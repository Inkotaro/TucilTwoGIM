@tool
class_name TimelineMigrateDialog
extends ConfirmationDialog
## Asks how the timeline's strings should follow it to another map.

signal migrate_chosen(target_id: String, mode: int)  ## a TimelineTextSession.MigrateMode

var _target := ""
var _info := Label.new()
var _options: Array[CheckBox] = []
var _descs: Array[Label] = []


func _init() -> void:
	title = "Switch map"
	ok_button_text = "Switch"
	var box := VBoxContainer.new()
	add_child(box)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(460, 0)
	box.add_child(_info)
	var group := ButtonGroup.new()
	_add_option(box, group, TimelineTextSession.MigrateMode.COPY, "Copy strings")
	_add_option(box, group, TimelineTextSession.MigrateMode.DISCARD, "Discard keys")
	_add_option(box, group, TimelineTextSession.MigrateMode.KEEP, "Keep ids as they are")
	confirmed.connect(_on_confirmed)


func _add_option(box: Control, group: ButtonGroup, mode: int, text: String) -> void:
	var cb := CheckBox.new()
	cb.text = text
	cb.button_group = group
	cb.set_meta("mode", mode)
	box.add_child(cb)
	_options.append(cb)
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(460, 0)
	l.modulate = Color(1, 1, 1, 0.6)
	box.add_child(l)
	_descs.append(l)


func ask(from_id: String, to_id: String, preview: Dictionary) -> void:
	_target = to_id
	var err := String(preview.error)
	_info.text = err if not err.is_empty() else \
			"'%s' -> '%s'\n%d string(s) of this timeline, %d draft(s). In the target: %d identical, %d with a different text.%s" % [
			from_id, to_id, preview.own, preview.drafts, preview.same, preview.collisions,
			"\n%d id(s) are already missing in the old map." % preview.unknown if preview.unknown > 0 else ""]
	_descs[0].text = "Copy the strings (all %d locale(s)) into '%s'. Same id and text is reused; a different text gets a new id, nothing is overwritten. '%s' is left untouched." % [
			preview.locales, to_id, from_id]
	_descs[1].text = "Every string reference becomes an empty draft. Nothing is copied."
	_descs[2].text = "Only switch. Ids that '%s' doesn't have will show as missing." % to_id
	for cb in _options:
		cb.button_pressed = int(cb.get_meta("mode")) == TimelineTextSession.MigrateMode.COPY
	get_ok_button().disabled = not err.is_empty()
	popup_centered(Vector2i(500, 380))


func _on_confirmed() -> void:
	for cb in _options:
		if cb.button_pressed:
			migrate_chosen.emit(_target, int(cb.get_meta("mode")))
			return
