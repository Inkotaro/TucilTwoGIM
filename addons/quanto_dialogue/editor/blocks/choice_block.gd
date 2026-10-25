@tool
class_name ChoiceBlock
extends DialogueBlock

var options_box: VBoxContainer

func block_type() -> DialogueEvent.Type:
	return DialogueEvent.Type.CHOICE

func block_color() -> Color:
	return Color("#e6a15a")

func _build_body(parent: VBoxContainer) -> void:
	options_box = VBoxContainer.new()
	options_box.add_theme_constant_override("separation", 8)
	parent.add_child(options_box)

	var add := Button.new()
	add.text = "+ Add option"
	add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add.pressed.connect(func(): add_option(DialogueChoice.new()))
	parent.add_child(add)


func add_option(d: DialogueChoice) -> void:
	var row := ChoiceOptionRow.new()
	row.from_choice(d)
	row.changed.connect(func(): changed.emit())
	options_box.add_child(row)
	changed.emit()



func to_event() -> DialogueEvent:
	ensure_built()
	var opts : Array[DialogueChoice] = []
	for row in options_box.get_children():
		if row is ChoiceOptionRow and not row.is_queued_for_deletion():
			opts.append(row.to_choice())
	var event := super.to_event()
	event.type = block_type()
	event.options = opts
	return event

func from_event(event: DialogueEvent) -> void:
	ensure_built()
	for row in options_box.get_children():
		options_box.remove_child(row)
		row.queue_free()
		
	if not event.options:
		add_option(DialogueChoice.new())
		add_option(DialogueChoice.new())
		return
	for o in event.options:
		add_option(o)
