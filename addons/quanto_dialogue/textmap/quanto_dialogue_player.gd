class_name QuantoDialoguePlayer
extends Node
## Plays registered timelines through a DialogueRunner, one at a time.
##
##   player.play("intro")          # one timeline
##   player.play_queue(["a", "b"]) # in order
##   player.play_all()             # every timeline in the registry, sorted by id

signal timeline_started(timeline_id: String)
signal timeline_finished(timeline_id: String)
## After the last timeline of a queue / play_all() has finished.
signal queue_finished
## A timeline couldn't be started (unknown id, missing file, invalid content, no registry).
## `reason` is human readable. Queues report it and carry on with the next id.
signal timeline_failed(timeline_id: String, reason: String)

@export var runner: DialogueRunner
## Optional: set the text locale when the scene starts ("" = leave as is).
@export var locale := "en"
## When a timeline can't be started, also show the reason in the runner's text box
## (handy while testing: nothing to look for in the Output panel).
@export var show_errors_in_runner := true

var current_id := ""

var _queue: PackedStringArray = []
var _in_queue := false


func _ready() -> void:
	if runner == null:
		push_error("QuantoDialoguePlayer: assign a DialogueRunner")
		return
	runner.timeline_finished.connect(_on_runner_finished)
	if not locale.is_empty():
		QuantoDialogue.set_locale(locale)


func is_playing() -> bool:
	return not current_id.is_empty()


## False if something is already playing, the id is unknown, or the file can't be loaded.
func play(timeline_id: String) -> bool:
	if runner == null:
		push_error("QuantoDialoguePlayer: no DialogueRunner assigned, cannot play '%s'" % timeline_id)
		return false
	if is_playing():
		push_warning("QuantoDialoguePlayer: '%s' is still playing" % current_id)
		return false
	var err := QuantoDialogue.error_for(timeline_id)
	if not err.is_empty():
		return _fail(timeline_id, err)
	var data := QuantoDialogue.load_timeline(timeline_id)
	if data == null:
		return _fail(timeline_id, "Timeline '%s' could not be loaded (invalid file, see the warning above)" % timeline_id)
	current_id = timeline_id
	timeline_started.emit(timeline_id)
	runner.start(data)
	return true


## Plays the ids in order. Ids that can't be started are reported through
## timeline_failed and skipped. Returns false if none of them could be started.
func play_queue(timeline_ids: PackedStringArray) -> bool:
	if is_playing():
		push_warning("QuantoDialoguePlayer: '%s' is still playing" % current_id)
		return false
	if timeline_ids.is_empty():
		return _fail("", _nothing_to_play_reason())
	_queue = timeline_ids.duplicate()
	_in_queue = true
	return _play_next()


func play_all() -> bool:
	return play_queue(QuantoDialogue.ids())


## Drops what is still queued. The running timeline finishes normally.
func clear_queue() -> void:
	_queue.clear()


## Why a queue / play_all() has nothing to play. The usual cause: timelines exist as
## files but were never registered (a timeline is registered when it is saved or opened
## in the editor, or via Registry > Timelines > Scan folder).
func _nothing_to_play_reason() -> String:
	var reg := QuantoDialogue.registry()
	if not reg.is_usable():
		return "No usable registry: %s" % reg.status_message
	return "Nothing to play: the registry has no timelines (%s). Save/open your timelines in the editor, or use Registry > Timelines > Scan folder, then export again." % reg.path


func _fail(timeline_id: String, reason: String) -> bool:
	push_error("QuantoDialoguePlayer: " + reason)
	# Emit first: whatever the runner does below, listeners always hear about the failure.
	timeline_failed.emit(timeline_id, reason)
	if show_errors_in_runner and runner != null:
		runner.show_error(reason)
	return false


func _play_next() -> bool:
	while not _queue.is_empty():
		var id := _queue[0]
		_queue.remove_at(0)
		if play(id):
			return true
	_finish_queue()
	return false


func _finish_queue() -> void:
	if _in_queue:
		_in_queue = false
		queue_finished.emit()


func _on_runner_finished() -> void:
	var id := current_id
	current_id = ""
	timeline_finished.emit(id)
	if _in_queue:
		_play_next()
