@tool
class_name QuantoExportDialog
extends AcceptDialog
## File > Export...: copies the project (registry, TextMaps, timelines) to where the game
## loads it from. This dialog only collects the choice; the host saves, publishes and
## reports back through show_result().

## `dir`: folder to export into. `prefix`: what the exported registry stores for the text
## folder ("text" = relative; "res://dialogue/text" = absolute).
signal export_requested(dir: String, prefix: String)

var _prefix := LineEdit.new()
var _status := Label.new()
var _folder_dialog := FileDialog.new()


func _init() -> void:
	title = "Export Project"
	ok_button_text = "Close"
	min_size = Vector2i(420, 170)

	var box := VBoxContainer.new()
	add_child(box)
	var info := Label.new()
	info.text = "Copies the registry, TextMaps and timelines for the game."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(380, 0)
	box.add_child(info)

	var prefix_row := HBoxContainer.new()
	box.add_child(prefix_row)
	var l := Label.new()
	l.text = "Path prefix"
	prefix_row.add_child(l)
	_prefix.placeholder_text = "registry path prefix"
	_prefix.tooltip_text = "Prefix written into the exported registry's templates.\n" \
			+ "\"text\" = relative to the registry (self-contained).\n" \
			+ "\"res://dialogue/text\" = absolute, for when you copy the files there yourself.\n" \
			+ "Files are always written to <folder>/text/ and <folder>/timelines/."
	_prefix.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_prefix.text_submitted.connect(func(t): QuantoDialogueLocator.set_export_prefix(t))
	_prefix.focus_exited.connect(func(): QuantoDialogueLocator.set_export_prefix(_prefix.text))
	prefix_row.add_child(_prefix)

	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	if QuantoDialogueLocator.can_write_project():
		var b := Button.new()
		b.text = "Export to game"
		b.tooltip_text = "Writes into %s" % QuantoDialogueLocator.SHIPPED_PATH.get_base_dir()
		b.pressed.connect(func(): _request(QuantoDialogueLocator.SHIPPED_PATH.get_base_dir()))
		buttons.add_child(b)
	var folder_btn := Button.new()
	folder_btn.text = "Export to folder..."
	folder_btn.pressed.connect(func(): _folder_dialog.popup_centered_ratio(0.6))
	buttons.add_child(folder_btn)

	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(380, 0)
	box.add_child(_status)

	_folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_folder_dialog.title = "Export to folder"
	_folder_dialog.dir_selected.connect(func(d: String): _request(ProjectSettings.localize_path(d)))
	add_child(_folder_dialog)


func open() -> void:
	_prefix.text = QuantoDialogueLocator.export_prefix()
	_status.text = ""
	popup_centered()


## Shows what the export did (or why it didn't).
func show_result(text: String) -> void:
	_status.text = text


func _request(dir: String) -> void:
	var prefix := _prefix.text.strip_edges()
	QuantoDialogueLocator.set_export_prefix(prefix)
	_status.text = "Exporting..."
	export_requested.emit(dir, prefix)
