@tool
class_name QuantoRegistryEditor
extends AcceptDialog
## Edits a QuantoDialogueRegistry. Two tabs:
##   TextMaps   map id  -> file template, default map, switch the open timeline's map
##   Timelines  timeline id -> file, open / add / scan / rename / relocate / remove

signal changed
## The user wants the current timeline to use this map. Nothing is changed here:
## the host runs session.migrate_tab(), then calls set_current_map(map_id).
signal map_switch_requested(map_id: String)
## The user wants to open a registered timeline (double-click or "Open").
signal timeline_open_requested(timeline_id: String)

var registry: QuantoDialogueRegistry
var current_map_id := ""       ## the map the open timeline uses (shown as "in use")
var current_timeline_id := ""  ## the open timeline's registry id (shown as "open")

var _tabs := TabContainer.new()
var _info := Label.new()
var _notice := Label.new()

# TextMaps tab
var _map_tree := Tree.new()
var _map_edit := LineEdit.new()
var _switch_btn: Button
var _file_dialog := FileDialog.new()
var _save_dialog := FileDialog.new()
var _import_dialog := FileDialog.new()
var _relocating := ""
var _pending_id := ""

# Timelines tab
var _tl_tree := Tree.new()
var _tl_edit := LineEdit.new()
var _open_btn: Button
var _tl_add_dialog := FileDialog.new()
var _tl_scan_dialog := FileDialog.new()
var _tl_relocate_dialog := FileDialog.new()
var _tl_relocating := ""


func _init() -> void:
	title = "Dialogue Registry"
	ok_button_text = "Close"
	min_size = Vector2i(760, 500)
	var box := VBoxContainer.new()
	add_child(box)
	box.add_child(_info)

	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_tabs)
	_build_maps_tab()
	_build_timelines_tab()

	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_notice)


## `map_id`: the map the open timeline uses. `timeline_id`: its registry id ("" if unsaved).
func open(reg: QuantoDialogueRegistry, map_id := "", timeline_id := "") -> void:
	registry = reg
	current_map_id = map_id
	current_timeline_id = timeline_id
	_pending_id = ""
	_notice.text = ""
	_refresh()
	popup_centered()


## Call after the host has actually switched the timeline to `map_id`.
func set_current_map(map_id: String) -> void:
	current_map_id = map_id
	_refresh()


## Call when the open timeline changes while the dialog is visible.
func set_current_timeline(timeline_id: String) -> void:
	current_timeline_id = timeline_id
	_refresh()


## Lets the host show the result of a switch / migration.
func show_notice(text: String) -> void:
	_notice.text = text


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _refresh() -> void:
	_refresh_maps()
	_refresh_timelines()
	_info.text = "%s   |   source locale: %s   |   %d map(s), %d timeline(s)" % [
			registry.path, registry.source_locale,
			registry.map_ids().size(), registry.timeline_ids().size()]


func _commit() -> void:
	var err := registry.save_file()
	if err != OK:
		push_error("QuantoRegistryEditor: cannot save registry (error %d)" % err)
	_refresh()
	changed.emit()


# ==============================================================================
# TextMaps tab
# ==============================================================================
func _build_maps_tab() -> void:
	var page := VBoxContainer.new()
	page.name = "TextMaps"
	_tabs.add_child(page)

	_map_tree.columns = 3
	_map_tree.hide_root = true
	_map_tree.column_titles_visible = true
	_map_tree.set_column_title(0, "Map id")
	_map_tree.set_column_title(1, "File template")
	_map_tree.set_column_title(2, "Status")
	_map_tree.set_column_expand(0, false)
	_map_tree.set_column_custom_minimum_width(0, 160)
	_map_tree.set_column_expand(2, false)
	_map_tree.set_column_custom_minimum_width(2, 110)
	_map_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map_tree.item_selected.connect(_update_switch)
	_map_tree.nothing_selected.connect(_update_switch)
	_map_tree.item_activated.connect(_on_switch)  # double-click = switch
	page.add_child(_map_tree)

	_switch_btn = _button("Select a map to switch to", _on_switch)
	page.add_child(_switch_btn)

	var row := HBoxContainer.new()
	page.add_child(row)
	_map_edit.placeholder_text = "new map id"
	_map_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_map_edit)
	row.add_child(_button("Add", _on_add))
	row.add_child(_button("Import...", _on_import))
	row.add_child(_button("Set default", _on_set_default))
	row.add_child(_button("Relocate...", _on_relocate))
	row.add_child(_button("Remove", _on_remove))

	# Relocate / import can point anywhere; new maps are saved into user:// by default.
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.json"])
	_file_dialog.file_selected.connect(_on_relocate_file)
	add_child(_file_dialog)

	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_USERDATA
	_save_dialog.title = "Where should this map be saved?"
	_save_dialog.filters = PackedStringArray(["*.json"])
	_save_dialog.file_selected.connect(_on_add_file)
	_save_dialog.canceled.connect(func(): _pending_id = "")
	add_child(_save_dialog)

	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.title = "Import an existing map (name.<locale>.json)"
	_import_dialog.filters = PackedStringArray(["*.json"])
	_import_dialog.file_selected.connect(_on_import_file)
	add_child(_import_dialog)


func _refresh_maps() -> void:
	var keep := _selected_map()
	_map_tree.clear()
	var root := _map_tree.create_item()
	for id in registry.map_ids():
		var it := _map_tree.create_item(root)
		var label := id
		if id == registry.default_map:
			label += " *"
		if id == current_map_id:
			label += "  (in use)"
			it.set_custom_color(0, Color(0.5, 0.9, 0.5))
		it.set_text(0, label)
		it.set_metadata(0, id)
		it.set_text(1, registry.template_of(id))
		var file := registry.path_for(id, registry.source_locale)
		it.set_tooltip_text(1, file)
		it.set_text(2, "ok" if FileAccess.file_exists(file) else "no file yet")
		if id == keep:
			it.select(0)
	_update_switch()


func _selected_map() -> String:
	var it := _map_tree.get_selected()
	return "" if it == null else String(it.get_metadata(0))


## The button always says what it will do, and is off when there is nothing to switch to.
func _update_switch() -> void:
	var id := _selected_map()
	if id.is_empty():
		_switch_btn.text = "Select a map to switch to"
		_switch_btn.disabled = true
	elif id == current_map_id:
		_switch_btn.text = "Timeline already uses '%s'" % id
		_switch_btn.disabled = true
	else:
		_switch_btn.text = "Switch timeline to '%s'" % id
		_switch_btn.disabled = false


func _on_switch() -> void:
	var id := _selected_map()
	if id.is_empty() or id == current_map_id:
		return
	_notice.text = "Switching to '%s'..." % id
	map_switch_requested.emit(id)


func _on_add() -> void:
	var id := _map_edit.text.strip_edges()
	if not TextMap.is_valid_id(id) or registry.has_map(id):
		_notice.text = "'%s' is invalid or already exists." % id
		return
	_pending_id = id
	var base := registry.path.get_base_dir()
	var start := registry.resolve_template(TimelineTextSession.MAP_TEMPLATE % id).get_base_dir()
	DirAccess.make_dir_recursive_absolute(start)
	_save_dialog.current_dir = start if DirAccess.dir_exists_absolute(start) else base
	_save_dialog.current_file = "%s.%s.json" % [id, registry.source_locale]
	_save_dialog.popup_centered_ratio(0.6)


func _on_add_file(file: String) -> void:
	if _pending_id.is_empty():
		return
	file = ProjectSettings.localize_path(file)
	var id := _pending_id
	_pending_id = ""
	# Normalise whatever was typed to "<name>.<source_locale>.json".
	var file_name := file.get_file().trim_suffix(".json")
	file_name = file_name.trim_suffix("." + registry.source_locale)
	var normalized := file.get_base_dir().path_join("%s.%s.json" % [file_name, registry.source_locale])
	var tpl := registry.template_from_file(normalized, registry.source_locale)
	if tpl.is_empty() or not registry.register(id, tpl):
		_notice.text = "Could not register '%s' at %s" % [id, file]
		return
	_map_edit.clear()
	_notice.text = ""
	_commit()


func _on_import() -> void:
	_import_dialog.current_dir = registry.path.get_base_dir()
	_import_dialog.popup_centered_ratio(0.6)


## Registers an existing map file. The id is what you typed in the box, otherwise the
## file name without ".<source_locale>.json" ("chapter1.en.json" -> "chapter1").
func _on_import_file(file: String) -> void:
	file = ProjectSettings.localize_path(file)
	var marker := ".%s." % registry.source_locale
	var tpl := registry.template_from_file(file, registry.source_locale)
	if tpl.is_empty():
		_notice.text = "Pick a file named like name%sjson" % marker
		return
	var id := _map_edit.text.strip_edges()
	if id.is_empty():
		id = file.get_file().get_slice(marker, 0)
	if not TextMap.is_valid_id(id):
		_notice.text = "'%s' is not a valid map id. Type one in the box and import again." % id
		return
	if registry.has_map(id):
		_notice.text = "A map '%s' already exists. Type another id in the box and import again." % id
		return
	if TextMapFile.load_file(file) == null:
		_notice.text = "Cannot read %s" % file
		return
	if not registry.register(id, tpl):
		_notice.text = "Could not register '%s'." % id
		return
	_map_edit.clear()
	_notice.text = "Imported '%s'. Select it and press Switch to use it." % id
	_commit()


func _on_set_default() -> void:
	var id := _selected_map()
	if id.is_empty():
		return
	registry.default_map = id
	_commit()


func _on_remove() -> void:
	var id := _selected_map()
	if id.is_empty():
		return
	if id == registry.default_map:
		_notice.text = "Set another default before removing '%s'." % id
		return
	if id == current_map_id:
		_notice.text = "'%s' is in use by the timeline; switch it first." % id
		return
	registry.unregister(id)  # the text files stay on disk
	_commit()


func _on_relocate() -> void:
	_relocating = _selected_map()
	if not _relocating.is_empty():
		_file_dialog.popup_centered_ratio(0.6)


func _on_relocate_file(file: String) -> void:
	file = ProjectSettings.localize_path(file)
	var tpl := registry.template_from_file(file, registry.source_locale)
	if tpl.is_empty():
		_notice.text = "Pick a file named like name.%s.json" % registry.source_locale
		return
	registry.register(_relocating, tpl)
	_commit()


# ==============================================================================
# Timelines tab
# ==============================================================================
func _build_timelines_tab() -> void:
	var page := VBoxContainer.new()
	page.name = "Timelines"
	_tabs.add_child(page)

	_tl_tree.columns = 4
	_tl_tree.hide_root = true
	_tl_tree.column_titles_visible = true
	_tl_tree.set_column_title(0, "Timeline id")
	_tl_tree.set_column_title(1, "File")
	_tl_tree.set_column_title(2, "TextMap")
	_tl_tree.set_column_title(3, "Status")
	_tl_tree.set_column_expand(0, false)
	_tl_tree.set_column_custom_minimum_width(0, 160)
	_tl_tree.set_column_expand(2, false)
	_tl_tree.set_column_custom_minimum_width(2, 110)
	_tl_tree.set_column_expand(3, false)
	_tl_tree.set_column_custom_minimum_width(3, 150)
	_tl_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tl_tree.item_selected.connect(_update_open)
	_tl_tree.nothing_selected.connect(_update_open)
	_tl_tree.item_activated.connect(_on_open_timeline)  # double-click = open
	page.add_child(_tl_tree)

	_open_btn = _button("Select a timeline to open", _on_open_timeline)
	page.add_child(_open_btn)

	var row := HBoxContainer.new()
	page.add_child(row)
	_tl_edit.placeholder_text = "timeline id (for Add / Rename)"
	_tl_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_tl_edit)
	row.add_child(_button("Add file...", func(): _tl_add_dialog.popup_centered_ratio(0.6)))
	row.add_child(_button("Scan folder...", func(): _tl_scan_dialog.popup_centered_ratio(0.6)))
	row.add_child(_button("Rename", _on_tl_rename))
	row.add_child(_button("Relocate...", _on_tl_relocate))
	row.add_child(_button("Remove", _on_tl_remove))

	_tl_add_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_tl_add_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_tl_add_dialog.title = "Add an existing timeline"
	_tl_add_dialog.filters = PackedStringArray(["*.json"])
	_tl_add_dialog.file_selected.connect(_on_tl_add_file)
	add_child(_tl_add_dialog)

	_tl_scan_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_tl_scan_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_tl_scan_dialog.title = "Register every timeline in a folder"
	_tl_scan_dialog.dir_selected.connect(_on_tl_scan_dir)
	add_child(_tl_scan_dialog)

	_tl_relocate_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_tl_relocate_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_tl_relocate_dialog.title = "New location of the timeline file"
	_tl_relocate_dialog.filters = PackedStringArray(["*.json"])
	_tl_relocate_dialog.file_selected.connect(_on_tl_relocate_file)
	add_child(_tl_relocate_dialog)


func _refresh_timelines() -> void:
	var keep := _selected_timeline()
	_tl_tree.clear()
	var root := _tl_tree.create_item()
	for id in registry.timeline_ids():
		var it := _tl_tree.create_item(root)
		var label := id
		if id == current_timeline_id:
			label += "  (open)"
			it.set_custom_color(0, Color(0.5, 0.9, 0.5))
		it.set_text(0, label)
		it.set_metadata(0, id)
		var file := registry.timeline_path(id)
		it.set_text(1, file)
		it.set_tooltip_text(1, file)
		var info := _peek(file)
		it.set_text(2, String(info.get("map_id", "")))
		match String(info.state):
			"missing":
				it.set_text(3, "missing file")
				it.set_custom_color(3, Color(1.0, 0.45, 0.45))
			"invalid":
				it.set_text(3, "not a valid timeline")
				it.set_custom_color(3, Color(1.0, 0.45, 0.45))
			_:
				if registry.has_map(String(info.map_id)):
					it.set_text(3, "ok")
				else:
					it.set_text(3, "map not registered")
					it.set_custom_color(3, Color(1.0, 0.6, 0.3))
		if id == keep:
			it.select(0)
	_update_open()


func _selected_timeline() -> String:
	var it := _tl_tree.get_selected()
	return "" if it == null else String(it.get_metadata(0))


func _update_open() -> void:
	var id := _selected_timeline()
	if id.is_empty():
		_open_btn.text = "Select a timeline to open"
		_open_btn.disabled = true
	elif id == current_timeline_id:
		_open_btn.text = "'%s' is already open" % id
		_open_btn.disabled = true
	else:
		_open_btn.text = "Open timeline '%s'" % id
		_open_btn.disabled = false


## Quick, silent look into a timeline file: {state: ok|missing|invalid, map_id}.
## Doesn't use DialogueDataResource.load_file, which warns on every problem.
func _peek(file: String) -> Dictionary:
	if not FileAccess.file_exists(file):
		return {"state": "missing", "map_id": ""}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(file))
	if not parsed is Dictionary or int(parsed.get("version", 0)) != DialogueDataResource.FORMAT_VERSION:
		return {"state": "invalid", "map_id": ""}
	return {"state": "ok", "map_id": str(parsed.get("map_id", ""))}


func _on_open_timeline() -> void:
	var id := _selected_timeline()
	if id.is_empty() or id == current_timeline_id:
		return
	timeline_open_requested.emit(id)


## Registers an existing timeline file. The id is what you typed in the box, otherwise it
## comes from the file name.
func _on_tl_add_file(file: String) -> void:
	file = ProjectSettings.localize_path(file)
	if _peek(file).state != "ok":
		_notice.text = "%s is not a valid timeline file." % file
		return
	var existing := registry.timeline_id_of_file(file)
	if not existing.is_empty():
		_notice.text = "Already registered as '%s'." % existing
		return
	var id := _tl_edit.text.strip_edges()
	if id.is_empty():
		id = registry.register_timeline_file(file)
	elif not TextMap.is_valid_id(id) or registry.has_timeline(id):
		_notice.text = "'%s' is invalid or already exists." % id
		return
	else:
		registry.register_timeline(id, registry.relative_path(file))
	_tl_edit.clear()
	_notice.text = "Added timeline '%s'." % id
	_commit()


## Registers every valid timeline below `dir` that isn't registered yet.
func _on_tl_scan_dir(dir: String) -> void:
	dir = ProjectSettings.localize_path(dir)
	var added := 0
	var skipped := 0
	for file in _find_json(dir):
		if _peek(file).state != "ok":
			skipped += 1  # TextMap files, the registry itself, other json
			continue
		if registry.timeline_id_of_file(file).is_empty():
			registry.register_timeline_file(file)
			added += 1
	_notice.text = "Scan: %d timeline(s) added, %d other .json file(s) ignored." % [added, skipped]
	if added > 0:
		_commit()


func _find_json(folder: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(folder):
		if f.ends_with(".json"):
			out.append(folder.path_join(f))
	for d in DirAccess.get_directories_at(folder):
		out.append_array(_find_json(folder.path_join(d)))
	return out


func _on_tl_rename() -> void:
	var id := _selected_timeline()
	var new_id := _tl_edit.text.strip_edges()
	if id.is_empty():
		return
	if not registry.rename_timeline(id, new_id):
		_notice.text = "Type a new, valid, unused id in the box first."
		return
	if id == current_timeline_id:
		current_timeline_id = new_id
	_tl_edit.clear()
	_notice.text = "Renamed '%s' to '%s'." % [id, new_id]
	_commit()


func _on_tl_relocate() -> void:
	_tl_relocating = _selected_timeline()
	if not _tl_relocating.is_empty():
		_tl_relocate_dialog.popup_centered_ratio(0.6)


func _on_tl_relocate_file(file: String) -> void:
	file = ProjectSettings.localize_path(file)
	if _peek(file).state != "ok":
		_notice.text = "%s is not a valid timeline file." % file
		return
	registry.register_timeline(_tl_relocating, registry.relative_path(file))
	_commit()


func _on_tl_remove() -> void:
	var id := _selected_timeline()
	if id.is_empty():
		return
	if id == current_timeline_id:
		_notice.text = "'%s' is open; close its tab first." % id
		return
	registry.unregister_timeline(id)  # the file stays on disk
	_commit()
