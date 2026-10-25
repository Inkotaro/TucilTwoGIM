extends Node

@export var song_path := "res://rolling-girl.mp3"
@export var save_path := "user://chart.json"
@export var bpm := 128.0
@export var snap_division := 0      # 0 = off, 4 = 1/4 beat, 8 = 1/8 beat, etc.
@export var manual_offset := 0.0    # seconds; tweak if your notes feel early/late

const LANE_KEYS := [KEY_D, KEY_F, KEY_J, KEY_K]

@onready var audio: AudioStreamPlayer2D = $AudioStreamPlayer
var notes: Array = []

func _ready() -> void:
	audio.stream = load(song_path)
	print("SPACE play/pause | D F J K record lanes | BACKSPACE undo | R restart | S save | LEFT/RIGHT seek")

# Latency-compensated song time (the standard Godot rhythm-game clock).
func song_time() -> float:
	var t := audio.get_playback_position() \
		+ AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency()
	return max(0.0, t + manual_offset)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return

	# Lane keys: record a note
	var lane := LANE_KEYS.find(event.keycode)
	if lane != -1:
		if audio.playing:
			_add_note(song_time(), lane)
		return

	match event.keycode:
		KEY_SPACE:
			if audio.playing:
				audio.stream_paused = true
				audio.stop()   # keeps position via seek below
			else:
				audio.play(_resume_pos)
		KEY_BACKSPACE:
			if notes.size() > 0:
				notes.pop_back()
				print("Removed last note. Total: ", notes.size())
		KEY_R:
			audio.stop(); _resume_pos = 0.0; notes.clear(); audio.play()
		KEY_S:
			save_chart()
		KEY_LEFT:
			_seek(-2.0)
		KEY_RIGHT:
			_seek(2.0)

var _resume_pos := 0.0

func _seek(delta: float) -> void:
	var pos: float = max(0.0, audio.get_playback_position() + delta)
	if audio.playing:
		audio.seek(pos)
	_resume_pos = pos

func _add_note(t: float, lane: int) -> void:
	if snap_division > 0:
		var step := 60.0 / bpm / (snap_division / 4.0)
		t = round(t / step) * step
	notes.append({ "t": snappedf(t, 0.001), "lane": lane })
	print("Note  t=%.3f  lane=%d" % [t, lane])

func save_chart() -> void:
	notes.sort_custom(func(a, b): return a.t < b.t)
	var data := {
		"song": song_path,
		"bpm": bpm,
		"lanes": 4,
		"notes": notes,
	}
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	print("Saved %d notes to %s" % [notes.size(), ProjectSettings.globalize_path(save_path)])
