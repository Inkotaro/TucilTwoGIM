@tool
class_name GameEventBlock
extends DialogueBlock
## Fires a key/value event at your game (give item, play sound, set flag...).

var key_input: LineEdit
var value_input: LineEdit


func block_type() -> DialogueEvent.Type:
	return DialogueEvent.Type.EVENT

func block_color() -> Color:
	return Color("#7bc67e")


func _build_body(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)

	key_input = LineEdit.new()
	key_input.placeholder_text = "Key (e.g. give_item)"
	key_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(key_input)
	EventList.make_drop_through(key_input)
	watch(key_input)
	value_input = LineEdit.new()
	value_input.placeholder_text = "Value"
	value_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value_input)
	EventList.make_drop_through(value_input)
	watch(value_input)

func to_event() -> DialogueEvent:
	ensure_built()
	var event := super.to_event()
	event.type = block_type()
	event.key = key_input.text
	event.value = value_input.text
	return event

func from_event(event: DialogueEvent) -> void:
	ensure_built()
	key_input.text = event.key
	value_input.text = event.value
