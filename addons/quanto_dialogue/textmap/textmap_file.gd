class_name TextMapFile
extends RefCounted
## Reads and writes TextMap files.
##
## Format: JSON, one entry per line, keys sorted, so git diffs and merges stay small.
##   { "format": 1, "map_id": "main", "locale": "en", "entries": {
##   "TIMELINE_A_1": "Hello",
##   "TIMELINE_A_2": {"text": "Hola", "src": "ab12cd34ef56"}   <- translations
##   } }
##
## save() MERGES: it re-reads the file on disk and applies only this map's dirty keys,
## so several writers (timelines, people) can touch the same map. If the same key
## changed in both places, this map wins. Writes are atomic (temp file + rename).

const FORMAT_VERSION := 1


## Returns null (with a warning) if the file is missing, corrupt or from a newer version.
static func load_file(path: String) -> TextMap:
	var parsed := _read_json(path)
	if parsed.is_empty():
		return null
	if int(parsed.get("format", 0)) > FORMAT_VERSION:
		push_warning("TextMapFile: %s was written by a newer version" % path)
		return null
	var map := TextMap.new(str(parsed.get("map_id", "")), str(parsed.get("locale", "")))
	var raw = parsed.get("entries", {})
	if not raw is Dictionary:
		push_warning("TextMapFile: %s has no valid entries" % path)
		return null
	for id: String in raw:
		var v = raw[id]
		if v is String:
			map.entries[id] = v
		elif v is Dictionary and v.get("text") is String:
			map.entries[id] = v["text"]
			if v.get("src") is String:
				map.source_hashes[id] = v["src"]
	return map


static func save(map: TextMap, path: String) -> Error:
	var entries: Dictionary
	var hashes: Dictionary
	if FileAccess.file_exists(path):
		var disk := load_file(path)
		if disk == null:
			return ERR_FILE_CORRUPT
		if disk.map_id != map.map_id or disk.locale != map.locale:
			push_warning("TextMapFile: %s belongs to %s/%s, not %s/%s" % [
				path, disk.map_id, disk.locale, map.map_id, map.locale])
			return ERR_INVALID_DATA
		entries = disk.entries
		hashes = disk.source_hashes
		for id: String in map.dirty_keys():
			if map.entries.has(id):
				entries[id] = map.entries[id]
				if map.source_hashes.has(id):
					hashes[id] = map.source_hashes[id]
				else:
					hashes.erase(id)
			else:
				entries.erase(id)
				hashes.erase(id)
	else:
		entries = map.entries.duplicate()
		hashes = map.source_hashes.duplicate()

	var err := write_atomic(path, serialize(map.map_id, map.locale, entries, hashes))
	if err == OK:
		map.absorb(entries, hashes)
		map.clear_dirty()
	return err


static func serialize(map_id: String, locale: String, entries: Dictionary, hashes: Dictionary) -> String:
	var keys := PackedStringArray(entries.keys())
	keys.sort()
	var lines := PackedStringArray()
	for id in keys:
		var value: String = entries[id]
		var encoded := JSON.stringify(value)
		if hashes.has(id):
			encoded = '{"text": %s, "src": %s}' % [encoded, JSON.stringify(hashes[id])]
		lines.append("%s: %s" % [JSON.stringify(id), encoded])
	return '{\n"format": %d,\n"map_id": %s,\n"locale": %s,\n"entries": {\n%s\n}\n}\n' % [
		FORMAT_VERSION, JSON.stringify(map_id), JSON.stringify(locale), ",\n".join(lines)]


## Writes to "<path>.tmp" then renames over `path`, so a crash never leaves a half file.
static func write_atomic(path: String, content: String) -> Error:
	var dir_err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if dir_err != OK:
		return dir_err
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(content)
	f.close()
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		DirAccess.remove_absolute(tmp)
	return err


static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("TextMapFile: %s does not exist" % path)
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_warning("TextMapFile: %s is not valid JSON" % path)
		return {}
	return parsed
