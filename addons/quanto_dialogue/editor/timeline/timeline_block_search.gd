@tool
class_name TimelineBlockSearch
extends RefCounted
## In-timeline block search: Enter = next match, Shift+Enter = previous.

var _edit: LineEdit
var _list: EventList
var _matches: Array[DialogueBlock] = []
var _index := -1


func _init(edit: LineEdit, list: EventList) -> void:
	_edit = edit
	_list = list
	edit.text_changed.connect(func(_t): search())
	edit.text_submitted.connect(func(_t): step(1))
	edit.gui_input.connect(_on_gui_input)


func search() -> void:
	_matches = _list.find_matches(_edit.text.strip_edges().to_lower())
	_index = 0 if not _matches.is_empty() else -1
	_show_current()


func step(delta: int) -> void:
	if _matches.is_empty():
		return
	_index = posmod(_index + delta, _matches.size())
	_show_current()


func _show_current() -> void:
	var current: DialogueBlock = _matches[_index] if _index >= 0 and _index < _matches.size() else null
	_list.set_highlights(_matches, current)
	if current:
		TimelineUtil.scroll_to(current)


func _on_gui_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and k.shift_pressed and k.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		step(-1)
		_edit.accept_event()
