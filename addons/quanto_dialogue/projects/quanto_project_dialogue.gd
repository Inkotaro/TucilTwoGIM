@tool
class_name QuantoProjectDialog
extends ConfirmationDialog
## The project list: open a recent project, search it, and manage it. Also the start-up
## prompt. The host does the actual switching.
##
##   Open           -> project_chosen(folder)   (also double-click)
##   New...         -> new_requested            (dialog closes; the host asks for a folder)
##   Browse...      -> browse_requested         (same, to open a project not in the list)
##   Remove         -> forgets the project in the list (nothing is deleted from disk)
##   Show folder    -> opens it in the file manager
##   Remove missing -> forgets every project whose folder is gone
##   Close          -> just closes

signal project_chosen(folder: String)
signal new_requested
signal browse_requested

var _current_label := Label.new()
var _search := LineEdit.new()
var _tree := Tree.new()
var _remove_btn: Button
var _show_btn: Button
var _startup := CheckBox.new()
var _current := ""


func _init() -> void:
	title = "Projects"
	ok_button_text = "Open"
	cancel_button_text = "Close"
	min_size = Vector2i(460, 300)

	var box := VBoxContainer.new()
	add_child(box)
	_current_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_current_label.custom_minimum_size = Vector2(420, 0)
	box.add_child(_current_label)

	_search.placeholder_text = "Search projects..."
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _fill())
	box.add_child(_search)

	_tree.columns = 2
	_tree.hide_root = true
	_tree.column_titles_visible = true
	_tree.set_column_title(0, "Project")
	_tree.set_column_title(1, "Location")
	_tree.set_column_expand(0, false)
	_tree.set_column_custom_minimum_width(0, 150)
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(0, 130)
	_tree.item_selected.connect(_update_buttons)
	_tree.nothing_selected.connect(_update_buttons)
	_tree.item_activated.connect(_choose)  # double-click
	box.add_child(_tree)

	var row := HBoxContainer.new()
	box.add_child(row)
	row.add_child(_button("New...", func(): _forward(new_requested)))
	row.add_child(_button("Browse...", func(): _forward(browse_requested)))
	_remove_btn = _button("Remove", _on_remove)
	_remove_btn.tooltip_text = "Remove from this list. Nothing is deleted from disk."
	row.add_child(_remove_btn)
	_show_btn = _button("Show folder", _on_show_folder)
	row.add_child(_show_btn)
	var missing_btn := _button("Remove missing", _on_remove_missing)
	missing_btn.tooltip_text = "Remove every project whose folder no longer exists."
	row.add_child(missing_btn)

	_startup.text = "Show on start"
	_startup.button_pressed = QuantoDialogueLocator.show_startup_dialog()
	_startup.toggled.connect(func(on: bool): QuantoDialogueLocator.set_show_startup_dialog(on))
	box.add_child(_startup)

	confirmed.connect(_choose)


## `current_folder`: the project that is open right now. `usable` = false when there is none
## (nothing chosen yet, or the remembered folder could not be opened).
func ask(current_folder: String, usable := true) -> void:
	_current = current_folder if usable else ""
	if usable:
		_current_label.text = "Project: %s" % current_folder.get_file()
		cancel_button_text = "Continue"
	else:
		_current_label.text = "No project open. Create or open one."
		cancel_button_text = "Close"
	_current_label.tooltip_text = current_folder
	_startup.set_pressed_no_signal(QuantoDialogueLocator.show_startup_dialog())
	_search.clear()
	_fill()
	popup_centered(Vector2i(480, 330))


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _fill() -> void:
	var keep := _selected()
	_tree.clear()
	var root := _tree.create_item()
	var q := _search.text.strip_edges().to_lower()
	var select_item: TreeItem = null
	for folder in QuantoDialogueLocator.recent():
		var short := folder.get_file() if not folder.get_file().is_empty() else folder
		if not q.is_empty() and not (short.to_lower().contains(q) or folder.to_lower().contains(q)):
			continue
		var exists := QuantoDialogueProject.is_project(folder)
		var it := _tree.create_item(root)
		var label := short
		if not _current.is_empty() and folder == _current:
			label += "  (current)"
			it.set_custom_color(0, Color(0.5, 0.9, 0.5))
		if not exists:
			label += "  (missing)"
			it.set_custom_color(0, Color(1.0, 0.45, 0.45))
			it.set_custom_color(1, Color(1.0, 0.45, 0.45))
		it.set_text(0, label)
		it.set_text(1, folder)
		it.set_tooltip_text(0, folder)
		it.set_tooltip_text(1, folder)
		it.set_metadata(0, folder)
		if folder == keep or (select_item == null and keep.is_empty() and folder == _current):
			select_item = it
	if select_item != null:
		select_item.select(0)
	_update_buttons()


func _selected() -> String:
	var it := _tree.get_selected()
	return "" if it == null else String(it.get_metadata(0))


func _update_buttons() -> void:
	var folder := _selected()
	var exists := not folder.is_empty() and QuantoDialogueProject.is_project(folder)
	get_ok_button().disabled = not exists or folder == _current
	_remove_btn.disabled = folder.is_empty()
	_show_btn.disabled = not exists


func _choose() -> void:
	var folder := _selected()
	if folder.is_empty() or folder == _current or not QuantoDialogueProject.is_project(folder):
		return
	hide()
	project_chosen.emit(folder)


func _forward(sig: Signal) -> void:
	hide()  # the host opens a folder picker; this dialog is exclusive and would block it
	sig.emit()


func _on_remove() -> void:
	var folder := _selected()
	if folder.is_empty():
		return
	QuantoDialogueLocator.remove_recent(folder)
	_fill()


func _on_show_folder() -> void:
	var folder := _selected()
	if not folder.is_empty():
		OS.shell_show_in_file_manager(ProjectSettings.globalize_path(folder))


func _on_remove_missing() -> void:
	for folder in QuantoDialogueLocator.recent():
		if not QuantoDialogueProject.is_project(folder):
			QuantoDialogueLocator.remove_recent(folder)
	_fill()
