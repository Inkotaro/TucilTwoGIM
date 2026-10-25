shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0, 0.05) = 0.01;
uniform bool edge_falloff = true;
uniform float distortion_amount : hint_range(-1, 1) = -.08;

void fragment() {
	vec2 p = SCREEN_UV - vec2(0.5);
	float r2 = dot(p, p);
	vec2 distorted_uv = p * (1.0 + distortion_amount * r2);
	vec2 final_uv = distorted_uv + vec2(0.5);
	vec2 direction = final_uv - vec2(0.5);
	float dist = length(direction);
	vec2 radial_offset = normalize(direction);
	float intensity = edge_falloff ? dist : 1.0;
	vec2 offset = radial_offset * strength * intensity;
	float r = texture(SCREEN_TEXTURE, final_uv + offset).r;
	float g = texture(SCREEN_TEXTURE, final_uv).g;
	float b = texture(SCREEN_TEXTURE, final_uv - offset).b;
	float a = texture(SCREEN_TEXTURE, final_uv).a;   
	COLOR = vec4(r, g, b, a);
}