class_name Conductor
extends AudioStreamPlayer
## Owns the song, the song clock, the chart, and every rhythm event.
## Attach to an AudioStreamPlayer node. Nothing else in the game touches audio timing.

signal note_spawned(note: Dictionary)   # fires `lead_time` seconds BEFORE the note (spawn bullets here)
signal note_reached(note: Dictionary)   # fires exactly when the song hits the note
signal beat(index: int)                 # fires on every beat (needs "bpm" in the chart)

@export_file("*.json") var chart_path := "user://chart.json"
@export var chart_offset := 0.0         # seconds; POSITIVE = notes/bullets arrive EARLIER, negative = later
@export var lead_time := 1.0            # how early note_spawned fires
@export var travel_time := 0.15         # max seconds spent gliding between lanes

var notes: Array = []
var bpm := 0.0
var lane_count := 4

var _spawn_idx := 0
var _reach_idx := 0
var _beat_idx := 0
var _time := 0.0   # song time, computed ONCE per frame so every consumer agrees

func _ready() -> void:
	process_priority = -100   # update the clock before bullets and the player read it

# ---------------------------------------------------------------- control
func start_level(from_time := 0.0) -> bool:
	if not load_chart():
		return false
	play(from_time)
	_reset_cursors(from_time)
	return true

func restart() -> void:
	start_level(0.0)

func seek_to(time: float) -> void:
	seek(time)
	_reset_cursors(time)

func load_chart() -> bool:
	notes.clear()
	if not FileAccess.file_exists(chart_path):
		push_warning("Chart not found: " + chart_path)
		return false
	var f := FileAccess.open(chart_path, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary) or not data.has("notes"):
		push_warning("Invalid chart: " + chart_path)
		return false
	notes = data["notes"]
	notes.sort_custom(func(a, b): return a.t < b.t)
	bpm = float(data.get("bpm", 0.0))
	lane_count = int(data.get("lanes", 4))
	if stream == null and data.has("song"):
		stream = load(data["song"])
	return stream != null

# ---------------------------------------------------------------- clock
## Latency-compensated song time in seconds. Use this everywhere instead of
## get_playback_position().
func song_time() -> float:
	return _time

func _compute_time() -> float:
	return get_playback_position() \
		+ AudioServer.get_time_since_last_mix() \
		- AudioServer.get_output_latency() + chart_offset

# ---------------------------------------------------------------- events
func _process(_delta: float) -> void:
	_time = _compute_time() if playing else 0.0
	if not playing or notes.is_empty():
		return
	var t := _time

	while _spawn_idx < notes.size() and notes[_spawn_idx].t - lead_time <= t:
		note_spawned.emit(notes[_spawn_idx])
		_spawn_idx += 1

	while _reach_idx < notes.size() and notes[_reach_idx].t <= t:
		note_reached.emit(notes[_reach_idx])
		_reach_idx += 1

	if bpm > 0.0:
		var beat_len := 60.0 / bpm
		while _beat_idx * beat_len <= t:
			beat.emit(_beat_idx)
			_beat_idx += 1

func _reset_cursors(time: float) -> void:
	# Notes still ahead of `time` will (re)spawn; bullets are time-driven so late spawns land correctly.
	var first := _last_note_index(time) + 1
	_spawn_idx = first
	_reach_idx = first
	if bpm > 0.0:
		_beat_idx = int(ceil(time * bpm / 60.0))

# ---------------------------------------------------------------- lane state for the player
## Where the player should be right now: glide from lane `prev` to lane `next`.
## p is 0..1 and lands on 1.0 exactly at the next note's time.
func lane_blend() -> Dictionary:
	if notes.is_empty():
		return { "prev": 0, "next": 0, "p": 0.0 }

	var t := song_time()
	var i := _last_note_index(t)
	if i == -1:
		var first_lane := int(notes[0].lane)
		return { "prev": first_lane, "next": first_lane, "p": 0.0 }

	var prev_lane := int(notes[i].lane)
	if i + 1 >= notes.size():
		return { "prev": prev_lane, "next": prev_lane, "p": 0.0 }

	var nxt: Dictionary = notes[i + 1]
	var gap: float = nxt.t - notes[i].t
	var dur: float = max(min(travel_time, gap), 0.0001)
	var p: float = clamp((t - (nxt.t - dur)) / dur, 0.0, 1.0)
	return { "prev": prev_lane, "next": int(nxt.lane), "p": ease(p, -2.0) }

func _last_note_index(t: float) -> int:
	var lo := 0
	var hi := notes.size() - 1
	var res := -1
	while lo <= hi:
		var mid := (lo + hi) / 2
		if notes[mid].t <= t:
			res = mid
			lo = mid + 1
		else:
			hi = mid - 1
	return res
