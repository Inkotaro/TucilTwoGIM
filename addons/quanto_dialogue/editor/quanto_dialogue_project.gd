class_name QuantoDialogueProject
extends RefCounted
## A dialogue project is a folder. The registry file marks it as a project:
##
##   <folder>/quanto_registry.json
##   <folder>/text/<map>.<locale>.json
##   <folder>/timelines/<id>.json
##
## "New Project" creates that layout, "Open Project" loads the registry from a folder.
## The registry itself (QuantoDialogueRegistry) doesn't care where it lives; everything
## about folders and layout is here.

const TEXT_DIR := "text"
const TIMELINES_DIR := "timelines"


static func registry_path(folder: String) -> String:
	return folder.path_join(QuantoDialogueRegistry.FILE_NAME)


static func is_project(folder: String) -> bool:
	return FileAccess.file_exists(registry_path(folder))


## Creates the folder layout and an empty registry. Never overwrites: if `folder` already
## holds a project, that project is opened instead (check is_project() first to tell
## the user). Never null; check `status` / `is_usable()`.
static func create(folder: String, source_locale := "en") -> QuantoDialogueRegistry:
	if folder.is_empty():
		return QuantoDialogueRegistry.load_file("")  # MISSING, "path is not set"
	if is_project(folder):
		return QuantoDialogueRegistry.load_file(registry_path(folder))
	DirAccess.make_dir_recursive_absolute(folder.path_join(TEXT_DIR))
	DirAccess.make_dir_recursive_absolute(folder.path_join(TIMELINES_DIR))
	return QuantoDialogueRegistry.create_new(registry_path(folder), source_locale)


## Loads the project in `folder` (a path to the registry file itself also works).
## Never null; check `status` / `is_usable()`.
static func open(folder: String) -> QuantoDialogueRegistry:
	if folder.ends_with(".json"):
		return QuantoDialogueRegistry.load_file(folder)
	return QuantoDialogueRegistry.load_file(registry_path(folder))


static func folder_of(reg: QuantoDialogueRegistry) -> String:
	return reg.path.get_base_dir()


static func name_of(reg: QuantoDialogueRegistry) -> String:
	return folder_of(reg).get_file()


static func text_dir(reg: QuantoDialogueRegistry) -> String:
	return folder_of(reg).path_join(TEXT_DIR)


## Where new timelines are saved by default.
static func timelines_dir(reg: QuantoDialogueRegistry) -> String:
	return folder_of(reg).path_join(TIMELINES_DIR)


## Turns a path from a file dialog into the form the project uses: inside the project
## folder -> "<project folder>/...", inside the Godot project -> "res://...",
## anything else unchanged. Keeps registry entries relative and portable.
static func localize(reg: QuantoDialogueRegistry, path: String) -> String:
	var folder := folder_of(reg)
	var folder_abs := ProjectSettings.globalize_path(folder).simplify_path()
	var p := path.simplify_path()
	if p.begins_with(folder_abs + "/"):
		return folder.path_join(p.trim_prefix(folder_abs + "/"))
	return ProjectSettings.localize_path(path)
