class_name QuantoDialogueLocator
extends RefCounted
## Finds the dialogue project (its registry) and keeps the per-user editor settings that
## go with it (current project, recent projects, export prefix, open tabs).
## Registry priority:
##   1. runtime override  (QuantoDialogueLocator.runtime_path, set by game code)
##   2. inside Godot: the current project (a folder, see QuantoDialogueProject)
##   3. exported game: the shipped registry in res://dialogue (read-only), if present
## There is no default project: until one is created or opened, load_registry() returns
## an unusable registry whose status_message says so.
## Everything the editor writes about itself lives in user://, so it stays out of git.

enum Source { RUNTIME, USER, DEFAULT }

const CONFIG_PATH := "user://quanto_dialogue.cfg"
const MAX_RECENT := 8
## Read-only registry packed into the exported game. Written by the Text Editor's
## "Export to project" button.
const SHIPPED_PATH := "res://dialogue/" + QuantoDialogueRegistry.FILE_NAME
## Default prefix written into exported registry templates.
const DEFAULT_EXPORT_PREFIX := "res://dialogue/text"

## Full path of a registry file; set by game code to override everything else.
static var runtime_path := ""


## True in an exported game (debug or release template). False when running inside
## Godot (editor or "Run project" from the editor), where res:// is a real folder.
static func is_exported() -> bool:
	return OS.has_feature("template")


## res:// can only be written when not exported.
static func can_write_project() -> bool:
	return not is_exported()


## "" when there is no project (nothing chosen yet, or no shipped registry in a build).
static func resolve_path() -> String:
	if not runtime_path.is_empty():
		return runtime_path
	if not is_exported():
		var folder := current_project()
		return QuantoDialogueProject.registry_path(folder) if not folder.is_empty() else ""
	# Exported game: use the shipped registry.
	return SHIPPED_PATH if FileAccess.file_exists(SHIPPED_PATH) else ""


static func source() -> Source:
	if not runtime_path.is_empty():
		return Source.RUNTIME
	if not is_exported() and not current_project().is_empty():
		return Source.USER
	return Source.DEFAULT


## Loads whatever resolve_path() points at. Never null; check `status`.
## Without a project the registry is unusable (MISSING) and nothing is created.
static func load_registry() -> QuantoDialogueRegistry:
	var path := resolve_path()
	if path.is_empty():
		var none := QuantoDialogueRegistry.new()
		none.status = QuantoDialogueRegistry.Status.MISSING
		none.status_message = "No dialogue project: create or open one" if not is_exported() \
				else "No dialogue registry found in the game (expected %s)" % SHIPPED_PATH
		return none
	var reg := QuantoDialogueRegistry.load_file(path)
	if reg.is_usable():
		add_recent(QuantoDialogueProject.folder_of(reg))
	return reg


# --- current project ----------------------------------------------------------
## Folder of the project the editor uses, "" = none chosen yet.
static func current_project() -> String:
	return str(_read().get_value("textmap", "project", ""))


## Empty string = no project.
static func set_current_project(folder: String) -> void:
	var cfg := _read()
	cfg.set_value("textmap", "project", folder)
	cfg.save(CONFIG_PATH)


# --- start-up dialog ----------------------------------------------------------
static func show_startup_dialog() -> bool:
	return bool(_read().get_value("textmap", "show_startup_dialog", true))


static func set_show_startup_dialog(on: bool) -> void:
	var cfg := _read()
	cfg.set_value("textmap", "show_startup_dialog", on)
	cfg.save(CONFIG_PATH)


# --- export prefix ------------------------------------------------------------
## Prefix written into the templates of an exported registry.
## "text" = relative to the registry; "res://dialogue/text" etc. = absolute.
static func export_prefix() -> String:
	var p := str(_read().get_value("textmap", "export_prefix", DEFAULT_EXPORT_PREFIX)).strip_edges()
	return p if not p.is_empty() else DEFAULT_EXPORT_PREFIX


## Empty string resets to the default.
static func set_export_prefix(prefix: String) -> void:
	var cfg := _read()
	cfg.set_value("textmap", "export_prefix", prefix.strip_edges())
	cfg.save(CONFIG_PATH)


# --- open tabs (session) ------------------------------------------------------
## Timeline ids that were open as tabs, remembered per registry file.
static func open_timelines(registry_path: String) -> PackedStringArray:
	var d = _read().get_value("session", registry_path.md5_text(), {})
	var out := PackedStringArray()
	if d is Dictionary and d.get("ids") is Array:
		for id in d["ids"]:
			out.append(str(id))
	return out


static func active_timeline(registry_path: String) -> String:
	var d = _read().get_value("session", registry_path.md5_text(), {})
	return str(d.get("active", "")) if d is Dictionary else ""


static func set_open_timelines(registry_path: String, ids: PackedStringArray, active: String) -> void:
	var cfg := _read()
	cfg.set_value("session", registry_path.md5_text(), {"ids": Array(ids), "active": active})
	cfg.save(CONFIG_PATH)


# --- recent projects ----------------------------------------------------------
## Project folders, most recent first.
static func recent() -> PackedStringArray:
	var raw = _read().get_value("textmap", "recent_projects", PackedStringArray())
	return PackedStringArray(raw) if raw is Array or raw is PackedStringArray else PackedStringArray()


static func add_recent(folder: String) -> void:
	if folder.is_empty():
		return
	var list := recent()
	var i := list.find(folder)
	if i != -1:
		list.remove_at(i)
	list.insert(0, folder)
	while list.size() > MAX_RECENT:
		list.remove_at(list.size() - 1)
	var cfg := _read()
	cfg.set_value("textmap", "recent_projects", list)
	cfg.save(CONFIG_PATH)


static func clear_recent() -> void:
	var cfg := _read()
	cfg.set_value("textmap", "recent_projects", PackedStringArray())
	cfg.save(CONFIG_PATH)


static func remove_recent(folder: String) -> void:
	var list := recent()
	var i := list.find(folder)
	if i == -1:
		return
	list.remove_at(i)
	var cfg := _read()
	cfg.set_value("textmap", "recent_projects", list)
	cfg.save(CONFIG_PATH)


static func _read() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)  # a missing file is fine
	return cfg
