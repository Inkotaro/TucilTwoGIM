@tool
class_name TimelineTextSession
extends RefCounted
## Text-side state of the editor: TextMap registry, store, working maps, lock state.
## Knows nothing about the UI.

enum State { OK, NO_REGISTRY, UNBOUND, MAP_UNREADABLE }
enum MigrateMode { COPY, DISCARD, KEEP }

const DRAFT := "DRAFT_"
const MAP_TEMPLATE := "text/%s.{locale}.json"

var registry: QuantoDialogueRegistry
var store: TextMapStore

var _work_maps: Dictionary = {}   ## map_id -> TextMap (provided to the store)
var _unreadable: Dictionary = {}  ## map_id -> true


func _init() -> void:
	registry = QuantoDialogueLocator.load_registry()
	store = TextMapStore.new(registry)


static func prefix_for(path: String) -> String:
	if path.is_empty():
		return DialogueBlock.DRAFT_PREFIX
	return TextMap.make_prefix(path.get_file().get_basename())


# --- state --------------------------------------------------------------------
func state_of(map_id: String) -> State:
	if not registry.is_usable():
		return State.NO_REGISTRY
	if not registry.has_map(map_id):
		return State.UNBOUND
	if _unreadable.has(map_id):
		return State.MAP_UNREADABLE
	return State.OK


## Number of own-map ids used by the tab that the working map doesn't have.
func count_missing(tab: TimelineTab) -> int:
	var map: TextMap = _work_maps.get(tab.map_id)
	if map == null or state_of(tab.map_id) != State.OK:
		return 0
	var ids := {}
	TextBinding.collect_ids(tab.events, ids)
	var n := 0
	for id: String in ids:
		if not id.begins_with(DRAFT) and not map.has(id):
			n += 1
	return n


## Points the blocks' static context at this tab. Run before event_list.from_array().
func enter(tab: TimelineTab) -> State:
	if tab.map_id.is_empty():
		tab.map_id = registry.default_map
	var map := _ensure_map(tab.map_id)
	if tab.resolver == null:
		tab.resolver = TimelineTextResolver.new(store, tab.map_id, tab.imports)
	var state := state_of(tab.map_id)
	DialogueBlock.text_map = map
	DialogueBlock.id_prefix = prefix_for(tab.path)
	DialogueBlock.resolver = tab.resolver
	DialogueBlock.store = store
	DialogueBlock.text_locked = state != State.OK
	return state


func _ensure_map(map_id: String) -> TextMap:
	if _work_maps.has(map_id):
		return _work_maps[map_id]
	var map: TextMap = null
	if registry.is_usable() and registry.has_map(map_id):
		map = registry.open_map(map_id)
		if map == null:
			_unreadable[map_id] = true
			push_error("TimelineTextSession: map '%s' is unreadable" % map_id)
	if map == null:
		map = TextMap.new(map_id, registry.source_locale)  # empty stand-in
	_work_maps[map_id] = map
	store.provide(map)
	return map


# --- undo ---------------------------------------------------------------------
func begin_recording() -> void:
	if DialogueBlock.text_map:
		DialogueBlock.text_map.begin_recording()


func end_recording() -> Dictionary:
	return DialogueBlock.text_map.end_recording() if DialogueBlock.text_map else {}


func apply_delta(delta: Dictionary, reverse: bool) -> void:
	if DialogueBlock.text_map:
		DialogueBlock.text_map.apply_delta(delta, reverse)


# --- saving -------------------------------------------------------------------
## Draft ids become <PREFIX>_<n>. On Save As to a new path every other own id is
## copied too, so two files never share an id. Returns old id -> new id; the caller
## must remap the events. Recording is ended only when there is work to do, and the
## caller must call begin_recording() again after rebuilding the list.
func assign_ids(tab: TimelineTab, path: String) -> Dictionary:
	var prefix := prefix_for(path)
	if prefix == DialogueBlock.DRAFT_PREFIX:
		return {}
	var copying := not tab.path.is_empty() and tab.path != path
	var ids := {}
	TextBinding.collect_ids(tab.events, ids)
	var todo: Array[String] = []
	for id: String in ids:
		if id.begins_with(DRAFT) or copying:
			todo.append(id)
	if todo.is_empty():
		return {}
	end_recording()
	var map := DialogueBlock.text_map
	var mapping := {}
	for old in todo:
		var fresh := map.generate_id(prefix)
		if old.begins_with(DRAFT) and map.has(old):
			map.rename(old, fresh)
		else:
			map.set_text(fresh, map.get_text(old))
		mapping[old] = fresh
	return mapping


func working_map(map_id: String) -> TextMap:
	return _ensure_map(map_id)


func save_text() -> Error:
	return save_working(DialogueBlock.text_map)


## Saves any working map. Drafts are hidden during the save so they never hit disk.
func save_working(map: TextMap) -> Error:
	var drafts := {}
	for id: String in map.entries.keys():
		if id.begins_with(DRAFT):
			drafts[id] = map.entries[id]
			map.forget(id)
	var err := registry.save_map(map)
	for id: String in drafts:
		map.put_silent(id, drafts[id])
	return err


## After the registry changed (relocate/remove). False if unsaved text would be lost.
func reload_maps() -> bool:
	if has_dirty():
		return false
	store.clear_provided()
	_work_maps.clear()
	_unreadable.clear()
	store.set_registry(registry)  # clears the cache and re-opens held maps
	return true


# --- registry changes ---------------------------------------------------------
func has_dirty() -> bool:
	for m: TextMap in _work_maps.values():
		if m.is_dirty():
			return true
	return false


## Registers `map_id` in the current registry and saves it.
func register_map(map_id: String) -> bool:
	if not (registry.register(map_id, MAP_TEMPLATE % map_id) and registry.save_file() == OK):
		return false
	_drop_map(map_id)
	return true


## Swaps the TextMap. The caller must have checked has_dirty() and flushed the editor.
func adopt(reg: QuantoDialogueRegistry, tabs: Array) -> void:
	for t: TimelineTab in tabs:
		_release_resolver(t)
	store.clear_provided()
	_work_maps.clear()
	_unreadable.clear()
	registry = reg
	store.set_registry(reg)


# --- switching a timeline to another map --------------------------------------
## Read-only summary shown before the user confirms. "error" is non-empty if switching is impossible.
func preview_migration(tab: TimelineTab, target_id: String) -> Dictionary:
	var out := {"error": "", "own": 0, "drafts": 0, "same": 0, "collisions": 0,
			"unknown": 0, "locales": 0}
	var old_id := tab.map_id if not tab.map_id.is_empty() else registry.default_map
	if not registry.has_map(target_id):
		out.error = "Map '%s' is not in the registry." % target_id
		return out
	var old := _ensure_map(old_id)
	var target := _ensure_map(target_id)
	if state_of(target_id) != State.OK or state_of(old_id) != State.OK:
		out.error = "Map '%s' or '%s' is not readable." % [old_id, target_id]
		return out
	var ids := {}
	TextBinding.collect_ids(tab.events, ids)
	for id: String in ids:
		if not old.has(id):
			out.unknown += 1
		elif id.begins_with(DRAFT):
			out.drafts += 1
		else:
			out.own += 1
			if target.has(id):
				if target.get_text(id) == old.get_text(id):
					out.same += 1
				else:
					out.collisions += 1
	out.locales = registry.locales_of(old_id).size()
	return out


## Moves a tab from its current map to `target_id`.
##   COPY    own strings are copied into the target (all locales), events remapped.
##   DISCARD string references become empty drafts; nothing is copied.
##   KEEP    only switches; ids the target lacks show as missing.
## `remap` is a Callable(mapping: Dictionary) that rewrites old id -> new id in tab.events.
## On failure the tab is restored and nothing is written to disk.
## On success the caller rebuilds the event list and resets undo.
func migrate_tab(tab: TimelineTab, target_id: String, mode: MigrateMode, remap: Callable) -> Dictionary:
	var report := {"ok": false, "message": "", "copied": 0, "reused": 0, "renamed": 0,
			"discarded": 0, "unknown": 0, "locales": 0, "mapping": {}}
	var old_id := tab.map_id if not tab.map_id.is_empty() else registry.default_map
	if target_id == old_id:
		report.message = "The timeline already uses '%s'." % target_id
		return report
	var had_target := _work_maps.has(target_id)
	var pre := preview_migration(tab, target_id)
	if not String(pre.error).is_empty():
		report.message = pre.error
		return report
	var old := _ensure_map(old_id)
	var target := _ensure_map(target_id)

	# 1. decide ids and apply them to the target map in memory only
	var ids := {}
	TextBinding.collect_ids(tab.events, ids)
	var prefix := prefix_for(tab.path)
	var mapping := {}
	var own: Array[String] = []
	if mode != MigrateMode.KEEP:
		for id: String in ids:
			if not old.has(id):
				report.unknown += 1
				continue
			if mode == MigrateMode.DISCARD:
				var blank := target.generate_id(DialogueBlock.DRAFT_PREFIX)
				target.set_text(blank, "")
				mapping[id] = blank
				report.discarded += 1
			elif id.begins_with(DRAFT):
				var draft := target.generate_id(DialogueBlock.DRAFT_PREFIX)
				target.set_text(draft, old.get_text(id))
				mapping[id] = draft
				report.copied += 1
			else:
				var text := old.get_text(id)
				own.append(id)
				if not target.has(id):
					target.set_text(id, text)
					report.copied += 1
				elif target.get_text(id) == text:
					report.reused += 1
				else:
					var fresh := target.generate_id(prefix)
					target.set_text(fresh, text)
					mapping[id] = fresh
					report.renamed += 1

	# 2. switch the tab
	if not mapping.is_empty():
		remap.call(mapping)
	_release_resolver(tab)
	tab.map_id = target_id
	var state := enter(tab)

	# 3. verify, then write
	var fail := ""
	if state != State.OK:
		fail = "Target map is not usable after switching."
	elif mode != MigrateMode.KEEP and count_missing(tab) > report.unknown:
		fail = "Some strings are still missing in '%s'." % target_id
	elif mode == MigrateMode.COPY:
		var err := save_working(target)
		if err != OK:
			fail = "Could not save '%s' (error %d)." % [target_id, err]
	if not fail.is_empty():
		_rollback(tab, old_id, target_id, mapping, remap, had_target)
		report.message = "Switch failed, nothing changed: " + fail
		return report
	if mode == MigrateMode.COPY:
		report.locales = _copy_locales(old_id, target_id, own, mapping)

	report.ok = true
	report.mapping = mapping
	report.message = _describe_migration(report, mode, old_id, target_id)
	return report


func _describe_migration(r: Dictionary, mode: MigrateMode, from_id: String, to_id: String) -> String:
	var text := "Now using '%s' (was '%s'). " % [to_id, from_id]
	match mode:
		MigrateMode.COPY:
			text += "Copied %d, reused %d, renamed %d, other locales %d." % [
					r.copied, r.reused, r.renamed, r.locales]
		MigrateMode.DISCARD:
			text += "Discarded %d string reference(s)." % r.discarded
		_:
			text += "Ids kept as they were."
	if r.unknown > 0:
		text += " %d id(s) were already missing in the old map." % r.unknown
	return text


func _rollback(tab: TimelineTab, old_id: String, target_id: String,
		mapping: Dictionary, remap: Callable, had_target: bool) -> void:
	if not mapping.is_empty():
		var inverse := {}
		for k in mapping:
			inverse[mapping[k]] = k
		remap.call(inverse)
	_release_resolver(tab)
	tab.map_id = old_id
	if not had_target:
		_drop_map(target_id)  # discard the half-built target; disk was never written
	enter(tab)


func _release_resolver(tab: TimelineTab) -> void:
	if tab.resolver:
		tab.resolver.release()
		tab.resolver = null


func _drop_map(map_id: String) -> void:
	_work_maps.erase(map_id)
	_unreadable.erase(map_id)
	store.forget_map(map_id)


## Copies the non-source locales of the migrated strings. Existing target text is never overwritten.
func _copy_locales(old_id: String, target_id: String, ids: Array[String], mapping: Dictionary) -> int:
	var n := 0
	for loc in registry.locales_of(old_id):
		if loc == registry.source_locale:
			continue
		var src := registry.open_map(old_id, loc)
		var dst := registry.open_map(target_id, loc)
		if src == null or dst == null:
			continue
		var touched := false
		for id in ids:
			var new_id: String = mapping.get(id, id)
			if src.has(id) and not dst.has(new_id):
				dst.set_text(new_id, src.get_text(id))
				touched = true
		if touched and registry.save_map(dst) == OK:
			n += 1
	return n
