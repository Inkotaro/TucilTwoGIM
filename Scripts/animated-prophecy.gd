@tool
extends AnimatedSprite3D

var _last_key := ""

func _process(_delta: float) -> void:
	_sync_shader()

func _sync_shader() -> void:
	var mat := material_override as ShaderMaterial
	if mat == null or sprite_frames == null:
		return
	if not sprite_frames.has_animation(animation):
		return

	var key := "%s:%d" % [animation, frame]
	if key == _last_key:
		return
	_last_key = key

	var tex: Texture2D = sprite_frames.get_frame_texture(animation, frame)
	if tex == null:
		return

	var full_tex: Texture2D = tex
	var rect := Vector4(0.0, 0.0, 1.0, 1.0)

	var atlas_tex := tex as AtlasTexture
	if atlas_tex != null and atlas_tex.atlas != null:
		full_tex = atlas_tex.atlas
		var atlas_size := Vector2(full_tex.get_size())
		var r := atlas_tex.region
		rect = Vector4(
			r.position.x / atlas_size.x, r.position.y / atlas_size.y,
			r.size.x / atlas_size.x, r.size.y / atlas_size.y
		)

	mat.set_shader_parameter("Sprite_Texture", full_tex)
	mat.set_shader_parameter("Frame_Rect", rect)
	mat.set_shader_parameter("Pixel_Size", pixel_size)
