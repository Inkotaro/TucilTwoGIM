class_name QuantoShortcutActions

const PREFIX := "quanto_dialogue_"


static func defaults() -> Dictionary:
	var d := {
		PREFIX + "new":       [_key(KEY_N)],
		PREFIX + "open":      [_key(KEY_O)],
		PREFIX + "save":      [_key(KEY_S)],
		PREFIX + "save_as":   [_key(KEY_S, true)],
		PREFIX + "close_tab": [_key(KEY_W)],
		PREFIX + "run":       [_key(KEY_ENTER, false, true), _key(KEY_KP_ENTER)],
		PREFIX + "undo":      [_key(KEY_Z)],
		PREFIX + "redo":      [_key(KEY_Z, true), _key(KEY_Y)],
		PREFIX + "next_tab":  [_key(KEY_TAB), _key(KEY_PAGEDOWN)],
		PREFIX + "prev_tab":  [_key(KEY_TAB, true), _key(KEY_PAGEUP)],
		PREFIX + "choice_1":  [_key(KEY_1, false, false)],
		PREFIX + "choice_2":  [_key(KEY_2, false, false)],
		PREFIX + "choice_3":  [_key(KEY_3, false, false)],
		PREFIX + "choice_4":  [_key(KEY_4, false, false)],
		PREFIX + "copy_block":      [_key(KEY_C)],
		PREFIX + "cut_block":       [_key(KEY_X)],
		PREFIX + "paste_block":     [_key(KEY_V)],
		PREFIX + "duplicate_block": [_key(KEY_D)],
		PREFIX + "delete_block":    [_key(KEY_DELETE, false, false)],
		PREFIX + "add_event":    [_key(KEY_A, true, false)],  # Shift+A
		PREFIX + "select_all":   [_key(KEY_A)],               # Ctrl+A
	}
	for i in 9:
		d[PREFIX + "tab_" + str(i + 1)] = [_key((KEY_1 + i) as Key)]
	return d


static func _key(keycode: Key, shift := false, ctrl := true) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.shift_pressed = shift
	if ctrl:
		if OS.get_name() == "macOS":
			ev.meta_pressed = true
		else:
			ev.ctrl_pressed = true
	return ev


## Adds any missing action to the live InputMap. Safe to call any time;
## existing actions (including user rebinds from project.godot) are untouched.
static func ensure_in_input_map() -> void:
	var actions := defaults()
	for action: String in actions:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for ev in actions[action]:
			InputMap.action_add_event(action, ev)
