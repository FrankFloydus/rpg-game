shader_type spatial;

uniform sampler2D stone_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 stone_tint : source_color = vec4(1.0);
uniform float stone_repeats_per_metre = 0.0;
instance uniform float clue_strength = 0.0;
varying vec2 wall_plane;

void vertex() {
	vec3 point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 normal = abs(MODEL_NORMAL_MATRIX * NORMAL);
	// Match the side projections used by the surrounding cardinal masonry faces.
	wall_plane = vec2(normal.x > normal.z ? -point.z : point.x, -point.y);
}

float crack_x(float y) {
	float row = y * 21.0;
	float segment = floor(row);
	float left = fract(sin(segment * 38.719 + 0.6) * 9321.753);
	float right = fract(sin((segment + 1.0) * 38.719 + 0.6) * 9321.753);
	return 0.49 + 0.042 * sin(y * 5.0) + 0.021 * (mix(left, right, fract(row)) - 0.5);
}

float hairline(float distance, float width) {
	float edge = max(fwidth(distance), 0.0008);
	return 1.0 - smoothstep(width * 0.35, width + edge, abs(distance));
}

void fragment() {
	vec2 uv = UV;
	float center = uv.x - crack_x(uv.y);
	float taper = smoothstep(0.17, 0.28, uv.y) * (1.0 - smoothstep(0.73, 0.86, uv.y));
	float fissure = hairline(center, 0.0026) * taper;
	float side_end = smoothstep(0.42, 0.46, uv.y) * (1.0 - smoothstep(0.53, 0.54, uv.y));
	float branch = hairline(uv.x - crack_x(0.54) + (0.54 - uv.y) * 0.65, 0.0014) * side_end;
	float edge = hairline(center - 0.004, 0.0014) * taper;
	vec2 stone_uv = stone_repeats_per_metre > 0.0 ? wall_plane * stone_repeats_per_metre : uv;
	vec3 stone = texture(stone_albedo, stone_uv).rgb * stone_tint.rgb;
	ALBEDO = stone * (1.0 - 0.56 * max(fissure, branch * 0.77) + edge * 0.11);
	float traced_crack = max(hairline(center, 0.0048) * taper, branch * 0.64);
	EMISSION = vec3(0.89, 0.47, 0.24) * traced_crack * clue_strength * 1.4;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
