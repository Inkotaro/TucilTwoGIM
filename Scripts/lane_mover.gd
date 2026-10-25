class_name LaneMover
extends Node
## Component: add as a child of Player. Moves the player between lanes on key press
## and squashes/stretches the sprite. Enabled by Player only in ROLLING_CHART mode.

signal lane_changed(lane: int)

## Leave empty to use the parent node.
@export var target: Node3D
## Leave empty to use target's child named "Sprite".
@export var sprite: Node3D

@export var enabled: bool = false : set = set_enabled

@export_group("Lanes")
## Evenly spaced: 0.625 between every pair of lanes. Bullets must use these same x values.
@export var lane_x: Array[float] = [-0.9375, -0.3125, 0.3125, 0.9375]
## One key per lane, left to right (physical keys).
@export var lane_keys: Array[int] = [KEY_D, KEY_F, KEY_J, KEY_K]
@export var start_lane: int = 1
@export var move_time: float = 0.08

@export_group("Squash And Stretch")
@export var stretch_amount: float = 0.5    # extra width when crossing all lanes (1 lane hop is about a third of this)
@export var hit_squash: Vector2 = Vector2(1.2, 0.75)  # pressing the lane you're already in
@export var settle_time: float = 0.35
## Squash toward the feet so the player never looks like it moves up or down.
@export var anchor_feet: bool = true

var current_lane: int = 0
var _base_scale := Vector3.ONE
var _base_pos_y := 0.0
var _half_h := 0.0
var _move_tween: Tween
var _squash_tween: Tween


func _ready() -> void:
	if target == null:
		target = get_parent() as Node3D
	if sprite == null and target != null:
		sprite = target.get_node_or_null("Sprite") as Node3D
	if sprite != null:
		_base_scale = sprite.scale
		_base_pos_y = sprite.position.y
	set_process_unhandled_input(enabled)
	if enabled:
		_snap_to_lane(start_lane)


func set_enabled(value: bool) -> void:
	enabled = value
	if not is_node_ready():
		return
	set_process_unhandled_input(value)
	if value:
		_snap_to_lane(start_lane)
	else:
		_kill_tweens()
		_reset_sprite()


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var lane := lane_keys.find(event.physical_keycode)
		if lane != -1 and lane < lane_x.size():
			go_to_lane(lane)


## Can also be called from code (e.g. a hit judge or AI).
func go_to_lane(lane: int) -> void:
	if target == null or lane < 0 or lane >= lane_x.size():
		return
	var target_x := lane_x[lane]
	var distance := absf(target_x - target.position.x)
	var changed := lane != current_lane
	current_lane = lane

	# Only x is ever tweened, y is never touched.
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.tween_property(target, "position:x", target_x, move_time)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	if distance > 0.01:
		var span := absf(lane_x[-1] - lane_x[0])
		var amount := clampf(distance / span, 0.1, 1.0) * stretch_amount
		_squash(Vector2(1.0 + amount, 1.0 - amount * 0.6))
	else:
		_squash(hit_squash)

	if changed:
		lane_changed.emit(lane)


func _snap_to_lane(lane: int) -> void:
	if target == null or lane_x.is_empty():
		return
	current_lane = clampi(lane, 0, lane_x.size() - 1)
	target.position.x = lane_x[current_lane]


func _squash(factor: Vector2) -> void:
	if sprite == null:
		return
	if _squash_tween and _squash_tween.is_valid():
		_squash_tween.kill()
	_half_h = _half_height()
	_apply_squash(factor)
	_squash_tween = create_tween()
	_squash_tween.tween_method(_apply_squash, factor, Vector2.ONE, settle_time)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _apply_squash(f: Vector2) -> void:
	sprite.scale = Vector3(_base_scale.x * f.x, _base_scale.y * f.y, _base_scale.z)
	if anchor_feet:
		# Keep the bottom edge fixed while the height changes.
		sprite.position.y = _base_pos_y - _half_h * (1.0 - f.y)


func _reset_sprite() -> void:
	if sprite == null:
		return
	sprite.scale = _base_scale
	sprite.position.y = _base_pos_y


# Half of the sprite's height in the sprite's parent space (0 if unknown or not centered).
func _half_height() -> float:
	if sprite is AnimatedSprite3D:
		var a := sprite as AnimatedSprite3D
		if a.centered and a.sprite_frames != null:
			var tex := a.sprite_frames.get_frame_texture(a.animation, a.frame)
			if tex != null:
				return tex.get_height() * a.pixel_size * _base_scale.y * 0.5
	elif sprite is Sprite3D:
		var s := sprite as Sprite3D
		if s.centered and s.texture != null:
			return (s.texture.get_height() / float(maxi(s.vframes, 1))) * s.pixel_size * _base_scale.y * 0.5
	return 0.0


func _kill_tweens() -> void:
	if _move_tween and _move_tween.is_valid():
		_move_tween.kill()
	if _squash_tween and _squash_tween.is_valid():
		_squash_tween.kill()
