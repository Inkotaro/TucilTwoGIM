class_name DialogueInterpreter
extends RefCounted
## Plays a DialogueDataResource in-game. No editor dependency.
##
## All displayed text goes through a TextResolver; the interpreter never sees raw text.
##
## Usage:
##   var runner := DialogueInterpreter.new()
##   runner.started.connect(func(timeline): ...)
##   runner.finished.connect(func(timeline): ...)
##   runner.line_shown.connect(func(speaker, text, text_id): ...)
##   runner.choices_shown.connect(func(options): ...)       # Array of resolved strings
##   runner.start(data, TimelineTextResolver.new(store, data.map_id, data.imports))
##   runner.advance()          # player clicked "continue"
##   runner.choose_option(1)   # player picked option 1

signal line_shown(speaker: String, text: String, text_id: String)
signal choices_shown(options: Array)  # Array[String], resolved
signal event_fired(key: String, value: String)
signal label_jump(key: String)
signal label_call(key: String)
signal started(timeline: String)
signal finished(timeline: String)

## Non-blocking events (jump, label, event...) allowed in a row before we assume an
## infinite loop such as `jump A` sitting right after `label A`.
const MAX_STEPS_PER_YIELD := 10000

var _stack: Array[Dictionary] = []     ## frames: {events: Array, pointer: int}
var _call_stack: Array = []            ## snapshots of _stack taken by CALL
var _labels: Dictionary = {}           ## key -> frames that rebuild the stack at that label
var _waiting := -1                     ## DialogueEvent.Type we are blocked on, or -1
var _pending_options: Array[DialogueChoice] = []
var _resolver: TextResolver = TextResolver.new()
var _timeline := ""


func start(data: DialogueDataResource, resolver: TextResolver = null) -> void:
	_stack.clear()
	_call_stack.clear()
	_labels.clear()
	_pending_options.clear()
	_waiting = -1
	_resolver = resolver if resolver != null else TextResolver.new()  # shows raw ids

	_timeline = data.map_id

	_index_labels(data.events, [])
	_push_frame(data.events)
	started.emit(_timeline)
	_step()


func advance() -> void:
	if _waiting != DialogueEvent.Type.LINE:
		return
	_waiting = -1
	_step()


func choose_option(index: int) -> void:
	if _waiting != DialogueEvent.Type.CHOICE:
		return
	if index < 0 or index >= _pending_options.size():
		return
	var chosen := _pending_options[index]
	_waiting = -1
	_pending_options.clear()
	if not chosen.events.is_empty():
		_push_frame(chosen.events)
	_step()


func jump_to_label(label_key: String, run_step := true) -> bool:
	if not _enter_label(label_key):
		return false
	label_jump.emit(label_key)
	if run_step:
		_step()
	return true


## Like jump, but a later RETURN comes back to just after the call.
func call_to_label(label_key: String, run_step := true) -> bool:
	if not _labels.has(label_key):
		push_error("DialogueInterpreter: Label key '%s' not found." % label_key)
		return false
	_call_stack.append(_snapshot_stack())
	_enter_label(label_key)
	label_call.emit(label_key)
	if run_step:
		_step()
	return true


# --- labels -------------------------------------------------------------------
## Labels are found at any depth (inside choice options too). Each one remembers the
## full chain of frames needed to be "inside" it, so a jump can rebuild the stack.
## `parents` = frames above `events`; a choice's frame resumes AFTER the choice.
func _index_labels(events: Array, parents: Array) -> void:
	for i in events.size():
		var ev: DialogueEvent = events[i]
		if ev == null:
			continue
		if ev.type == DialogueEvent.Type.LABEL and not ev.key.is_empty():
			if _labels.has(ev.key):
				push_warning("DialogueInterpreter: duplicate label '%s' ignored." % ev.key)
			else:
				_labels[ev.key] = parents + [{"events": events, "pointer": i}]
		elif ev.type == DialogueEvent.Type.CHOICE:
			var here := parents + [{"events": events, "pointer": i + 1}]
			for opt in ev.options:
				if opt != null:
					_index_labels(opt.events, here)


func _enter_label(label_key: String) -> bool:
	if not _labels.has(label_key):
		push_error("DialogueInterpreter: Label key '%s' not found." % label_key)
		return false
	_waiting = -1
	_pending_options.clear()
	_stack.assign(_copy_frames(_labels[label_key]))
	return true


# --- stack helpers ------------------------------------------------------------
func _push_frame(events: Array) -> void:
	_stack.append({"events": events, "pointer": 0})


## Frames are copied (pointers mutate); the event arrays inside are shared.
func _copy_frames(frames: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f: Dictionary in frames:
		out.append(f.duplicate())
	return out


func _snapshot_stack() -> Array[Dictionary]:
	return _copy_frames(_stack)


# --- execution ----------------------------------------------------------------
func _step() -> void:
	var guard := 0
	while not _stack.is_empty():
		guard += 1
		if guard > MAX_STEPS_PER_YIELD:
			push_error("DialogueInterpreter: more than %d events without a line or choice (infinite jump loop?). Stopping." % MAX_STEPS_PER_YIELD)
			_stack.clear()
			break

		var frame: Dictionary = _stack.back()
		var events: Array = frame["events"]
		var pointer: int = frame["pointer"]
		if pointer >= events.size():
			_stack.pop_back()
			continue
		frame["pointer"] = pointer + 1

		var ev: DialogueEvent = events[pointer]
		if ev == null:
			continue

		match ev.type:
			DialogueEvent.Type.LINE:
				_waiting = DialogueEvent.Type.LINE
				line_shown.emit(ev.speaker, _resolver.resolve(ev.text_id), ev.text_id)
				return
			DialogueEvent.Type.CHOICE:
				if ev.options.is_empty():
					continue
				_waiting = DialogueEvent.Type.CHOICE
				_pending_options.assign(ev.options)
				var texts := []
				for o in _pending_options:
					texts.append(_resolver.resolve(o.text_id))
				choices_shown.emit(texts)
				return
			DialogueEvent.Type.EVENT:
				event_fired.emit(ev.key, ev.value)
			DialogueEvent.Type.JUMP:
				if not jump_to_label(ev.key, false):
					return
			DialogueEvent.Type.CALL:
				if not call_to_label(ev.key, false):
					return
			DialogueEvent.Type.RETURN:
				if _call_stack.is_empty():
					push_warning("DialogueInterpreter: Return called with empty call stack.")
					_stack.clear()
					break
				_stack.assign(_call_stack.pop_back())
			DialogueEvent.Type.END:
				_stack.clear()
				break
			DialogueEvent.Type.LABEL, DialogueEvent.Type.NONE:
				pass  # a label is just a landing point
			_:
				push_warning("DialogueInterpreter: unknown event type '%s'" % ev.type)

	_waiting = -1
	finished.emit(_timeline)
