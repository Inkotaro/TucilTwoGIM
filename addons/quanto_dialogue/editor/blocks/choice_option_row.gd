@tool
class_name ChoiceOptionRow
extends VBoxContainer
## One option of a ChoiceBlock: its text + the events that run if it's picked.

signal changed

var text_edit: LineEdit
var text_binding: TextBinding
var list: EventList


func _init() -> void:
	var header := HBoxContainer.new()
	add_child(header)

	var arrow := Label.new()
	arrow.text = "▸"
	header.add_child(arrow)

	text_edit = LineEdit.new()
	text_edit.placeholder_text = "Choice text"
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(text_edit)
	EventList.make_drop_through(text_edit)
	
	text_binding = TextBinding.new(text_edit)
	text_binding.relinked.connect(func(): changed.emit())
	text_edit.text_changed.connect(func(_t): changed.emit())
	header.add_child(text_binding.chip)   
	
	var delete := Button.new()
	delete.text = "✕"
	delete.flat = true
	delete.tooltip_text = "Remove option"
	delete.pressed.connect(_delete)
	header.add_child(delete)

	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", 24)
	add_child(indent)

	list = EventList.new()
	list.changed.connect(func(): changed.emit())
	indent.add_child(list)

func to_choice() -> DialogueChoice:
	var choice := DialogueChoice.new()
	choice.text_id = text_binding.text_id
	choice.events = list.to_array()
	return choice

func from_choice(choice: DialogueChoice) -> void:
	text_binding.load_ref(choice.text_id)
	list.from_array(choice.events)


func _delete() -> void:
	var p := get_parent()
	if p:
		p.remove_child(self)
	changed.emit()
	queue_free()
