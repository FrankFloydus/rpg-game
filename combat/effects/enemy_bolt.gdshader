shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

instance uniform vec4 bolt_tint : source_color = vec4(0.64, 0.58, 0.83, 1.0);
instance uniform int element = 0;

varying vec3 shape_position;

float hash_point(vec3 value) {
	value = fract(value * 0.3183099 + vec3(0.11, 0.37, 0.79));
	value *= 17.0;
	return fract(value.x * value.y * value.z * (value.x + value.y + value.z));
}

float drift(vec3 point) {
	vec3 cell = floor(point);
	vec3 fraction = fract(point);
	fraction = fraction * fraction * (3.0 - 2.0 * fraction);
	float lower = mix(mix(hash_point(cell), hash_point(cell + vec3(1.0, 0.0, 0.0)), fraction.x),
		mix(hash_point(cell + vec3(0.0, 1.0, 0.0)), hash_point(cell + vec3(1.0, 1.0, 0.0)), fraction.x), fraction.y);
	float upper = mix(mix(hash_point(cell + vec3(0.0, 0.0, 1.0)), hash_point(cell + vec3(1.0, 0.0, 1.0)), fraction.x),
		mix(hash_point(cell + vec3(0.0, 1.0, 1.0)), hash_point(cell + vec3(1.0, 1.0, 1.0)), fraction.x), fraction.y);
	return mix(lower, upper, fraction.z);
}

void vertex() {
	shape_position = VERTEX;
}

void fragment() {
	float face = abs(dot(normalize(NORMAL), VIEW));
	float spine = pow(face, 2.4);
	float nose = 1.0 - smoothstep(-0.30, 0.50, shape_position.z);
	vec3 stream = shape_position * vec3(5.7, 8.8, 13.0) + vec3(0.0, 0.0, -TIME * 5.2);
	float swirl = drift(stream) * 0.73 + drift(stream * 1.8) * 0.27;
	float coverage = smoothstep(0.15, 0.76, swirl + spine * 0.32);
	float bright = spine * nose;
	vec3 pigment = bolt_tint.rgb;
	if (element == 1) {
		pigment = mix(bolt_tint.rgb * vec3(0.80, 0.37, 0.27), vec3(1.42, 0.81, 0.33), bright * 0.76);
	} else if (element == 2) {
		float vein = sin((shape_position.x - shape_position.y) * 26.0 + shape_position.z * 22.0);
		coverage *= 0.65 + 0.35 * smoothstep(-0.30, 0.83, vein);
		pigment = mix(bolt_tint.rgb, vec3(0.63, 1.07, 1.19), bright * 0.51);
	} else if (element == 3) {
		float turn = atan(shape_position.y, shape_position.x + 0.0001);
		float filament = sin(turn * 2.0 + shape_position.z * 15.3 + TIME * 6.7 + swirl * 2.0);
		coverage = max(coverage * 0.45, smoothstep(0.62, 0.99, filament));
		pigment = mix(bolt_tint.rgb, vec3(1.10, 0.94, 1.23), bright * 0.65);
	} else if (element == 4) {
		pigment = bolt_tint.rgb * (0.67 + swirl * 0.52);
		bright *= 0.53;
	}
	ALBEDO = pigment * (0.47 + bright * 0.73);
	ALPHA = nose * (0.10 + bright * 0.69) * coverage;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
