class_name Player
extends CharacterBody3D

enum Mode { SIDE_PLATFORMING, TOP_DOWN, TOP_DOWN_SNAPPED, ROLLING_CHART }

const SPEED = 2.0
const JUMP_VELOCITY = 4.5

@export var is_menu = true
@export var mode: Mode = Mode.SIDE_PLATFORMING : set = set_mode

@export_group("Jumping")
@export var jump_buffer_time := 0.12   # press jump slightly BEFORE landing and it still counts
@export var coyote_time := 0.08        # jump slightly AFTER leaving a ledge and it still counts

@export_group("Stopping")
@export var stop_anim_time := 0.5     # how long the "stop" animation plays after you let go of run

@export_group("Top Down Snapped")
@export var grid_size := 1.0
@export var grid_origin := Vector2.ZERO   # x/z offset of the grid
@export var snap_speed := 8.0             # units per second between tiles

@export_group("Point And Click")
@export var stop_distance := 0.1
@export var click_speed := 5.0

@export_group("Rolling Chart")
@export var conductor: Conductor
@export var lane_mover: LaneMover   # optional: auto-found if a child node is named "LaneMover"
@export var follow_chart := false   # true = autoplay/demo: player follows the notes instead of input
@export var lane_x: Array[float] = [-0.9375, -0.3125, 0.3125, 0.9375]  # only used when follow_chart is on
@export var roll_animation := "roll"

@onready var sprite = $Sprite

## Set by PlayerInteractor (or anything else) to freeze movement input, e.g. during dialogue.
var input_locked := false

var jumped = false
var _roll_y := 0.0

# Jump buffer / coyote
var _jump_buffer := 0.0
var _coyote := 0.0

# Stop animation (platforming)
var _was_running := false
var _stop_timer := 0.0

# Snapped top-down
var _snap_moving := false
var _snap_target := Vector3.ZERO

# Point and click
var _click_target := Vector3.ZERO
var _has_click_target := false

# Top-down facing: "down", "up", "left", "right"
var facing := "down"

func _ready() -> void:
	if lane_mover == null:
		lane_mover = get_node_or_null("LaneMover") as LaneMover
	if mode == Mode.ROLLING_CHART and lane_mover == null:
		push_warning("Player: no LaneMover child found, keyboard lane control is disabled.")
	_enter_mode()
	
	

func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	if is_node_ready():
		_enter_mode()

func _enter_mode() -> void:
	velocity = Vector3.ZERO
	jumped = false
	_jump_buffer = 0.0
	_coyote = 0.0
	_was_running = false
	_stop_timer = 0.0
	_snap_moving = false
	_has_click_target = false
	sprite.scale.y = 1.0
	sprite.flip_h = false
	match mode:
		Mode.ROLLING_CHART:
			_roll_y = position.y
			_set_anim(roll_animation)
	# LaneMover only listens for keys while in ROLLING_CHART mode
	if lane_mover:
		lane_mover.enabled = (mode == Mode.ROLLING_CHART)

func _physics_process(delta: float) -> void:
	match mode:
		Mode.SIDE_PLATFORMING:
			_side_platforming(delta)
		Mode.TOP_DOWN:
			_top_down(delta)
		Mode.ROLLING_CHART:
			_rolling_chart()

# Movement input, zero while input is locked (dialogue, cutscenes).
func _move_input() -> Vector2:
	if input_locked:
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")

# ---------------------------------------------------------------- 1. Side platforming
func _side_platforming(delta: float) -> void:
	# Timers
	_jump_buffer = max(0.0, _jump_buffer - delta)
	if not input_locked and Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer_time

	if is_on_floor():
		_coyote = coyote_time
		jumped = false
	else:
		_coyote = max(0.0, _coyote - delta)
		velocity += get_gravity() * delta

	# Jump if a press is buffered AND we're grounded (or just left the ground)
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0
		jumped = true
		var tween = create_tween()
		sprite.scale.y = 2
		tween.tween_property(sprite, "scale:y", 1.0, 0.2)

	var input_dir := _move_input()
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var moving := direction != Vector3.ZERO

	if moving:
		sprite.flip_h = direction.x < 0
		velocity.x = direction.x * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	# Stop animation: starts the moment you let go of a run on the ground.
	if _was_running and not moving and is_on_floor():
		_stop_timer = stop_anim_time
	if moving or not is_on_floor():
		_stop_timer = 0.0
	_stop_timer = max(0.0, _stop_timer - delta)
	_was_running = moving and is_on_floor()

	if not is_on_floor() and velocity.y < 0:
		_set_anim("fall")
	elif jumped:
		_set_anim("jump")
	elif moving:
		_set_anim("run")
	elif _stop_timer > 0.0 and _has_anim("stop"):
		_set_anim("stop")
	else:
		_set_anim("idle")

	move_and_slide()

# ---------------------------------------------------------------- Animation helpers
func _has_anim(anim_name: StringName) -> bool:
	return sprite.sprite_frames != null and sprite.sprite_frames.has_animation(anim_name)

# Converts a world direction to "up" / "down" / "left" / "right" (dominant axis wins).
func _facing_from(dir: Vector3) -> String:
	if abs(dir.x) > abs(dir.z):
		return "right" if dir.x > 0 else "left"
	return "down" if dir.z > 0 else "up"

func _set_anim(anim_name: StringName) -> void:
	if not _has_anim(anim_name):
		return
	if sprite.animation != anim_name:
		sprite.animation = anim_name
	if not sprite.is_playing():
		sprite.play()

# Plays walk_<facing> while moving. When standing, uses idle_<facing> if you made one,
# otherwise falls back to "idle".
func _play_top_down_anim(moving: bool) -> void:
	sprite.flip_h = false
	if moving:
		_set_anim("walk_" + facing)
	elif _has_anim("idle_" + facing):
		_set_anim("idle_" + facing)
	else:
		_set_anim("idle")
		
func _top_down(delta: float) -> void:
	# Gravity, and stay glued to the floor when grounded
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0

	var input_dir := _move_input()
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		facing = _facing_from(direction)
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	_play_top_down_anim(direction != Vector3.ZERO)

	move_and_slide()   # delete the old `velocity.y = 0.0` line above this


# ---------------------------------------------------------------- 5. Rolling chart
# Key-driven lane movement lives in the LaneMover component.
# The chart only moves the player when follow_chart is on (autoplay/demo).
func _rolling_chart() -> void:
	velocity = Vector3.ZERO
	position.y = _roll_y
	_set_anim(roll_animation)

	if lane_mover or not follow_chart:
		return  # player input only, the chart never moves the player

	if conductor == null or conductor.notes.is_empty():
		return

	var s: Dictionary = conductor.lane_blend()
	position.x = lerp(lane_x[s.prev], lane_x[s.next], s.p)
