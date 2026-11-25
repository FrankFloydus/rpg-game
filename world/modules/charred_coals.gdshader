shader_type spatial;

uniform sampler2D charcoal_grain : source_color, hint_default_white, filter_linear_mipmap, repeat_disable;

varying vec3 world_point;

float grain_hash(vec2 cell) {
	vec3 seed = fract(vec3(cell.xyx) * 0.1031);
	seed += dot(seed, seed.yzx + 31.32);
	return fract((seed.x + seed.y) * seed.z);
}

float grain(vec2 point) {
	vec2 cell = floor(point);
	vec2 blend = smoothstep(0.0, 1.0, fract(point));
	return mix(mix(grain_hash(cell), grain_hash(cell + vec2(1.0, 0.0)), blend.x),
		mix(grain_hash(cell + vec2(0.0, 1.0)), grain_hash(cell + 1.0), blend.x), blend.y);
}

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 mark = world_point.xz + world_point.y * vec2(0.57, -0.32);
	float coarse = grain(mark * 43.0);
	float fine = grain(mark * 184.0);
	float seams = abs(fract(mark.x * 18.0 + grain(mark * 29.0) * 1.55) - 0.5);
	float heat = (1.0 - smoothstep(0.008, 0.10, seams)) * smoothstep(0.32, 0.77, coarse);
	float exposed_heat = smoothstep(0.88, 0.99, coarse * 0.72 + fine * 0.28);
	float breath = 0.76 + 0.24 * sin(TIME * 2.1 + coarse * 21.0);
	vec2 grain_uv = vec2(0.514, 0.014) + fract(mark * 3.5) * 0.472;
	float mapped_grain = texture(charcoal_grain, grain_uv).r;
	ALBEDO = mix(vec3(0.019, 0.014, 0.013), vec3(0.12, 0.095, 0.079), fine * coarse);
	ALBEDO *= 0.76 + 0.24 * mapped_grain;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = vec3(0.80, 0.096, 0.016) * (heat * breath + exposed_heat * 0.28);
}
