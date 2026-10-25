@tool
class_name LabelBlock
extends DialogueBlock

var key_input: LineEdit
var list: EventList

func block_type() -> DialogueEvent.Type:
	return DialogueEvent.Type.LABEL

func block_color() -> Color:
	return Color("ff7dccff")


func _build_body(parent: VBoxContainer) -> void:
	key_input = LineEdit.new()
	key_input.placeholder_text = "Key (e.g. death_event)"
	key_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(key_input)
	EventList.make_drop_through(key_input)
	watch(key_input)
	
	var indent := MarginContainer.new()
	indent.add_theme_constant_override("margin_left", 24)
	parent.add_child(indent)
	
	list = EventList.new()
	list.changed.connect(func(): changed.emit())
	indent.add_child(list)
	
func to_event() -> DialogueEvent:
	ensure_built()
	var event := super.to_event()
	event.type = block_type()
	event.key = key_input.text
	event.events = list.to_array()
	return event

func from_event(event: DialogueEvent) -> void:
	ensure_built()
	key_input.text = event.key
	list.from_array(event.events)
