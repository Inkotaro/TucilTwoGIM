extends Node
## Autoload as "InteractionManager" (Project Settings > Globals > Autoload).
## Tracks nearby Interactables, chooses the best one, and handles the interact input.

signal focus_changed(interactable: Interactable)   # null when nothing is focused
signal interaction_started(interactable: Interactable)
signal interaction_finished(interactable: Interactable)

const INTERACT_ACTION := "interact"

var focused: Interactable = null
var locked: bool = false  # true while dialogue/cutscene is running

var _candidates: Array[Interactable] = []
var _player: Node3D = null
var _current: Interactable = null  # the interactable currently being used


func register(interactable: Interactable, player: Node3D) -> void:
	_player = player
	if not _candidates.has(interactable):
		_candidates.append(interactable)


func unregister(interactable: Interactable) -> void:
	_candidates.erase(interactable)
	if focused == interactable:
		_set_focus(null)


func _physics_process(_delta: float) -> void:
	if locked or _player == null:
		_set_focus(null)
		return
	_set_focus(_pick_best())


func _unhandled_input(event: InputEvent) -> void:
	if locked or focused == null:
		return
	if event.is_action_pressed(INTERACT_ACTION):
		get_viewport().set_input_as_handled()
		start_interaction(focused)


func start_interaction(target: Interactable) -> void:
	if locked or not target.enabled:
		return
	_current = target
	lock()
	interaction_started.emit(target)
	target.interact(_player)


## Call this when the NPC is done (dialogue ended, cutscene over, etc.).
func finish_interaction() -> void:
	var done := _current
	_current = null
	unlock()
	if done:
		interaction_finished.emit(done)


func lock() -> void:
	locked = true


func unlock() -> void:
	locked = false


func _pick_best() -> Interactable:
	var best: Interactable = null
	var best_priority := -2147483648
	var best_dist := INF

	for item in _candidates:
		if not is_instance_valid(item) or not item.enabled:
			continue

		var to_item := item.global_position - _player.global_position
		var dist := to_item.length()

		if item.require_facing:
			var flat := Vector3(to_item.x, 0.0, to_item.z).normalized()
			var forward := -_player.global_transform.basis.z
			forward = Vector3(forward.x, 0.0, forward.z).normalized()
			if forward.dot(flat) < item.facing_threshold:
				continue

		if item._priority > best_priority or (item._priority == best_priority and dist < best_dist):
			best = item
			best_priority = item._priority
			best_dist = dist

	return best


func _set_focus(target: Interactable) -> void:
	if focused == target:
		return
	if is_instance_valid(focused):
		focused.set_focused(false)
	focused = target
	if focused:
		focused.set_focused(true)
	focus_changed.emit(focused)
