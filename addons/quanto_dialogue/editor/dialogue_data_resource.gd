class_name DialogueDataResource
extends Resource
## A timeline: its events plus the text map it reads from.
##
## File format (version 2), JSON, only non-empty fields are written:
##   { "version": 2, "map_id": "chapter1", "imports": ["common"],
##     "events": [ { "type": "line", "speaker": "Bob", "text_id": "TIMELINE_INTRO_1" },
##                 { "type": "choice", "options": [ { "text_id": "...", "events": [] } ] } ] }
##
## There is no migration: a file with any other version is rejected, not guessed at.
##
## Timelines are listed in the QuantoDialogueRegistry; in game, load them by id with
## load_by_id() instead of hard-coding file paths.

const FORMAT_VERSION := 2

@export var version: int = FORMAT_VERSION
## The text map this timeline owns. Plain ids resolve here.
@export var map_id: String = ""
## Other maps this timeline may reference as "map_id:ID". Nothing else resolves.
@export var imports: PackedStringArray = []
@export var events: Array[DialogueEvent] = []


static func empty(p_map_id := "") -> DialogueDataResource:
	var data := DialogueDataResource.new()
	data.map_id = p_map_id
	return data


## Loads a timeline registered in the registry under `timeline_id`.
## Uses `store`'s registry, default: TextMapStore.shared() (the same one the runner uses).
## Returns null for unknown ids and files that can't be loaded (a warning says why).
static func load_by_id(timeline_id: String, store: TextMapStore = null) -> DialogueDataResource:
	var s := store if store != null else TextMapStore.shared()
	return s.registry.open_timeline(timeline_id)


## Returns null (with a warning naming the problem) if the file can't be loaded.
## Never returns a half-parsed timeline, so a bad file can't be saved over by accident.
static func load_file(path: String) -> DialogueDataResource:
	if not FileAccess.file_exists(path):
		push_warning("DialogueData: %s does not exist" % path)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not json.data is Dictionary:
		push_warning("DialogueData: %s is not valid JSON (line %d: %s)" % [
			path, json.get_error_line(), json.get_error_message()])
		return null
	var parsed: Dictionary = json.data

	var file_version := int(parsed.get("version", 0))
	if file_version != FORMAT_VERSION:
		push_warning("DialogueData: %s has format version %d, expected %d" % [
			path, file_version, FORMAT_VERSION])
		return null

	var errors := PackedStringArray()
	var data := DialogueDataResource.new()

	var raw_map = parsed.get("map_id", "")
	if raw_map is String and TextMap.is_valid_id(raw_map):
		data.map_id = raw_map
	else:
		errors.append("map_id: missing or invalid")

	var raw_imports = parsed.get("imports", [])
	if raw_imports is Array:
		for imp in raw_imports:
			if imp is String and TextMap.is_valid_id(imp):
				data.imports.append(imp)
			else:
				errors.append("imports: invalid entry %s" % var_to_str(imp))
	else:
		errors.append("imports: expected array")

	data.events = _parse_events(parsed.get("events", []), errors, "events")

	if not errors.is_empty():
		push_warning("DialogueData: cannot load %s:\n  %s" % [path, "\n  ".join(errors)])
		return null
	return data


static func save_file(path: String, data: DialogueDataResource) -> bool:
	if not TextMap.is_valid_id(data.map_id):
		push_error("DialogueData: cannot save %s: map_id '%s' is not set or invalid" % [path, data.map_id])
		return false
	var dict_to_save := {
		"version": FORMAT_VERSION,
		"map_id": data.map_id,
		"events": _serialize_events(data.events),
	}
	if not data.imports.is_empty():
		dict_to_save["imports"] = Array(data.imports)

	var err := TextMapFile.write_atomic(path, JSON.stringify(dict_to_save, "\t", true) + "\n")
	if err != OK:
		push_error("DialogueData: cannot write %s (error %d)" % [path, err])
		return false
	return true


# --- parsing ------------------------------------------------------------------
## Problems are appended to `errors` as "events[3].options[1].events[0]: message".
static func _parse_events(arr: Variant, errors: PackedStringArray, where: String) -> Array[DialogueEvent]:
	var res: Array[DialogueEvent] = []
	if not arr is Array:
		errors.append("%s: expected array" % where)
		return res
	for i in arr.size():
		var at := "%s[%d]" % [where, i]
		var d = arr[i]
		if not d is Dictionary:
			errors.append("%s: expected object" % at)
			continue
		var type := DialogueEvent.type_from_name(str(d.get("type", "")))
		if type == -1:
			errors.append("%s: unknown type '%s'" % [at, d.get("type", "")])
			continue

		var ev := DialogueEvent.new(type as DialogueEvent.Type)
		ev.speaker = _get_str(d, "speaker", errors, at)
		ev.text_id = _get_str(d, "text_id", errors, at)
		ev.key = _get_str(d, "key", errors, at)
		ev.value = _get_str(d, "value", errors, at)

		var raw_options = d.get("options", [])
		if raw_options is Array:
			for j in raw_options.size():
				var opt_at := "%s.options[%d]" % [at, j]
				var o = raw_options[j]
				if not o is Dictionary:
					errors.append("%s: expected object" % opt_at)
					continue
				var choice := DialogueChoice.new()
				choice.text_id = _get_str(o, "text_id", errors, opt_at)
				choice.events = _parse_events(o.get("events", []), errors, opt_at + ".events")
				ev.options.append(choice)
		else:
			errors.append("%s.options: expected array" % at)

		ev.events = _parse_events(d.get("events", []), errors, at + ".events")
		res.append(ev)
	return res


static func _get_str(d: Dictionary, field: String, errors: PackedStringArray, at: String) -> String:
	var v = d.get(field, "")
	if v is String:
		return v
	errors.append("%s.%s: expected string" % [at, field])
	return ""


# --- serializing --------------------------------------------------------------
static func _serialize_events(arr: Array[DialogueEvent]) -> Array:
	var res := []
	for ev in arr:
		var d := {"type": DialogueEvent.get_type_name(ev.type)}
		for pair in [["speaker", ev.speaker], ["text_id", ev.text_id], ["key", ev.key], ["value", ev.value]]:
			if not pair[1].is_empty():
				d[pair[0]] = pair[1]
		if not ev.options.is_empty():
			var opts := []
			for opt in ev.options:
				var o := {}
				if not opt.text_id.is_empty():
					o["text_id"] = opt.text_id
				if not opt.events.is_empty():
					o["events"] = _serialize_events(opt.events)
				opts.append(o)
			d["options"] = opts
		if not ev.events.is_empty():
			d["events"] = _serialize_events(ev.events)
		res.append(d)
	return res
