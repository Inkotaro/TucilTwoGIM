@tool
class_name TimelineMapPicker
extends ConfirmationDialog
## Asks which TextMap a new timeline should use, or lets you create one.
## Creating one asks where its file should be saved, registers it in the
## registry, and then emits `map_picked`.

## For `is_new == true` the map is already registered (and the registry saved)
## by the time this is emitted, so the receiver must not register it again.
signal map_picked(map_id: String, is_new: bool)

var _registry: QuantoDialogueRegistry
var _list := ItemList.new()
var _new_edit := LineEdit.new()
var _hint := Label.new()
var _save_dialog := FileDialog.new()
var _pending_id := ""


func _init() -> void:
	title = "Choose a TextMap"
	ok_button_text = "Use"
	var box := VBoxContainer.new()
	add_child(box)
	var l1 := Label.new()
	l1.text = "Existing TextMaps:"
	box.add_child(l1)
	_list.custom_minimum_size = Vector2(0, 140)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_list)
	var l2 := Label.new()
	l2.text = "...or create a new one (id):"
	box.add_child(l2)
	_new_edit.placeholder_text = "e.g. chapter1"
	box.add_child(_new_edit)
	box.add_child(_hint)

	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = FileDialog.ACCESS_RESOURCES if Engine.is_editor_hint() \
			else FileDialog.ACCESS_FILESYSTEM
	_save_dialog.title = "Where should this map be saved?"
	_save_dialog.filters = PackedStringArray(["*.json"])
	_save_dialog.file_selected.connect(_on_save_file)
	_save_dialog.canceled.connect(_on_save_canceled)
	add_child(_save_dialog)

	_list.item_selected.connect(func(_i): _new_edit.clear(); _update())
	_list.item_activated.connect(func(_i): _on_confirmed(); hide())
	_new_edit.text_changed.connect(func(_t): _list.deselect_all(); _update())
	confirmed.connect(_on_confirmed)


func ask(registry: QuantoDialogueRegistry) -> void:
	_registry = registry
	_pending_id = ""
	_list.clear()
	_new_edit.clear()
	for id in registry.map_ids():
		var i := _list.add_item(id + ("  (default)" if id == registry.default_map else ""))
		_list.set_item_metadata(i, id)
		if id == registry.default_map:
			_list.select(i)
	_update()
	popup_centered(Vector2i(380, 340))


func _update() -> void:
	var typed := _new_edit.text.strip_edges()
	var ok := false
	_hint.text = ""
	if not typed.is_empty():
		if not TextMap.is_valid_id(typed):
			_hint.text = "Only A-Z a-z 0-9 _ . - allowed"
		elif _registry.has_map(typed):
			_hint.text = "Already exists, pick it from the list"
		else:
			ok = true
	else:
		ok = not _list.get_selected_items().is_empty()
	get_ok_button().disabled = not ok


func _on_confirmed() -> void:
	var typed := _new_edit.text.strip_edges()
	if not typed.is_empty():
		_ask_save_location(typed)
		return
	var sel := _list.get_selected_items()
	if not sel.is_empty():
		map_picked.emit(_list.get_item_metadata(sel[0]), false)


func _ask_save_location(id: String) -> void:
	_pending_id = id
	# Start in the folder of the default template, falling back to the registry folder.
	var base := _registry.path.get_base_dir()
	var start := _registry.resolve_template(TimelineTextSession.MAP_TEMPLATE % id).get_base_dir()
	_save_dialog.current_dir = start if DirAccess.dir_exists_absolute(start) else base
	_save_dialog.current_file = "%s.%s.json" % [id, _registry.source_locale]
	_save_dialog.popup_centered_ratio(0.6)


func _on_save_file(file: String) -> void:
	if _pending_id.is_empty():
		return
	var id := _pending_id
	_pending_id = ""
	# Normalise whatever was typed to "<name>.<source_locale>.json".
	var file_name := file.get_file().trim_suffix(".json")
	file_name = file_name.trim_suffix("." + _registry.source_locale)
	var normalized := file.get_base_dir().path_join("%s.%s.json" % [file_name, _registry.source_locale])
	var tpl := _registry.template_from_file(normalized, _registry.source_locale)
	if tpl.is_empty() or not _registry.register(id, tpl):
		push_warning("TimelineMapPicker: could not register '%s' at %s" % [id, file])
		popup_centered(Vector2i(380, 340))
		return
	var err := _registry.save_file()
	if err != OK:
		push_error("TimelineMapPicker: cannot save registry (error %d)" % err)
	map_picked.emit(id, true)


func _on_save_canceled() -> void:
	# Back to the picker so the user can change the id or pick an existing map.
	_pending_id = ""
	popup_centered(Vector2i(380, 340))
