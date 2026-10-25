class_name SubtitleSpawner
extends Node
## Component: shows subtitles from an .srt file, synced to the Conductor's song clock.
## Add anywhere in the level, assign `conductor` and `srt_path`.
## If no `label` is assigned, it builds its own centered label at the bottom of the screen.

@export var conductor: Conductor
@export_file("*.srt") var srt_path := ""
@export var label: Label                    # optional: use your own styled Label
@export var subtitle_offset := 0.0          # seconds; positive = subtitles appear later
@export var fade_time := 0.12

@export_group("Built-in Label")
@export var font_size := 28
@export var bottom_margin := 48.0
@export var side_margin := 120.0

var cues: Array[Dictionary] = []   # each: { start: float, end: float, text: String }
var _current := -1
var _tween: Tween


func _ready() -> void:
	if label == null:
		_build_label()
	label.text = ""
	label.modulate.a = 0.0
	if not srt_path.is_empty():
		load_srt(srt_path)


func load_srt(path: String) -> bool:
	cues.clear()
	_current = -1
	if not FileAccess.file_exists(path):
		push_warning("SubtitleSpawner: file not found: " + path)
		return false
	cues = parse_srt(FileAccess.get_file_as_string(path))
	return not cues.is_empty()


func _process(_delta: float) -> void:
	if conductor == null or cues.is_empty():
		return
	if not conductor.playing:
		if _current != -1:
			_current = -1
			_hide()
		return

	# Pure audio time (the chart_offset only shifts notes, not the voice/lyrics).
	var t := conductor.song_time() - conductor.chart_offset + subtitle_offset
	var idx := _find_cue(t)
	if idx != _current:
		_current = idx
		if idx == -1:
			_hide()
		else:
			_show(cues[idx].text)


func _find_cue(t: float) -> int:
	if _current != -1 and t >= cues[_current].start and t < cues[_current].end:
		return _current
	for i in cues.size():
		if t >= cues[i].start and t < cues[i].end:
			return i
	return -1


func _show(text: String) -> void:
	_restart_tween()
	label.text = text
	_tween.tween_property(label, "modulate:a", 1.0, fade_time)


func _hide() -> void:
	_restart_tween()
	_tween.tween_property(label, "modulate:a", 0.0, fade_time)
	_tween.tween_callback(func():
		if _current == -1:
			label.text = ""
	)


func _restart_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()


# ---------------------------------------------------------------- SRT parsing
func parse_srt(raw: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var text := raw.replace("\r\n", "\n").replace("\r", "\n").trim_prefix("\uFEFF")
	# Treat blank lines that contain spaces as real blank lines.
	text = RegEx.create_from_string("\\n[ \\t]*\\n").sub(text, "\n\n", true)

	var re_time := RegEx.create_from_string(
		"(\\d+):(\\d+):(\\d+)[,.](\\d+)\\s*-->\\s*(\\d+):(\\d+):(\\d+)[,.](\\d+)")
	var re_tags := RegEx.create_from_string("<[^>]+>|\\{\\\\[^}]*\\}")

	for block in text.split("\n\n", false):
		var lines := block.strip_edges().split("\n")
		var time_line := -1
		var m: RegExMatch
		for i in lines.size():
			m = re_time.search(lines[i])
			if m:
				time_line = i
				break
		if time_line == -1:
			continue

		var body := "\n".join(lines.slice(time_line + 1))
		body = re_tags.sub(body, "", true).strip_edges()
		if body.is_empty():
			continue
		result.append({
			"start": _to_seconds(m, 1),
			"end": _to_seconds(m, 5),
			"text": body,
		})

	result.sort_custom(func(a, b): return a.start < b.start)
	return result


func _to_seconds(m: RegExMatch, first_group: int) -> float:
	var h := m.get_string(first_group).to_int()
	var mi := m.get_string(first_group + 1).to_int()
	var s := m.get_string(first_group + 2).to_int()
	var frac := ("0." + m.get_string(first_group + 3)).to_float()
	return h * 3600.0 + mi * 60.0 + s + frac


# ---------------------------------------------------------------- built-in label
func _build_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	label = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	layer.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_top = -(font_size * 3.0 + bottom_margin)
	label.offset_bottom = -bottom_margin
	label.offset_left = side_margin
	label.offset_right = -side_margin
