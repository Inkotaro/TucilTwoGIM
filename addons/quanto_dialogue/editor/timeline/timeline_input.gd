@tool
class_name TimelineInput
extends RefCounted
## Keyboard shortcut dispatch plus block navigation keys.
## `handle()` returns true if the event was consumed.

const _TEXT_OWNED := [
	"undo", "redo",
	"copy_block", "cut_block", "paste_block",
	"select_all", "delete_block", "duplicate_block",
]  # text fields keep their own editing shortcuts

var shortcuts: Dictionary  # action name -> Callable
var _list: EventList
var _nav: TimelineNavigator
var _prefix: String


func _init(root_list: EventList, nav: TimelineNavigator, actions: Dictionary, prefix: String) -> void:
	_list = root_list
	_nav = nav
	shortcuts = actions
	_prefix = prefix


func handle(event: InputEvent, viewport: Viewport) -> bool:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return false
	var key := event as InputEventKey
	var focus := viewport.gui_get_focus_owner()
	var typing := focus is LineEdit or focus is TextEdit

	for action: String in shortcuts:
		# exact_match so Ctrl+S doesn't also fire on Ctrl+Shift+S
		if not InputMap.has_action(action) or not event.is_action_pressed(action, false, true):
			continue
		if typing and action.trim_prefix(_prefix) in _TEXT_OWNED:
			return false
		shortcuts[action].call()
		return true

	var is_enter := key.keycode in [KEY_ENTER, KEY_KP_ENTER]
	var plain := not key.shift_pressed and not key.alt_pressed and not key.is_command_or_control_pressed()

	if is_enter and plain and typing and _list.is_ancestor_of(focus):
		_nav.enter_to_next(focus)
		return true

	if not typing and not key.is_command_or_control_pressed() and not key.alt_pressed:
		match key.keycode:
			KEY_DOWN:
				_nav.move_selection(1, key.shift_pressed)
				return true
			KEY_UP:
				_nav.move_selection(-1, key.shift_pressed)
				return true
			KEY_RIGHT:
				_nav.nav_nested(true)
				return true
			KEY_LEFT:
				_nav.nav_nested(false)
				return true
		if is_enter and not key.shift_pressed \
				and not DialogueBlock.selection.is_empty() and not focus is BaseButton:
			_nav.focus_selected()
			return true

	if key.keycode == KEY_ESCAPE and not DialogueBlock.selection.is_empty():
		DialogueBlock.clear_selection()
		return true
	return false
