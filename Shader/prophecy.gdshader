shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;

group_uniforms Texture;
	// Assign the same texture as the Sprite3D. Must NOT repeat.
	uniform sampler2D Sprite_Texture : source_color, filter_nearest, repeat_disable;
	// The scrolling pattern SHOULD repeat.
	uniform sampler2D Scroll_Texture : source_color, filter_nearest, repeat_enable;
	uniform bool Use_Original_Texture = false;
	uniform float Pixel_Size = 0.01; // match Sprite3D.pixel_size
	// Only change for sprite sheets (hframes/vframes/region): x, y, width, height in 0-1 UV space.
	// Example for a 4x1 sheet showing frame 2: vec4(0.5, 0.0, 0.25, 1.0)
	uniform vec4 Frame_Rect = vec4(0.0, 0.0, 1.0, 1.0);
group_uniforms;

group_uniforms Scrolling_Settings;
	uniform vec2 Scrolling_Speed = vec2(-1, -1);
	uniform float Time_Scale = 0.1;
	uniform float Texture_Scale = 1.0;
group_uniforms;

group_uniforms Bobbing_Settings;
	uniform float Height : hint_range(0, 16, 1) = 8;
	uniform float Cycles = 0.4;
	uniform float Offset = 0.0;
group_uniforms;

group_uniforms Echoes_Settings;
	uniform float Distance : hint_range(0, 128, 0.1) = 35.0;
	uniform int Count : hint_range(0, 8, 1) = 2;
	uniform float Fade : hint_range(0.0, 1.0, 0.01) = 0.25;
	uniform float Start_Alpha : hint_range(0.0, 1.0, 0.01) = 0.8;
	uniform float Tint_Amount : hint_range(0.0, 1.0, 0.01) = 0.5;
	uniform vec4 Tint : source_color = vec4(1.0);
	uniform bool Pulse_both_Directions = false;
	uniform float Diagonal_Angle : hint_range(0, 90, 15) = 45.0;
	uniform int Echo_Blend_Mode : hint_enum("Mix","Additive") = 0;
group_uniforms;

varying float vertex_scale;

// local_uv is 0-1 across the sprite frame. Anything outside that range is transparent,
// so the enlarged quad never shows tiled or smeared copies.
vec4 SampleSprite(sampler2D tex, vec2 local_uv) {
	vec2 atlas_uv = local_uv * Frame_Rect.zw + Frame_Rect.xy;
	vec4 c = texture(tex, atlas_uv);
	vec2 inside = step(vec2(0.0), local_uv) * step(local_uv, vec2(1.0));
	c.a *= inside.x * inside.y;
	return c;
}

vec4 RenderEchoes(
	vec2 BaseUV, vec2 sScrollUVColor, sampler2D MainTex, sampler2D ScrollTex,
	vec2 TexelSize, bool UseMainTex, float BobOSC, float EchoDistPx, int EchoCount,
	float EchoFade, float EchoStartAlpha, float EchoTintAmount, vec4 EchoTint,
	bool Pulse2Direction, float EchoAngle, int EchoBlendMode
) {
	vec4 AccumEchoCol = vec4(0.0);
	float AngleRadians = radians(EchoAngle);
	vec2 BaseDirVector = vec2(cos(AngleRadians), sin(AngleRadians));
	float decay_factor = 1.0 - EchoFade;
	float inv_echo_count = 1.0 / max(1.0, float(EchoCount));

	vec3 pre_sampled_scrolling_rgb = vec3(0.0);
	if (!UseMainTex) {
		pre_sampled_scrolling_rgb = texture(ScrollTex, sScrollUVColor).rgb;
	}

	for (int i = 1; i <= EchoCount; ++i) {
		float CurrentEchoAlpha = EchoStartAlpha * pow(decay_factor, float(i - 1));
		if (CurrentEchoAlpha <= 0.0) break;

		float i_norm = float(i) * inv_echo_count;
		vec3 progressive_rgb_tint = mix(vec3(1.0), EchoTint.rgb, i_norm * EchoTintAmount);
		float OffsetMagnitUV = BobOSC * EchoDistPx * float(i) * TexelSize.x;

		for (int j = 0; j < (Pulse2Direction ? 2 : 1); ++j) {
			vec2 CurrentDispUV = BaseDirVector * ((j == 0) ? OffsetMagnitUV : -OffsetMagnitUV);
			vec2 DispUVOGShape = BaseUV - CurrentDispUV;

			vec4 CurrentEchoColor;
			if (UseMainTex) {
				CurrentEchoColor = SampleSprite(MainTex, DispUVOGShape);
			} else {
				CurrentEchoColor = vec4(pre_sampled_scrolling_rgb, SampleSprite(MainTex, DispUVOGShape).a);
			}

			CurrentEchoColor.rgb *= progressive_rgb_tint;
			CurrentEchoColor.a *= (EchoTint.a * CurrentEchoAlpha);

			if (EchoBlendMode == 0) {
				AccumEchoCol = mix(AccumEchoCol, CurrentEchoColor, CurrentEchoColor.a);
			} else {
				AccumEchoCol.rgb += CurrentEchoColor.rgb * CurrentEchoColor.a;
				AccumEchoCol.a = min(1.0, AccumEchoCol.a + CurrentEchoColor.a);
			}
		}
	}
	return AccumEchoCol;
}

vec2 ScrollingUV(vec2 sUV, vec2 sPX, float time) {
	vec2 T = Scrolling_Speed * time * Time_Scale;
	vec2 ScreenPixelSize = vec2(1.0) / sPX;
	vec2 TexturePixelSize = vec2(textureSize(Scroll_Texture, 0));
	vec2 repeats = ScreenPixelSize / TexturePixelSize;
	return (sUV * repeats + T) / Texture_Scale;
}

float CalculateExpansion() {
	// Width of the current frame in pixels (works for atlases and varying frame sizes).
	float frame_width_px = max(1.0, float(textureSize(Sprite_Texture, 0).x) * Frame_Rect.z);
	float max_echo_distance = Distance * float(Count);
	float distance_ratio = max_echo_distance / frame_width_px;
	return max(1.0, (1.0 + distance_ratio * 2.0) * 1.2);
}

void vertex() {
	vertex_scale = CalculateExpansion();
	VERTEX.xy *= vertex_scale;
	// 3D y is up (canvas y is down), so subtract. Convert px -> world units.
	VERTEX.y -= sin(TAU * Cycles * TIME + Offset) * Height * Pixel_Size;
}

void fragment() {
	// Frame-local UV (0-1 across the visible frame), expanded around its center.
	vec2 local_uv = (UV - Frame_Rect.xy) / Frame_Rect.zw;
	vec2 adjusted_UV = (local_uv - 0.5) * vertex_scale + 0.5;

	vec2 screen_pixel_size = 1.0 / VIEWPORT_SIZE;
	vec2 ScreenScrollingUV = ScrollingUV(SCREEN_UV, screen_pixel_size, TIME);

	// Echo distance is in sprite pixels, expressed in frame-local UV units.
	vec2 texel = 1.0 / (vec2(textureSize(Sprite_Texture, 0)) * Frame_Rect.zw);

	vec4 tex1 = SampleSprite(Sprite_Texture, adjusted_UV);
	vec3 tex2_scrolling_rgb = texture(Scroll_Texture, ScreenScrollingUV).rgb;
	float BobOSC = sin(TAU * Cycles * TIME + Offset);

	vec4 AccumEchoCol = RenderEchoes(
		adjusted_UV, ScreenScrollingUV, Sprite_Texture, Scroll_Texture, texel,
		Use_Original_Texture, BobOSC, Distance, Count, Fade, Start_Alpha,
		Tint_Amount, Tint, Pulse_both_Directions, Diagonal_Angle, Echo_Blend_Mode
	);

	vec4 MainInstCol = Use_Original_Texture
		? tex1
		: vec4(tex2_scrolling_rgb * tex1.a, tex1.a);

	vec4 result = mix(AccumEchoCol, MainInstCol, MainInstCol.a);
	ALBEDO = result.rgb;
	ALPHA = result.a;
}
