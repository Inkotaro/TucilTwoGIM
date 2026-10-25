@tool
class_name TimelineNavigator
extends RefCounted
## Keyboard navigation over blocks and their input fields.

var _list: EventList


func _init(root_list: EventList) -> void:
	_list = root_list


func move_selection(step: int, extend: bool) -> void:
	var all := _list.flat_blocks()
	if all.is_empty():
		return
	var from := DialogueBlock.cursor
	var i := all.find(from) if from != null else -1
	var target: DialogueBlock
	if i == -1:
		# nothing selected yet: Down starts at the top, Up at the bottom
		target = all[0] if step > 0 else all[all.size() - 1]
	else:
		target = all[clampi(i + step, 0, all.size() - 1)]

	if extend and from != null:
		if target in DialogueBlock.selection and target != from:
			DialogueBlock.select(from, true)  # toggles the old end off
			DialogueBlock.cursor = target
		else:
			DialogueBlock.select(target, true)
	else:
		DialogueBlock.clear_selection()
		DialogueBlock.select(target, true)
	TimelineUtil.scroll_to(target)


## Right = into the first nested block, Left = out to the owning block.
func nav_nested(into: bool) -> void:
	var from := DialogueBlock.cursor
	if from == null:
		move_selection(1, false)
		return
	var target: DialogueBlock = null
	if into:
		for l in EventList._nested_lists(from):
			var inner := l.flat_blocks()
			if not inner.is_empty():
				target = inner[0]
				break
	else:
		target = TimelineUtil.owner_block(EventList._find_list(from))
	if target != null:
		DialogueBlock.clear_selection()
		DialogueBlock.select(target, true)
		TimelineUtil.scroll_to(target)


func focus_selected() -> void:
	var sel := TimelineUtil.selected_blocks()
	if sel.is_empty():
		return
	var inputs: Array[Control] = []
	EventList.collect_inputs(sel[0], inputs)
	if inputs.is_empty():
		return  # e.g. an End block: keep the selection
	inputs[0].grab_focus()
	TimelineUtil.scroll_to(inputs[0])


## Enter in a field jumps to the next field, or to the list's "Add event" button.
func enter_to_next(focus: Control) -> void:
	var list := EventList._find_list(focus)
	if list == null:
		return
	var inputs: Array[Control] = []
	EventList.collect_inputs(_list, inputs)
	var i := inputs.find(focus)
	var next: Control = inputs[i + 1] if i >= 0 and i + 1 < inputs.size() else null
	var dest: Control = next if next != null and list.is_ancestor_of(next) else list.add_menu
	dest.grab_focus()
	TimelineUtil.scroll_to(dest)
