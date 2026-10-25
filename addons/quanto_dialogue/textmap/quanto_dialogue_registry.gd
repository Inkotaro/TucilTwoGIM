@tool
class_name QuantoDialogueRegistry
extends RefCounted
## Project registry of everything a dialogue project consists of:
##   maps      map_id      -> TextMap file template (one file per locale)
##   timelines timeline_id -> timeline file path
##
## Timelines reference a map_id, never a path, so moving or swapping the TextMap doesn't
## touch any timeline. Game code loads timelines by id, so moving a timeline file only
## means updating this registry.
##
##   { "format": 2, "source_locale": "en", "default_map": "main",
##     "maps": { "main": "text/main.{locale}.json" },
##     "timelines": { "intro": "timelines/intro.json" } }
##
## Templates and paths may be absolute ("res://", "user://", "/abs", "C:/") or relative to
## the registry file, so the whole folder can be moved or swapped as a unit.

const FORMAT_VERSION := 2
const LOCALE_TOKEN := "{locale}"
const DEFAULT_TEMPLATE := "text/main.{locale}.json"
## Name of the registry file inside a project folder (see QuantoDialogueProject).
const FILE_NAME := "quanto_registry.json"
## Sub-folders used by publish_to().
const PUBLISH_SUBDIR := "text"
const PUBLISH_TIMELINES_SUBDIR := "timelines"

enum Status { OK, MISSING, UNREADABLE }

var source_locale := "en"
var default_map := "main"
var path := ""  ## where this registry was loaded from / saves to
var status := Status.OK
var status_message := ""

var _maps: Dictionary = {}       ## map_id -> template
var _timelines: Dictionary = {}  ## timeline_id -> path (as stored: absolute or relative)


## Never returns null. Check `status` / `is_usable()`.
static func load_file(p_path: String) -> QuantoDialogueRegistry:
	var reg := QuantoDialogueRegistry.new()
	reg.path = p_path
	if p_path.is_empty():
		reg._fail(Status.MISSING, "Registry path is not set")
		return reg
	if not FileAccess.file_exists(p_path):
		reg._fail(Status.MISSING, "Registry not found: %s" % p_path)
		return reg
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(p_path))
	if not parsed is Dictionary:
		reg._fail(Status.UNREADABLE, "Registry is not valid JSON: %s" % p_path)
		return reg
	if int(parsed.get("format", 0)) > FORMAT_VERSION:
		reg._fail(Status.UNREADABLE, "Registry was written by a newer version: %s" % p_path)
		return reg
	reg.source_locale = str(parsed.get("source_locale", "en"))
	reg.default_map = str(parsed.get("default_map", "main"))
	var maps = parsed.get("maps", {})
	if maps is Dictionary:
		for id: String in maps:
			reg.register(id, str(maps[id]))
	var timelines = parsed.get("timelines", {})
	if timelines is Dictionary:
		for id: String in timelines:
			reg.register_timeline(id, str(timelines[id]))
	return reg


## Creates and writes a new, empty registry. Status is UNREADABLE if writing failed.
static func create_new(p_path: String, p_source_locale := "en") -> QuantoDialogueRegistry:
	var reg := QuantoDialogueRegistry.new()
	reg.path = p_path
	reg.source_locale = p_source_locale
	reg.register(reg.default_map, DEFAULT_TEMPLATE)
	var err := reg.save_file()
	if err != OK:
		reg._fail(Status.UNREADABLE, "Cannot write registry %s (error %d)" % [p_path, err])
	return reg


func is_usable() -> bool:
	return status == Status.OK


## Saves to `to`, or to `path` when empty. Relative entries are NOT rewritten, so
## "Save as" to another folder only works if the files move with it.
func save_file(to := "") -> Error:
	if not to.is_empty():
		path = to
	if path.is_empty():
		return ERR_FILE_BAD_PATH
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var text := '{\n"format": %d,\n"source_locale": %s,\n"default_map": %s,\n"maps": {\n%s\n},\n"timelines": {\n%s\n}\n}\n' % [
			FORMAT_VERSION, JSON.stringify(source_locale), JSON.stringify(default_map),
			_dict_lines(_maps), _dict_lines(_timelines)]
	var err := TextMapFile.write_atomic(path, text)
	if err == OK:
		status = Status.OK
		status_message = ""
	return err


func _dict_lines(d: Dictionary) -> String:
	var ids := PackedStringArray(d.keys())
	ids.sort()
	var lines := PackedStringArray()
	for id in ids:
		lines.append("%s: %s" % [JSON.stringify(id), JSON.stringify(d[id])])
	return ",\n".join(lines)


# --- maps ---------------------------------------------------------------------
## The template must contain "{locale}" so each locale gets its own file.
func register(map_id: String, template: String) -> bool:
	if not TextMap.is_valid_id(map_id) or not template.contains(LOCALE_TOKEN):
		push_warning("QuantoDialogueRegistry: bad map '%s' / template '%s'" % [map_id, template])
		return false
	_maps[map_id] = template
	return true


func unregister(map_id: String) -> void:
	_maps.erase(map_id)


func has_map(map_id: String) -> bool:
	return _maps.has(map_id)


func map_ids() -> PackedStringArray:
	var ids := PackedStringArray(_maps.keys())
	ids.sort()
	return ids


func template_of(map_id: String) -> String:
	return String(_maps.get(map_id, ""))


# --- timelines ----------------------------------------------------------------
## Registers a timeline file under an explicit id. `file_path` may be absolute or
## relative to the registry.
func register_timeline(timeline_id: String, file_path: String) -> bool:
	if not TextMap.is_valid_id(timeline_id) or file_path.is_empty():
		push_warning("QuantoDialogueRegistry: bad timeline '%s' / path '%s'" % [timeline_id, file_path])
		return false
	_timelines[timeline_id] = file_path
	return true


## Registers `file_path` and returns its id. If the file is already registered, returns
## the existing id. Otherwise the id comes from the file name (made valid, and made
## unique with a numeric suffix). The path is stored relative to the registry when the
## file lies below it. Call save_file() afterwards to persist.
func register_timeline_file(file_path: String) -> String:
	var wanted := file_path.simplify_path()
	for id: String in _timelines:
		if resolve_template(String(_timelines[id])).simplify_path() == wanted:
			return id
	var base := _sanitize_id(file_path.get_file().get_basename())
	var id := base
	var n := 2
	while _timelines.has(id):
		id = "%s_%d" % [base, n]
		n += 1
	_timelines[id] = _make_relative(file_path)
	return id


func unregister_timeline(timeline_id: String) -> void:
	_timelines.erase(timeline_id)


## Changes a timeline's id, keeping its file. False if `old_id` is unknown, `new_id` is
## invalid, or `new_id` is already taken. Timelines don't store their own id, so
## nothing else needs updating.
func rename_timeline(old_id: String, new_id: String) -> bool:
	if not _timelines.has(old_id) or not TextMap.is_valid_id(new_id) or _timelines.has(new_id):
		return false
	_timelines[new_id] = _timelines[old_id]
	_timelines.erase(old_id)
	return true


func has_timeline(timeline_id: String) -> bool:
	return _timelines.has(timeline_id)


func timeline_ids() -> PackedStringArray:
	var ids := PackedStringArray(_timelines.keys())
	ids.sort()
	return ids


## The id `file_path` is registered under, or "" if it is not registered.
func timeline_id_of_file(file_path: String) -> String:
	var wanted := file_path.simplify_path()
	for id: String in _timelines:
		if resolve_template(String(_timelines[id])).simplify_path() == wanted:
			return id
	return ""


## Resolved path of a timeline file, or "" for an unknown id.
func timeline_path(timeline_id: String) -> String:
	if not _timelines.has(timeline_id):
		return ""
	return resolve_template(String(_timelines[timeline_id]))


## Loads a timeline by id. Null for unknown ids and for files that can't be loaded
## (DialogueDataResource.load_file warns with the reason).
func open_timeline(timeline_id: String) -> DialogueDataResource:
	var file := timeline_path(timeline_id)
	if file.is_empty():
		push_warning("QuantoDialogueRegistry: unknown timeline '%s'" % timeline_id)
		return null
	return DialogueDataResource.load_file(file)


# --- paths --------------------------------------------------------------------
## Absolute-or-relative template/path -> a path usable with FileAccess.
func resolve_template(template: String) -> String:
	if template.is_absolute_path() or path.is_empty():
		return template
	return path.get_base_dir().path_join(template)


func path_for(map_id: String, locale: String) -> String:
	if not _maps.has(map_id):
		return ""
	return resolve_template(String(_maps[map_id]).replace(LOCALE_TOKEN, locale))


## For "Relocate"/"Import": turns a picked file like ".../chapter1.en.json" into a template
## ("chapter1.{locale}.json"), relative to the registry when it lies below it.
## Returns "" if the file name doesn't contain ".<locale>.".
func template_from_file(file_path: String, locale: String) -> String:
	var file_name := file_path.get_file()
	var marker := ".%s." % locale
	if not file_name.contains(marker):
		return ""
	var tpl := file_path.get_base_dir().path_join(file_name.replace(marker, ".%s." % LOCALE_TOKEN))
	return _make_relative(tpl)


## `p` relative to the registry folder when it lies below it, else unchanged.
func relative_path(p: String) -> String:
	return _make_relative(p)


func _make_relative(p: String) -> String:
	if path.is_empty():
		return p
	var base := path.get_base_dir()
	var prefix := base if base.ends_with("/") else base + "/"
	return p.trim_prefix(prefix) if p.begins_with(prefix) else p


func _sanitize_id(raw: String) -> String:
	var out := ""
	for c in raw:
		out += c if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") \
				or (c >= "0" and c <= "9") or c == "_" or c == "." or c == "-" else "_"
	return out if not out.is_empty() else "timeline"


# --- map files ----------------------------------------------------------------
## Loads the map for `locale`, or returns a fresh empty one if its file doesn't exist yet.
## Returns null for unknown map ids and for files that exist but can't be read.
func open_map(map_id: String, locale := "") -> TextMap:
	if locale.is_empty():
		locale = source_locale
	var file := path_for(map_id, locale)
	if file.is_empty():
		push_warning("QuantoDialogueRegistry: unknown map '%s'" % map_id)
		return null
	if not FileAccess.file_exists(file):
		return TextMap.new(map_id, locale)
	return TextMapFile.load_file(file)


func save_map(map: TextMap) -> Error:
	var file := path_for(map.map_id, map.locale)
	if file.is_empty():
		return ERR_DOES_NOT_EXIST
	DirAccess.make_dir_recursive_absolute(file.get_base_dir())
	return TextMapFile.save(map, file)


## Locales that have a file on disk for `map_id` (scans the template's folder).
## If "{locale}" is in a folder name (not the file name) only the source locale is checked.
func locales_of(map_id: String) -> PackedStringArray:
	var found := PackedStringArray()
	if not _maps.has(map_id):
		return found
	var tpl := String(_maps[map_id])
	var file_part := tpl.get_file()
	if not file_part.contains(LOCALE_TOKEN):
		if FileAccess.file_exists(path_for(map_id, source_locale)):
			found.append(source_locale)
		return found
	var parts := file_part.split(LOCALE_TOKEN, true, 1)
	for f in DirAccess.get_files_at(resolve_template(tpl).get_base_dir()):
		if f.length() > parts[0].length() + parts[1].length() \
				and f.begins_with(parts[0]) and f.ends_with(parts[1]):
			found.append(f.substr(parts[0].length(), f.length() - parts[0].length() - parts[1].length()))
	return found


# --- publishing ---------------------------------------------------------------
## Copies this registry, all its map files (every locale) and all its timelines into `dir`.
## Map files land in `<dir>/text/<map>.<locale>.json`, timelines in
## `<dir>/timelines/<timeline_id>.json`. Existing files there are overwritten.
##
## `template_prefix` is what the new registry stores for the text folder: "text" (relative,
## self-contained), "res://dialogue/text" or "user://mods/story/text" (absolute, for when you
## copy the files there yourself). The timelines folder is written next to it, e.g.
## "res://dialogue/text" -> "res://dialogue/timelines".
##
## Timelines that can't be loaded or whose map_id isn't registered are skipped with a warning.
## Returns the number of files copied, or -1 if the registry could not be written.
## res:// is only writable when running inside Godot.
func publish_to(dir: String, template_prefix := PUBLISH_SUBDIR) -> int:
	var prefix := template_prefix.strip_edges().replace("\\", "/").rstrip("/")
	if prefix.is_empty():
		prefix = PUBLISH_SUBDIR
	var tl_prefix := prefix.get_base_dir().path_join(PUBLISH_TIMELINES_SUBDIR)

	var out := QuantoDialogueRegistry.new()
	out.path = dir.path_join(FILE_NAME)
	out.source_locale = source_locale
	out.default_map = default_map
	var copied := 0

	for id in map_ids():
		out.register(id, "%s/%s.%s.json" % [prefix, id, LOCALE_TOKEN])
		for loc in locales_of(id):
			var dst := dir.path_join(PUBLISH_SUBDIR).path_join("%s.%s.json" % [id, loc])
			var err := _copy_file(path_for(id, loc), dst)
			if err == OK:
				copied += 1
			else:
				push_warning("QuantoDialogueRegistry: could not publish map %s/%s (error %d)" % [id, loc, err])

	for id in timeline_ids():
		var data := open_timeline(id)  # warns if unreadable
		if data == null:
			continue
		if not has_map(data.map_id):
			push_warning("QuantoDialogueRegistry: timeline '%s' uses map '%s' which is not registered; skipped" % [id, data.map_id])
			continue
		var dst := dir.path_join(PUBLISH_TIMELINES_SUBDIR).path_join("%s.json" % id)
		var err := _copy_file(timeline_path(id), dst)
		if err == OK:
			out.register_timeline(id, "%s/%s.json" % [tl_prefix, id])
			copied += 1
		else:
			push_warning("QuantoDialogueRegistry: could not publish timeline %s (error %d)" % [id, err])

	return copied if out.save_file() == OK else -1


func _copy_file(src: String, dst: String) -> Error:
	if not FileAccess.file_exists(src):
		return ERR_FILE_NOT_FOUND
	var data := FileAccess.get_file_as_bytes(src)
	DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(data)
	return OK


func _fail(p_status: Status, message: String) -> void:
	status = p_status
	status_message = message
	push_warning("QuantoDialogueRegistry: " + message)
