class_name TimelineUtil
extends RefCounted
## Small stateless helpers shared by the timeline editor modules.


static func scroll_to(control: Control) -> void:
	if control == null or not control.is_inside_tree():
		return
	var n := control.get_parent()
	while n and not n is ScrollContainer:
		n = n.get_parent()
	if n == null:
		return
	await control.get_tree().process_frame
	if is_instance_valid(control) and control.is_inside_tree():
		(n as ScrollContainer).ensure_control_visible(control)


## Valid selected blocks, top to bottom. Children of a selected block are dropped
## because they travel with their parent.
static func selected_blocks() -> Array[DialogueBlock]:
	var valid: Array[DialogueBlock] = []
	for b in DialogueBlock.selection:
		if is_instance_valid(b) and b.is_inside_tree() and not b.is_queued_for_deletion():
			valid.append(b)
	var out: Array[DialogueBlock] = []
	for b in valid:
		if not valid.any(func(o): return o != b and o.is_ancestor_of(b)):
			out.append(b)
	out.sort_custom(func(a, b): return a.get_global_rect().position.y < b.get_global_rect().position.y)
	return out


## The block that contains `list` as a nested list, or null for the root list.
static func owner_block(list: EventList) -> DialogueBlock:
	if list == null:
		return null
	var n := list.get_parent()
	while n and not n is DialogueBlock:
		n = n.get_parent()
	return n as DialogueBlock


static func live_blocks(list: EventList) -> Array[DialogueBlock]:
	var out: Array[DialogueBlock] = []
	for c in list.blocks.get_children():
		if c is DialogueBlock and not c.is_queued_for_deletion():
			out.append(c)
	return out
