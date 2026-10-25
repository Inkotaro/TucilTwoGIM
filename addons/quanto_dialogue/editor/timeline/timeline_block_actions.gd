@tool
class_name TimelineBlockActions
extends RefCounted
## Block-level editing: copy / cut / paste / duplicate / delete / select-all / add.
## Emits `edited` whenever the event list was modified so the editor can snapshot.

signal edited

var _list: EventList


func _init(root_list: EventList) -> void:
	_list = root_list


## The list the user is currently working in: selection first, then focus, then root.
func current_list() -> EventList:
	var sel := TimelineUtil.selected_blocks()
	if not sel.is_empty():
		var l := EventList._find_list(sel.back())
		if l != null:
			return l
	var focus := _list.get_viewport().gui_get_focus_owner()
	if focus != null and _list.is_ancestor_of(focus):
		var l := EventList._find_list(focus)
		if l != null:
			return l
	return _list


func add_event_in_scope() -> void:
	var sel := TimelineUtil.selected_blocks()
	if not sel.is_empty():
		var last: DialogueBlock = sel.back()
		var l := EventList._find_list(last)
		if l != null:
			TimelineUtil.scroll_to(last)
			l.open_add_menu(last.get_index() + 1)
			return
	var list := current_list()
	TimelineUtil.scroll_to(list.add_menu)
	list.open_add_menu(-1)


func select_all(list: EventList) -> void:
	DialogueBlock.clear_selection()
	var last: DialogueBlock = null
	for b in TimelineUtil.live_blocks(list):
		DialogueBlock.select(b, true)
		last = b
	if last:
		TimelineUtil.scroll_to(last)


## Select everything in the current list; pressing again widens to the parent list.
func select_all_in_scope() -> void:
	var list := current_list()
	if _all_selected_in(list):
		var outer := EventList._find_list(TimelineUtil.owner_block(list))
		if outer != null:
			list = outer
	select_all(list)


func copy() -> void:
	var sel := TimelineUtil.selected_blocks()
	if sel.is_empty():
		return
	DialogueBlock.clipboard.clear()
	DialogueBlock.clipboard_texts.clear()
	for b in sel:
		var e: DialogueEvent = b.to_event()
		DialogueBlock.clipboard.append(e)
		var ids := {}
		TextBinding.collect_ids([e], ids)
		for id: String in ids:
			DialogueBlock.clipboard_texts[id] = DialogueBlock.read_text(id)


func cut() -> void:
	copy()
	delete_selected()


func delete_selected() -> void:
	var sel := TimelineUtil.selected_blocks()
	if sel.is_empty():
		return
	for b in sel:
		b._delete()
	DialogueBlock.selection.clear()
	edited.emit()  # delete doesn't emit the list's changed signal, so undo would miss it


func duplicate() -> void:
	var sel := TimelineUtil.selected_blocks()
	if sel.is_empty():
		return
	DialogueBlock.clear_selection()
	var first: DialogueBlock = null
	for b in sel:
		var list := EventList._find_list(b)
		if list == null:
			continue
		var e: DialogueEvent = b.to_event()
		TextBinding.refresh_ids(e, {})
		var nb := list.add_block(e)
		if nb == null:
			continue
		list.blocks.move_child(nb, b.get_index() + 1)
		DialogueBlock.select(nb, true)
		if first == null:
			first = nb
	if first:
		TimelineUtil.scroll_to(first)
	edited.emit()


## `target` given: append to that list. Otherwise paste after the selection, or at root end.
func paste(target: EventList = null) -> void:
	if DialogueBlock.clipboard.is_empty():
		return
	var list := _list
	var index := -1
	if target != null:
		list = target
	else:
		var sel := TimelineUtil.selected_blocks()
		if not sel.is_empty():
			var last: DialogueBlock = sel.back()
			var found := EventList._find_list(last)
			if found:
				list = found
				index = last.get_index() + 1
	DialogueBlock.clear_selection()
	var first: DialogueBlock = null
	for e in DialogueBlock.clipboard:
		var copy_e := TextBinding.clone(e)
		TextBinding.refresh_ids(copy_e, DialogueBlock.clipboard_texts)
		var nb := list.add_block(copy_e)
		if nb == null:
			continue
		if index >= 0:
			list.blocks.move_child(nb, index)
			index += 1
		DialogueBlock.select(nb, true)
		if first == null:
			first = nb
	if first:
		TimelineUtil.scroll_to(first)
	edited.emit()


func _all_selected_in(list: EventList) -> bool:
	var blocks := TimelineUtil.live_blocks(list)
	return not blocks.is_empty() and blocks.all(func(b): return b in DialogueBlock.selection)
