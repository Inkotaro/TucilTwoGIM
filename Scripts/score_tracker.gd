class_name ScoreTracker
extends Node
## Component: add anywhere in the level and assign `level`.
## Scores every note, tracks combo and multiplier, and stores the final results in
## Engine.get_meta("last_results") when the song ends, so the main menu can show them.

signal score_changed(score: int, combo: int, multiplier: int)
signal combo_broken(lost_combo: int)
signal results_ready(results: Dictionary)

@export var level: RhythmLevel
@export var points_per_note := 100
@export var combo_per_multiplier := 10   # +1x multiplier every N combo
@export var max_multiplier := 4
@export var miss_penalty := 0            # points lost on a miss (0 = none)

var score := 0
var combo := 0
var max_combo := 0
var hits := 0
var misses := 0


func _ready() -> void:
	if level == null:
		push_warning("ScoreTracker: assign the level.")
		return
	level.note_success.connect(_on_success)
	level.note_failed.connect(_on_failed)
	level.level_finished.connect(_on_level_finished)
	if Engine.has_meta("last_results"):
		Engine.remove_meta("last_results")   # clear results from a previous run
	score_changed.emit(score, combo, multiplier())


func multiplier() -> int:
	return mini(1 + combo / maxi(combo_per_multiplier, 1), max_multiplier)


func _on_success(_note: Dictionary) -> void:
	score += points_per_note * multiplier()
	hits += 1
	combo += 1
	max_combo = maxi(max_combo, combo)
	score_changed.emit(score, combo, multiplier())


func _on_failed(_note: Dictionary) -> void:
	var lost := combo
	score = maxi(0, score - miss_penalty)
	misses += 1
	combo = 0
	if lost > 0:
		combo_broken.emit(lost)
	score_changed.emit(score, combo, multiplier())


func _on_level_finished() -> void:
	var total := level.conductor.notes.size()
	if total == 0:
		total = hits + misses
	var accuracy := (float(hits) / float(total) * 100.0) if total > 0 else 0.0
	var results := {
		"score": score,
		"max_combo": max_combo,
		"hits": hits,
		"misses": misses,
		"total_notes": total,
		"accuracy": accuracy,
		"grade": _grade(accuracy),
		"full_combo": misses == 0 and total > 0,
	}
	Engine.set_meta("last_results", results)
	results_ready.emit(results)


func _grade(accuracy: float) -> String:
	if accuracy >= 95.0: return "S"
	if accuracy >= 85.0: return "A"
	if accuracy >= 70.0: return "B"
	if accuracy >= 50.0: return "C"
	return "D"
