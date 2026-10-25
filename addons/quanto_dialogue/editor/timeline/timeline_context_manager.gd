@tool
class_name TimelineContextMenu
extends RefCounted
## Right-click menu for blocks and lists.

enum Ctx { COPY, CUT, PASTE, DUPLICATE, DELETE, ADD, SELECT_ALL }

var _menu := PopupMenu.new()
var _actions: TimelineBlockActions
var _prefix: String
var _list: EventList = null  # list that was right-clicked, if any


func _init(host: Control, actions: TimelineBlockActions, action_prefix: String) -> void:
	_actions = actions
	_prefix = action_prefix
	host.add_child(_menu)
	_menu.id_pressed.connect(_on_id)
	EventList.context_handler = _show_for_list
	DialogueBlock.context_handler = _show_for_block


func teardown() -> void:
	if DialogueBlock.context_handler.get_object() == self:
		DialogueBlock.context_handler = Callable()
	if EventList.context_handler.get_object() == self:
		EventList.context_handler = Callable()


func _show_for_list(list: EventList, pos: Vector2) -> void:
	_list = list
	DialogueBlock.clear_selection()
	_menu.clear()
	_item("Paste", "paste_block", Ctx.PASTE)
	_item("Select all", "select_all", Ctx.SELECT_ALL)
	_menu.add_separator()
	_item("Add event", "", Ctx.ADD)
	_popup(pos)


func _show_for_block(block: DialogueBlock, pos: Vector2) -> void:
	_list = null
	# right-clicking an unselected block selects it; a selected one keeps the selection
	if block not in DialogueBlock.selection:
		DialogueBlock.clear_selection()
		DialogueBlock.select(block, true)
	_menu.clear()
	_item("Copy", "copy_block", Ctx.COPY)
	_item("Cut", "cut_block", Ctx.CUT)
	_item("Paste", "paste_block", Ctx.PASTE)
	_item("Duplicate", "duplicate_block", Ctx.DUPLICATE)
	_menu.add_separator()
	_item("Add event", "add_event", Ctx.ADD)
	_menu.add_separator()
	_item("Delete", "delete_block", Ctx.DELETE)
	_popup(pos)


func _item(label: String, action: String, id: int) -> void:
	var hint := _hint(action)
	_menu.add_item(label if hint.is_empty() else label + "\t" + hint, id)


func _hint(action: String) -> String:
	var a := _prefix + action
	if action.is_empty() or not InputMap.has_action(a):
		return ""
	var events := InputMap.action_get_events(a)
	return events[0].as_text() if not events.is_empty() else ""


func _popup(pos: Vector2) -> void:
	var paste_idx := _menu.get_item_index(Ctx.PASTE)
	if paste_idx != -1:
		_menu.set_item_disabled(paste_idx, DialogueBlock.clipboard.is_empty())
	_menu.popup_on_parent(Rect2i(Vector2i(pos), Vector2i.ZERO))


func _on_id(id: int) -> void:
	match id:
		Ctx.COPY: _actions.copy()
		Ctx.CUT: _actions.cut()
		Ctx.PASTE: _actions.paste(_list)
		Ctx.DUPLICATE: _actions.duplicate()
		Ctx.DELETE: _actions.delete_selected()
		Ctx.SELECT_ALL: _actions.select_all(_list)
		Ctx.ADD:
			if _list != null:
				var l := _list
				(func(): l.open_add_menu(-1)).call_deferred()
			else:
				_actions.add_event_in_scope.call_deferred()
