@tool
class_name LineBlock
extends DialogueBlock

func block_type() -> DialogueEvent.Type:
	return DialogueEvent.Type.LINE

func block_color() -> Color:
	return Color("#5aa9e6")

var speaker_input: LineEdit
var text_input: TextEdit
var text_binding: TextBinding

func _build_body(parent: VBoxContainer) -> void:
	speaker_input = LineEdit.new()
	speaker_input.placeholder_text = "Speaker"
	parent.add_child(speaker_input)
	EventList.make_drop_through(speaker_input)
	watch(speaker_input)
	text_input = TextEdit.new()
	text_input.placeholder_text = "What do they say?"
	text_input.custom_minimum_size = Vector2(0, 70)
	text_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	parent.add_child(text_input)
	EventList.make_drop_through(text_input)
	text_binding = TextBinding.new(text_input)  # before watch(): the id exists when `changed` fires
	text_binding.relinked.connect(func(): changed.emit())
	parent.add_child(text_binding.chip)
	watch(text_input)

func to_event() -> DialogueEvent:
	ensure_built()
	var event := super.to_event()
	event.type = block_type()
	event.speaker = speaker_input.text
	event.text_id = text_binding.text_id
	return event

func from_event(event: DialogueEvent) -> void:
	ensure_built()
	speaker_input.text = event.speaker
	text_binding.load_ref(event.text_id)
