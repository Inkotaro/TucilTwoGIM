class_name TextMap
extends RefCounted
## One locale of one text map: `id -> string`, plus dirty tracking, id generation
## and delta recording (for undo). Pure data, no editor or scene dependency.
##
## Ids are restricted to [A-Za-z0-9_.-] so ":" stays free for "map:id" references.

signal entry_changed(id: String, old_text: Variant, new_text: Variant)  ## null = absent

var map_id := ""
var locale := ""
var entries: Dictionary = {}        ## id -> String
var source_hashes: Dictionary = {}  ## id -> hash of the source text (translations only)

var _dirty: Dictionary = {}         ## id -> true (set or removed since last save)
var _next_suffix: Dictionary = {}   ## prefix -> last number handed out
var _recording := false
var _recorded: Dictionary = {}      ## id -> [old, new]

static var _id_regex: RegEx


func _init(p_map_id := "", p_locale := "") -> void:
	map_id = p_map_id
	locale = p_locale


# --- ids ----------------------------------------------------------------------
static func is_valid_id(id: String) -> bool:
	if _id_regex == null:
		_id_regex = RegEx.create_from_string("^[A-Za-z0-9_.\\-]+$")
	return _id_regex.search(id) != null


## "hell bob" -> "TIMELINE_HELL_BOB"
static func make_prefix(timeline_name: String) -> String:
	var s := ""
	for ch in timeline_name.to_upper():
		var ok := (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9")
		if ok:
			s += ch
		elif not s.ends_with("_"):
			s += "_"
	s = s.trim_prefix("_").trim_suffix("_")
	return "TIMELINE_" + (s if not s.is_empty() else "UNTITLED")


static func hash_text(text: String) -> String:
	return text.sha256_text().substr(0, 12)


## Next free "<prefix>_<n>". Highest existing suffix + 1, never reuses a number
## handed out during this session. Does not create the entry.
func generate_id(prefix: String) -> String:
	if not _next_suffix.has(prefix):
		var top := 0
		var head := prefix + "_"
		for id: String in entries:
			if id.begins_with(head):
				var tail := id.substr(head.length())
				if tail.is_valid_int():
					top = maxi(top, tail.to_int())
		_next_suffix[prefix] = top
	var id := ""
	while id.is_empty() or entries.has(id):
		_next_suffix[prefix] += 1
		id = "%s_%d" % [prefix, _next_suffix[prefix]]
	return id


# --- access -------------------------------------------------------------------
func has(id: String) -> bool:
	return entries.has(id)


func get_text(id: String, default := "") -> String:
	return entries.get(id, default)


func size() -> int:
	return entries.size()


## Returns false (and changes nothing) for an invalid id, true otherwise.
## `src_hash` is the hash of the source text a translation was written from.
func set_text(id: String, text: String, src_hash := "") -> bool:
	if not is_valid_id(id):
		push_warning("TextMap: invalid id '%s'" % id)
		return false
	_write(id, text)
	if not src_hash.is_empty() and source_hashes.get(id, "") != src_hash:
		source_hashes[id] = src_hash
		_dirty[id] = true
	return true


func remove(id: String) -> void:
	if entries.has(id):
		_write(id, null)
		source_hashes.erase(id)


## False if `old_id` is missing, `new_id` is invalid or `new_id` already exists.
func rename(old_id: String, new_id: String) -> bool:
	if not entries.has(old_id) or entries.has(new_id) or not is_valid_id(new_id):
		return false
	var text: String = entries[old_id]
	var h = source_hashes.get(old_id)
	_write(new_id, text)
	if h != null:
		source_hashes[new_id] = h
	remove(old_id)
	return true


## A translation is stale when its source text changed after it was written.
func is_stale(id: String, source_text: String) -> bool:
	return entries.has(id) and source_hashes.get(id, "") != hash_text(source_text)


func ids_sorted() -> PackedStringArray:
	var keys := PackedStringArray(entries.keys())
	keys.sort()
	return keys


# --- dirty tracking -----------------------------------------------------------
func is_dirty() -> bool:
	return not _dirty.is_empty()


func dirty_keys() -> Array:
	return _dirty.keys()


func clear_dirty() -> void:
	_dirty.clear()


# --- deltas (undo) ------------------------------------------------------------
## Everything written between begin and end is returned as {id: [old, new]},
## keeping the first old and the last new value per id. null = absent.
func begin_recording() -> void:
	_recording = true
	_recorded = {}


func end_recording() -> Dictionary:
	_recording = false
	var out := _recorded
	_recorded = {}
	return out


## reverse = true undoes the delta.
func apply_delta(delta: Dictionary, reverse := false) -> void:
	for id: String in delta:
		var pair: Array = delta[id]
		var value = pair[0] if reverse else pair[1]
		_write(id, value)
		if value == null:
			source_hashes.erase(id)


# --- file merge support -------------------------------------------------------
## Replace contents with `new_entries` (used after a merge-save). Emits
## entry_changed for every key whose value differs; does not mark anything dirty.
func absorb(new_entries: Dictionary, new_hashes: Dictionary) -> void:
	for id: String in entries.keys():
		if not new_entries.has(id):
			entry_changed.emit(id, entries[id], null)
	for id: String in new_entries:
		if entries.get(id) != new_entries[id]:
			entry_changed.emit(id, entries.get(id), new_entries[id])
	entries = new_entries.duplicate()
	source_hashes = new_hashes.duplicate()


# --- internals ----------------------------------------------------------------
## Single write path. `value == null` removes. Returns true if anything changed.
func _write(id: String, value: Variant) -> bool:
	var old: Variant = entries.get(id, null)
	if old == value:
		return false
	if value == null:
		entries.erase(id)
	else:
		entries[id] = value
	_dirty[id] = true
	if _recording:
		if _recorded.has(id):
			_recorded[id][1] = value
		else:
			_recorded[id] = [old, value]
	entry_changed.emit(id, old, value)
	return true

## Silent removal: no dirty flag, no recording, no signal. For transient draft ids.
func forget(id: String) -> void:
	entries.erase(id)
	source_hashes.erase(id)
	_dirty.erase(id)


## Silent insert, counterpart of forget().
func put_silent(id: String, text: String) -> void:
	entries[id] = text
