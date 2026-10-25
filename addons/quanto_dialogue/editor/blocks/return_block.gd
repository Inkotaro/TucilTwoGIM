@tool
class_name ReturnBlock
extends DialogueBlock
## Return, and pop a stack in the timeline.

func block_type() -> DialogueEvent.Type:
	return DialogueEvent.Type.RETURN

func block_color() -> Color:
	return Color("ff7dccff")


func _build_body(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)


func to_event() -> DialogueEvent:
	ensure_built()
	var event := super.to_event()
	return event

func from_event(event: DialogueEvent) -> void:
	ensure_built()
