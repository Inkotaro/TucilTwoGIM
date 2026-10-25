class_name RhythmLevel
extends Node3D
## The audio-driven level. Listens to the Conductor and spawns bullets from the chart.
##
## DODGE: a bullet in every lane EXCEPT the note's lane. Be in the note's lane to survive.
## CATCH: one bullet in the note's lane only. Be in the note's lane to hit it.
## Either way, the note's lane is the "correct" lane, checked at the exact note time.
## When the song ends, emits level_finished and changes to the main menu.

enum Mode { DODGE, CATCH }

signal note_success(note: Dictionary)   # player was in the note's lane (dodged / caught)
signal note_failed(note: Dictionary)    # player was in a different lane (got hit / missed)
signal level_finished                   # song ended (ScoreTracker stores the results on this)

@export var mode: Mode = Mode.DODGE
@export var conductor: Conductor
@export var player: Player
@export var bullet_scene: PackedScene       # Area3D with the bullet script attached
@export var approach_time := 2.0            # seconds a bullet is visible before it lands (bigger = slower, spawns sooner)
@export var spawn_height := 10.0            # how far from the player bullets appear
@export var from_below := true              # true = bullets rise from below, false = fall from above
@export var target_y_offset := 0.0          # shift where bullets land (e.g. 0.5 to hit the body, not the feet)

@export_group("Song End")
@export_file("*.tscn") var main_menu_scene := "res://Scenes/main-menu.tscn"
@export var end_delay := 1.5                # seconds to wait after the song ends
@export var fade_rect: ColorRect            # optional: fades to black before changing scene
@export var fade_time := 0.6

@export_group("Beat Effects")
## Your PhantomCamera3D node (typed as Node3D so the script still loads without the addon).
@export var phantom_camera: Node3D
## The full-screen ColorRect that has the chromatic aberration ShaderMaterial.
@export var chroma_rect: ColorRect
@export var beat_every := 1                 # pulse on every Nth beat
@export var beat_pulse_time := 0.25
@export var beat_fov_punch := 2.0           # degrees of zoom-in on the beat (0 = off)
@export var beat_chroma_boost := 0.02       # extra chromatic strength on the beat (0 = off)

@export_group("Lane Visuals")
@export var draw_lanes := true
@export var lane_line_width := 0.03
@export var lane_overshoot := 3.0           # how far each line continues PAST the player
@export var pressed_width_scale := 3.0      # line gets this much thicker while its key is held
@export var lane_color := Color(1, 1, 1, 0.35)
@export var lane_pressed_color := Color(1, 1, 1, 0.9)
@export var glow_time := 0.08               # seconds to fade the highlight in/out
@export var receptor_width := 0.0           # 0 = auto (90% of the lane spacing)
@export var receptor_height := 0.08         # the bar where bullets land

var bullet_speed := 5.0   # derived: spawn_height / approach_time (world units per second)
var _bullets := {}        # note key -> Array of bullets spawned for that note
var _ending := false

var _base_fov := 75.0
var _base_chroma := 0.01
var _beat_tween: Tween

var _lane_nodes: Array[MeshInstance3D] = []
var _lane_mats: Array[StandardMaterial3D] = []
var _receptor_mats: Array[StandardMaterial3D] = []
var _lane_glow: Array[float] = []

func _ready() -> void:
	# Bullets cover spawn_height in approach_time, so the Conductor spawns them exactly that early.
	bullet_speed = spawn_height / maxf(approach_time, 0.01)
	conductor.lead_time = approach_time
	conductor.note_spawned.connect(_on_note_spawned)
	conductor.note_reached.connect(_on_note_reached)
	conductor.beat.connect(_on_beat)
	conductor.finished.connect(_on_song_finished)

	player.set_mode(Player.Mode.ROLLING_CHART)
	_read_beat_defaults()
	if draw_lanes:
		_build_lanes()
	conductor.start_level()

func _process(delta: float) -> void:
	_update_lane_highlights(delta)

# ---------------------------------------------------------------- bullets
func _on_note_spawned(note: Dictionary) -> void:
	var note_lane := int(note.lane)
	var lanes := _lane_xs()
	var spawned: Array = []
	for lane in lanes.size():
		# DODGE: skip the note's lane. CATCH: only the note's lane.
		if (mode == Mode.DODGE) == (lane == note_lane):
			continue
		var bullet := bullet_scene.instantiate()
		add_child(bullet)   # must be in the tree before setup() sets global_position
		var pos := _lane_position(lane)
		bullet.setup(
			conductor, float(note.t),
			pos.x, pos.y + target_y_offset, pos.z,
			-bullet_speed if from_below else bullet_speed   # negative speed = spawn below, move up
		)
		spawned.append(bullet)
	_bullets[_key(note)] = spawned

func _on_note_reached(note: Dictionary) -> void:
	var in_lane := _player_lane() == int(note.lane)
	var bullets: Array = _bullets.get(_key(note), [])
	_bullets.erase(_key(note))

	if in_lane:
		# CATCH: the bullet is consumed on a successful hit.
		if mode == Mode.CATCH:
			for b in bullets:
				if is_instance_valid(b):
					b.queue_free()
		note_success.emit(note)
	else:
		note_failed.emit(note)

func _key(note: Dictionary) -> String:
	return "%s_%s" % [note.t, note.lane]

# ---------------------------------------------------------------- song end
func _on_song_finished() -> void:
	if _ending:
		return
	_ending = true
	level_finished.emit()   # ScoreTracker stores results synchronously here

	await get_tree().create_timer(end_delay).timeout

	if fade_rect:
		fade_rect.show()
		fade_rect.modulate.a = 0.0
		var t := create_tween()
		t.tween_property(fade_rect, "modulate:a", 1.0, fade_time)
		await t.finished

	if main_menu_scene.is_empty():
		push_warning("RhythmLevel: main_menu_scene is not set, staying on this scene.")
		return
	get_tree().change_scene_to_file(main_menu_scene)

# ---------------------------------------------------------------- beat effects
func _read_beat_defaults() -> void:
	if phantom_camera:
		var f = phantom_camera.get("fov")
		if f != null:
			_base_fov = float(f)
	if chroma_rect and chroma_rect.material is ShaderMaterial:
		var s = (chroma_rect.material as ShaderMaterial).get_shader_parameter("strength")
		if s != null:
			_base_chroma = float(s)

func _on_beat(index: int) -> void:
	if beat_every > 1 and index % beat_every != 0:
		return

	if _beat_tween and _beat_tween.is_valid():
		_beat_tween.kill()
	_beat_tween = create_tween().set_parallel(true)

	# Camera punch-in, then ease back out.
	if phantom_camera and beat_fov_punch != 0.0:
		phantom_camera.set("fov", _base_fov - beat_fov_punch)
		_beat_tween.tween_property(phantom_camera, "fov", _base_fov, beat_pulse_time)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	# Chromatic aberration spike, then ease back to normal.
	if chroma_rect and chroma_rect.material is ShaderMaterial and beat_chroma_boost != 0.0:
		var peak := minf(_base_chroma + beat_chroma_boost, 0.05)   # shader range tops out at 0.05
		_beat_tween.tween_method(_set_chroma, peak, _base_chroma, beat_pulse_time)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _set_chroma(value: float) -> void:
	(chroma_rect.material as ShaderMaterial).set_shader_parameter("strength", value)

# ---------------------------------------------------------------- lane visuals
func _make_lane_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = color
	return m

func _build_lanes() -> void:
	var xs := _lane_xs()
	var spacing := absf(xs[1] - xs[0]) if xs.size() > 1 else 0.5
	var bar_width := receptor_width if receptor_width > 0.0 else spacing * 0.9
	var dir := -1.0 if from_below else 1.0   # which side of the player bullets come from

	for lane in xs.size():
		var pos := _lane_position(lane)
		var row_y := pos.y + target_y_offset

		# Lane line: from where bullets spawn, through the player's row, and past it.
		var length := spawn_height + lane_overshoot
		var center_y := row_y + dir * (spawn_height - lane_overshoot) * 0.5
		var line := MeshInstance3D.new()
		var line_mesh := QuadMesh.new()
		line_mesh.size = Vector2(lane_line_width, length)
		line.mesh = line_mesh
		var line_mat := _make_lane_material(lane_color)
		line.material_override = line_mat
		add_child(line)
		line.global_position = Vector3(pos.x, center_y, pos.z - 0.05)

		# Receptor: brighter bar where the bullet lands.
		var receptor := MeshInstance3D.new()
		var receptor_mesh := QuadMesh.new()
		receptor_mesh.size = Vector2(bar_width, receptor_height)
		receptor.mesh = receptor_mesh
		var receptor_mat := _make_lane_material(_receptor_color(0.0))
		receptor.material_override = receptor_mat
		add_child(receptor)
		receptor.global_position = Vector3(pos.x, row_y, pos.z - 0.04)

		_lane_nodes.append(line)
		_lane_mats.append(line_mat)
		_receptor_mats.append(receptor_mat)
		_lane_glow.append(0.0)

func _receptor_color(glow: float) -> Color:
	var base := Color(lane_color.r, lane_color.g, lane_color.b, minf(lane_color.a * 0.6, 1.0))
	var pressed := Color(lane_pressed_color.r, lane_pressed_color.g, lane_pressed_color.b, 1.0)
	return base.lerp(pressed, glow)

# A lane lights up and thickens while its key is held (keys come from the player's LaneMover).
func _update_lane_highlights(delta: float) -> void:
	if _lane_mats.is_empty():
		return
	var keys: Array[int] = []
	if player.lane_mover:
		keys = player.lane_mover.lane_keys
	for lane in _lane_mats.size():
		var held := lane < keys.size() and Input.is_physical_key_pressed(keys[lane] as Key)
		_lane_glow[lane] = move_toward(_lane_glow[lane], 1.0 if held else 0.0, delta / maxf(glow_time, 0.001))
		var g := _lane_glow[lane]
		_lane_mats[lane].albedo_color = lane_color.lerp(lane_pressed_color, g)
		_lane_nodes[lane].scale.x = lerpf(1.0, pressed_width_scale, g)
		_receptor_mats[lane].albedo_color = _receptor_color(g)

# ---------------------------------------------------------------- lane helpers
# Lanes come from the player's LaneMover so bullets and player always agree.
func _lane_xs() -> Array[float]:
	if player.lane_mover:
		return player.lane_mover.lane_x
	return player.lane_x

func _player_lane() -> int:
	if player.lane_mover:
		return player.lane_mover.current_lane
	return -1

# World position of the player's row for `lane` (x from the lane, y/z from the player).
# lane_x is in the player's parent space, so convert to world space.
func _lane_position(lane: int) -> Vector3:
	var xs := _lane_xs()
	lane = clampi(lane, 0, xs.size() - 1)
	var local := Vector3(xs[lane], player.position.y, player.position.z)
	var parent := player.get_parent() as Node3D
	return parent.to_global(local) if parent else local
