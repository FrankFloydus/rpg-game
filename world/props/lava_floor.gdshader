shader_type spatial;
render_mode cull_back, specular_disabled;

uniform sampler2D crust_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D crust_normal : hint_normal, filter_linear_mipmap, repeat_enable;
instance uniform vec2 surface_size = vec2(1.0);
instance uniform float heat = 0.0;

vec2 hash2(vec2 cell) {
	vec2 projected = vec2(dot(cell, vec2(123.43, 311.71)), dot(cell, vec2(47.19, 191.57)));
	return fract(sin(projected) * 43758.5453);
}

float cracks(vec2 point) {
	vec2 cell = floor(point);
	vec2 local = fract(point);
	float first = 4.0;
	float second = 4.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 delta = offset + hash2(cell + offset) * 0.73 - local + 0.135;
			float distance_squared = dot(delta, delta);
			second = min(second, max(first, distance_squared));
			first = min(first, distance_squared);
		}
	}
	return sqrt(second) - sqrt(first);
}

void fragment() {
	vec2 point = (UV - 0.5) * surface_size;
	vec2 roughness_uv = point * 0.78;
	vec3 stone = texture(crust_texture, roughness_uv).rgb;
	float grain = stone.r;
	float fine_grain = texture(crust_texture, point * 2.10 + 0.3).r;
	vec2 wave = vec2(sin(point.y * 5.3 + TIME * 0.43), sin(point.x * 4.9 - TIME * 0.37));
	vec2 irregularity = vec2(grain - 0.24, fine_grain - 0.24) * 0.52;
	vec2 field = point * vec2(1.36, 1.63) + irregularity + wave * (0.075 + heat * 0.13);
	float fracture = cracks(field);
	float expansion = smoothstep(0.21, 0.93, heat);
	float channel = 1.0 - smoothstep(0.018, 0.11 + expansion * (0.27 + fine_grain * 0.16), fracture + grain * 0.08);
	float bank = 1.0 - smoothstep(0.07, 0.53, fracture + fine_grain * 0.18);
	float pulse = 0.53 + 0.47 * sin(TIME * 0.95 + point.x * 1.94 + point.y * 0.87 + grain * 4.2);
	float streak = 0.5 + 0.5 * sin(point.x * 35.0 + point.y * 23.0 + TIME * 1.3 + grain * 13.0);
	float margin = min(min(UV.x, UV.y), min(1.0 - UV.x, 1.0 - UV.y));
	float molten = heat * smoothstep(0.004, 0.030, margin);
	vec3 charred = stone * vec3(0.58, 0.53, 0.48) * (0.63 + 0.49 * fine_grain);
	charred *= mix(0.45, 1.0, smoothstep(0.01, 0.19, fracture));
	vec3 cooled_glass = vec3(0.19, 0.028, 0.011) * (0.45 + bank * 0.55);
	vec3 lava = mix(vec3(0.40, 0.054, 0.009), vec3(0.91, 0.29, 0.044),
		clamp(pulse * 0.68 + streak * 0.17 + grain * 0.37, 0.0, 1.0));
	ALBEDO = mix(charred, lava, channel * molten * 0.76);
	EMISSION = (cooled_glass * (0.24 + bank * 0.80) * expansion
		+ lava * channel * (0.30 + 1.22 * expansion)) * molten;
	NORMAL_MAP = texture(crust_normal, roughness_uv).rgb;
	NORMAL_MAP_DEPTH = 0.78 * (1.0 - channel * molten * 0.55);
	ROUGHNESS = 1.0;
}
