class_name QuantoDialogue
extends RefCounted
## In-game entry point: find and load every timeline in the registry.
## Uses TextMapStore.shared(), i.e. the registry QuantoDialogueLocator finds
## (the shipped one in an exported game), so the text lookup and the timelines
## always come from the same place.
##
##   QuantoDialogue.ids()                       # all timeline ids
##   QuantoDialogue.load_timeline("intro")      # one DialogueDataResource (cached)
##   QuantoDialogue.load_all()                  # { id: DialogueDataResource }
##   QuantoDialogue.set_locale("fr")

static var _cache: Dictionary = {}  ## timeline_id -> DialogueDataResource
static var _hooked_store: TextMapStore = null


static func registry() -> QuantoDialogueRegistry:
	return _store().registry


## False when no usable registry was found (check registry().status_message).
static func is_ready() -> bool:
	return _store().registry.is_usable()


static func ids() -> PackedStringArray:
	return _store().registry.timeline_ids()


static func has(timeline_id: String) -> bool:
	return _store().registry.has_timeline(timeline_id)


## Why `timeline_id` can't be played right now, or "" if it can. Checks the registry,
## the id and that the file exists (not that its content is valid; load_timeline does that).
static func error_for(timeline_id: String) -> String:
	var reg := _store().registry
	if not reg.is_usable():
		return "No usable registry: %s" % reg.status_message
	if not reg.has_timeline(timeline_id):
		return "Unknown timeline '%s' (registered: %s)" % [timeline_id, ", ".join(reg.timeline_ids())]
	var file := reg.timeline_path(timeline_id)
	if not FileAccess.file_exists(file):
		return "Timeline '%s' is registered but its file is missing: %s" % [timeline_id, file]
	return ""


## Null for unknown ids and files that can't be loaded (a warning says why).
## Results are cached; pass use_cache = false to re-read the file.
static func load_timeline(timeline_id: String, use_cache := true) -> DialogueDataResource:
	var store := _store()
	var err := error_for(timeline_id)
	if not err.is_empty():
		push_error("QuantoDialogue: " + err)  # unknown id, missing file or no registry
		return null
	if use_cache and _cache.has(timeline_id):
		return _cache[timeline_id]
	var data := store.registry.open_timeline(timeline_id)
	if data != null:
		_cache[timeline_id] = data
	return data


## Loads every registered timeline. Ones that fail are skipped (and warned about).
static func load_all(use_cache := true) -> Dictionary:
	var out := {}
	for id in ids():
		var data := load_timeline(id, use_cache)
		if data != null:
			out[id] = data
	return out


static func clear_cache() -> void:
	_cache.clear()


static func set_locale(locale: String) -> void:
	_store().set_locale(locale)


static func locale() -> String:
	return _store().locale


## Re-reads the registry and every file from disk (e.g. after replacing the files).
static func reload() -> void:
	clear_cache()
	_store().reload()


static func _store() -> TextMapStore:
	var store := TextMapStore.shared()
	if store != _hooked_store:  # first use, or the shared store was replaced
		if _hooked_store != null and _hooked_store.registry_changed.is_connected(clear_cache):
			_hooked_store.registry_changed.disconnect(clear_cache)
		store.registry_changed.connect(clear_cache)
		_hooked_store = store
		clear_cache()
	return store
