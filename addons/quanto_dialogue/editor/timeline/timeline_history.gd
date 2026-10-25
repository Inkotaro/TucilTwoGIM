class_name EditHistory
extends RefCounted

const MAX_STEPS := 100

var last_delta: Dictionary = {}   ## delta of the step just undone/redone
var last_reverse := false         ## true if last_delta must be applied reversed

var _undo: Array = []   ## {events: before, delta}
var _redo: Array = []   ## {events: after, delta}
var _current: Array[DialogueEvent] = []

func reset(snapshot: Array[DialogueEvent]) -> void:
	_undo.clear()
	_redo.clear()
	_current = snapshot

func replace_current(snapshot: Array[DialogueEvent]) -> void:
	_current = snapshot

func commit(snapshot: Array[DialogueEvent], delta: Dictionary = {}) -> void:
	_undo.push_back({"events": _current, "delta": delta})
	if _undo.size() > MAX_STEPS:
		_undo.pop_front()
	_current = snapshot
	_redo.clear()

func can_undo() -> bool:
	return not _undo.is_empty()

func can_redo() -> bool:
	return not _redo.is_empty()

func undo() -> Array[DialogueEvent]:
	var step: Dictionary = _undo.pop_back()
	_redo.push_back({"events": _current, "delta": step.delta})
	_current = step.events
	last_delta = step.delta
	last_reverse = true
	return _current

func redo() -> Array[DialogueEvent]:
	var step: Dictionary = _redo.pop_back()
	_undo.push_back({"events": _current, "delta": step.delta})
	_current = step.events
	last_delta = step.delta
	last_reverse = false
	return _current
