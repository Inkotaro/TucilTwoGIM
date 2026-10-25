@tool
class_name CallBlock
extends DialogueBlock
## Calls a specific label inside the events list, without clearing the timeline stack

var key_input: LineEdit
var value_input: LineEdit

func block_type() -> DialogueEvent.Type:
	return DialogueEvent.Type.CALL

func block_color() -> Color:
	return Color("ff2076ff")

func _build_body(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	key_input = LineEdit.new()
	key_input.placeholder_text = "Label Key (e.g. death_event)"
	key_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key_input)
	watch(key_input)
	EventList.make_drop_through(key_input)

func to_event() -> DialogueEvent:
	ensure_built()
	var event := super.to_event()
	event.type = block_type()
	event.key = key_input.text
	return event

func from_event(event: DialogueEvent) -> void:
	ensure_built()
	key_input.text = event.key
