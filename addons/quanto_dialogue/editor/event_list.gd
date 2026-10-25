@tool
class_name EventList
extends VBoxContainer
## An ordered list of blocks. Handles drag & drop reordering and (de)serialising
## itself. Choice options each own one of these, so nesting is recursive.

signal changed

var blocks: VBoxContainer
var add_menu: MenuButton # NEW

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	blocks = VBoxContainer.new()
	blocks.add_theme_constant_override("separation", 6)
	add_child(blocks)

	var menu := MenuButton.new()
	add_menu = menu # NEW
	menu.focus_mode = Control.FOCUS_ALL # NEW: MenuButton isn't focusable by default
	menu.text = "+ Add event"
	menu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var types : Array[DialogueEvent.Type] = BlockRegistry.types()
	var popup := menu.get_popup()
	for t in types:
		popup.add_item(BlockRegistry.label(t))
	# NEW: focus the first field of the block that was just added
	popup.index_pressed.connect(func(i: int):
		var b := add_block(DialogueEvent.new(types[i]))
		if b and _insert_index >= 0:
			blocks.move_child(b, mini(_insert_index, blocks.get_child_count() - 1))
		_insert_index = -1
		if b:
			_focus_first_input(b))
	popup.popup_hide.connect(func(): _reset_insert_index.call_deferred())
	add_child(menu)
	make_drop_through(menu)

var _insert_index := -1  # -1 = append at the end
func _reset_insert_index() -> void:
	_insert_index = -1

func open_add_menu(at_index := -1) -> void:
	_insert_index = at_index
	if at_index >= 0:
		# opened for "add below": show the menu at the mouse
		var p := add_menu.get_popup()
		p.popup(Rect2i(Vector2i(DisplayServer.mouse_get_position()), Vector2i.ZERO))
	else:
		add_menu.show_popup()

func _focus_first_input(block: Control) -> void:
	# wait for the popup to close and the new block to be laid out
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(block) or not block.is_inside_tree():
		return
	var inputs: Array[Control] = []
	collect_inputs(block, inputs)
	if not inputs.is_empty():
		inputs[0].grab_focus()
	scroll_into_view(block)


static func scroll_into_view(control: Control) -> void:
	var n := control.get_parent()
	while n and not n is ScrollContainer:
		n = n.get_parent()
	if n:
		(n as ScrollContainer).ensure_control_visible(control)


# NEW: editable text fields under `node`, in visual order
static func collect_inputs(node: Node, out: Array[Control]) -> void:
	for c in node.get_children():
		if c.is_queued_for_deletion():
			continue
		if (c is LineEdit or c is TextEdit) and c.editable and c.is_visible_in_tree():
			out.append(c)
		collect_inputs(c, out)

# --- data ---------------------------------------------------------------------
func to_array() -> Array[DialogueEvent]:
	var out: Array[DialogueEvent] = []
	for c in blocks.get_children():
		if c is DialogueBlock and not c.is_queued_for_deletion():
			out.append(c.to_event())
	return out


func from_array(events: Array[DialogueEvent]) -> void:
	clear_blocks()
	for d in events:
		add_block(d)


func clear_blocks() -> void:
	for c in blocks.get_children():
		blocks.remove_child(c)
		c.queue_free()
	changed.emit()


func add_block(d: DialogueEvent) -> DialogueBlock:
	var b := BlockRegistry.create(d.type)
	if b == null:
		return null
	blocks.add_child(b)
	b.from_event(d)
	b.changed.connect(_notify_changed)
	changed.emit()
	return b


# --- drag & drop --------------------------------------------------------------
func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	# Reject dropping a block into its own descendants (e.g. a choice into its own option)
	return data is DialogueBlock and not data.is_ancestor_of(self)


func _drop_data(pos: Vector2, data: Variant) -> void:
	var block := data as DialogueBlock
	var index := _index_at(pos.y - blocks.position.y, block)
	var old_parent := block.get_parent()
	var old_list := _find_list(old_parent) if old_parent else null
	if old_parent:
		old_parent.remove_child(block)
	blocks.add_child(block)
	blocks.move_child(block, index)
	
	if old_list != self:
		if old_list and block.changed.is_connected(old_list._notify_changed):
			block.changed.disconnect(old_list._notify_changed)
		if not block.changed.is_connected(_notify_changed):
			block.changed.connect(_notify_changed)

	changed.emit()
	if old_list and old_list != self:
		old_list.changed.emit()


func _index_at(y: float, ignore: Node) -> int:
	var i := 0
	for c in blocks.get_children():
		if c == ignore:
			continue
		if y < c.position.y + c.size.y * 0.5:
			return i
		i += 1
	return i


## Godot stops looking for a drop target at controls that capture the mouse
## (LineEdit, TextEdit, Button...). Call this on such widgets so a block can be
## dropped while hovering over them; the drop goes to the nearest EventList.
static func make_drop_through(widget: Control) -> void:
	var can_drop := func(at: Vector2, data: Variant) -> bool:
		var l := _find_list(widget)
		return l != null and l._can_drop_data(l._to_local(widget, at), data)
	var drop := func(at: Vector2, data: Variant) -> void:
		var l := _find_list(widget)
		if l:
			l._drop_data(l._to_local(widget, at), data)
	widget.set_drag_forwarding(Callable(), can_drop, drop)


static func _find_list(from: Node) -> EventList:
	var n := from.get_parent()
	while n and not n is EventList:
		n = n.get_parent()
	return n as EventList

func _to_local(from: Control, at: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * (from.get_global_transform() * at)

func _notify_changed() -> void:
	changed.emit()
	
## Returns every block (including ones nested in choice options) whose own
## text contains `q`, in visual order. `q` must be lowercase.
func find_matches(q: String) -> Array[DialogueBlock]:
	var out: Array[DialogueBlock] = []
	if q.is_empty():
		return out
	for b in blocks.get_children():
		if not b is DialogueBlock or b.is_queued_for_deletion():
			continue
		if _own_text(b).to_lower().contains(q):
			out.append(b)
		for l in _nested_lists(b):
			out.append_array(l.find_matches(q))
	return out

func set_highlights(matches: Array[DialogueBlock], current: DialogueBlock = null) -> void:
	for b in blocks.get_children():
		if not b is DialogueBlock:
			continue
		var block := b as DialogueBlock
		if block == current:
			block.set_highlight(DialogueBlock.Highlight.CURRENT)
		elif block in matches:
			block.set_highlight(DialogueBlock.Highlight.MATCH)
		else:
			block.set_highlight(DialogueBlock.Highlight.NONE)
		for l in _nested_lists(block):
			l.set_highlights(matches, current)


# Text of a block, excluding anything inside nested EventLists.
static func _own_text(node: Node) -> String:
	var out := ""
	for c in node.get_children():
		if c is EventList:
			continue
		if c is LineEdit or c is TextEdit:
			out += c.text + "\n"
		elif c is OptionButton:
			out += c.text + "\n"
		out += _own_text(c)
	return out

# The nearest EventLists below `node` (does not go inside them).
static func _nested_lists(node: Node) -> Array[EventList]:
	var out: Array[EventList] = []
	for c in node.get_children():
		if c is EventList:
			out.append(c)
		else:
			out.append_array(_nested_lists(c))
	return out

## All blocks under this list in visual (top-to-bottom) order, nested ones included.
func flat_blocks() -> Array[DialogueBlock]:
	var out: Array[DialogueBlock] = []
	for b in blocks.get_children():
		if not b is DialogueBlock or b.is_queued_for_deletion():
			continue
		out.append(b)
		for l in _nested_lists(b):
			out.append_array(l.flat_blocks())
	return out
	
static var context_handler: Callable = Callable()

func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().gui_release_focus()
		if context_handler.is_valid():
			context_handler.call(self, get_global_mouse_position())
		accept_event()
		
