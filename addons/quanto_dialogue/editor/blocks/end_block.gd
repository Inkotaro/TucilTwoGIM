@tool
class_name EndBlock
extends DialogueBlock
## Ends the entire timeline stack

func block_type() -> DialogueEvent.Type:
	return DialogueEvent.Type.END

func block_color() -> Color:
	return Color("ff7dccff")


func _build_body(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)



func to_event() -> DialogueEvent:
	ensure_built()
	var event := super.to_event()
	event.type = block_type()
	return event

func from_event(event: DialogueEvent) -> void:
	ensure_built()
