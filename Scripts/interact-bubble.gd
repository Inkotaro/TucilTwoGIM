extends Sprite3D
## Attach to the Sprite3D that sits above the player (child of the Player).
## Grows in with squash and stretch when an interactable is in focus, shrinks out when it's not,
## and gently pulses while visible. Set Billboard to Enabled on the Sprite3D so it faces the camera.

@export_group("Squash And Stretch")
@export var pop_time := 0.1                # length of each step of the grow / shrink
@export var idle_pulse := true             # gentle shrink-and-grow loop while visible
@export var pulse_amount := 0.08
@export var pulse_time := 0.5

var _base_scale := Vector3.ONE
var _tween: Tween
var _shown := false


func _ready() -> void:
	_base_scale = scale
	scale = Vector3.ZERO
	visible = false
	InteractionManager.focus_changed.connect(_on_focus_changed)


func _on_focus_changed(target: Interactable) -> void:
	if target != null:
		grow()
	else:
		shrink()


func grow() -> void:
	if _shown:
		return
	_shown = true
	_restart_tween()
	visible = true
	# Squash wide and flat, stretch tall, then settle.
	_tween.tween_property(self, "scale", _squash(1.3, 0.7), pop_time)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", _squash(0.9, 1.15), pop_time)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "scale", _base_scale, pop_time)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if idle_pulse:
		_tween.tween_callback(_start_pulse)


func shrink() -> void:
	if not _shown:
		return
	_shown = false
	_restart_tween()
	# Quick stretch up (anticipation), then squash away to nothing.
	_tween.tween_property(self, "scale", _squash(0.85, 1.2), pop_time * 0.6)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", Vector3.ZERO, pop_time * 1.2)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func(): visible = false)


func _start_pulse() -> void:
	_restart_tween()
	_tween.set_loops()   # forever
	_tween.tween_property(self, "scale", _squash(1.0 + pulse_amount, 1.0 - pulse_amount), pulse_time * 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(self, "scale", _squash(1.0 - pulse_amount, 1.0 + pulse_amount), pulse_time * 0.5)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# Base scale multiplied by an x/y squash factor (z is left alone).
func _squash(x: float, y: float) -> Vector3:
	return Vector3(_base_scale.x * x, _base_scale.y * y, _base_scale.z)


func _restart_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
