@tool
class_name ScaleInEffect
extends RichTextEffect

var bbcode := "scale_in"

var duration := 0.18
var start_scale := 0.0
var font_size := 24          # set from the runner
var reveal_times := {}

func reset() -> void:
	reveal_times.clear()

func mark_revealed(index: int) -> void:
	reveal_times[index] = Time.get_ticks_msec()

func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	var idx := char_fx.relative_index
	if not reveal_times.has(idx):
		return true

	var elapsed: float = (Time.get_ticks_msec() - reveal_times[idx]) / 1000.0
	var t := clampf(elapsed / duration, 0.0, 1.0)
	var c1 := 1.70158
	var c3 := c1 + 1.0
	var eased := 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)
	var s := lerpf(start_scale, 1.0, eased)

	var ts := TextServerManager.get_primary_interface()
	var adv := ts.font_get_glyph_advance(char_fx.font, font_size, char_fx.glyph_index).x
	var pivot := Vector2(adv * 0.5, -font_size * 0.35)

	char_fx.transform = char_fx.transform \
		.translated_local(pivot) \
		.scaled_local(Vector2(s, s)) \
		.translated_local(-pivot)
	return true
