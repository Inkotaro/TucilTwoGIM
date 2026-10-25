extends Area3D
## Falls toward the player's height and arrives exactly at hit_time.
## Position is computed from the song clock (not velocity), so it stays in sync
## through lag spikes, pauses and seeks.

var _conductor: Conductor
var _hit_time := 0.0
var _speed := 8.0
var _target_y := 0.0

func setup(conductor: Conductor, hit_time: float, x: float, target_y: float, z: float, speed: float) -> void:
	_conductor = conductor
	_hit_time = hit_time
	_target_y = target_y
	_speed = speed
	global_position = Vector3(x, target_y + (hit_time - conductor.song_time()) * speed, z)

func _process(_delta: float) -> void:
	if _conductor == null:
		return
	var remaining := _hit_time - _conductor.song_time()
	global_position.y = _target_y + remaining * _speed
	if remaining < -0.5:
		queue_free()
