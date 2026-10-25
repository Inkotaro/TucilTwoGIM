class_name ScoreHUD
extends CanvasLayer
## Builds a simple score / combo display in the top-right corner (no scene setup needed).
## Add as a node in the level and assign `tracker`.

@export var tracker: ScoreTracker
@export var font_size := 32

var _score_label: Label
var _combo_label: Label
var _last_combo := 0


func _ready() -> void:
	layer = 5
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 24)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	_score_label = _make_label(font_size)
	_combo_label = _make_label(int(font_size * 0.8))
	box.add_child(_score_label)
	box.add_child(_combo_label)
	_score_label.text = "0000000"
	_combo_label.text = ""

	if tracker:
		tracker.score_changed.connect(_on_score_changed)
		tracker.combo_broken.connect(_on_combo_broken)

var font = preload("res://Assets/Fonts/dungeon-mode.ttf")
func _make_label(size: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_font_override("font",font)
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	return l


func _on_score_changed(score: int, combo: int, multiplier: int) -> void:
	_score_label.text = "%07d" % score
	if combo >= 2:
		_combo_label.text = "%d COMBO  x%d" % [combo, multiplier]
	else:
		_combo_label.text = ""
	if combo > _last_combo and combo >= 2:
		_pop(_combo_label)
	_last_combo = combo


func _on_combo_broken(_lost: int) -> void:
	_score_label.modulate = Color(1.0, 0.35, 0.35)
	create_tween().tween_property(_score_label, "modulate", Color.WHITE, 0.4)


# Small squash-and-stretch pop when the combo grows.
func _pop(label: Label) -> void:
	var min_size := label.get_minimum_size()
	label.pivot_offset = Vector2(min_size.x, min_size.y * 0.5)
	label.scale = Vector2(1.25, 0.8)
	create_tween().tween_property(label, "scale", Vector2.ONE, 0.2)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
