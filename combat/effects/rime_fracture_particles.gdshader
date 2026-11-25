shader_type particles;
render_mode disable_force, disable_velocity;

uniform float radius = 2.6;

float random_value(float index, float offset) {
	return fract(sin(index * 127.1 + offset * 311.7) * 43758.5453);
}

void start() {
	float seed = float(INDEX) + float(RANDOM_SEED % uint(3011));
	CUSTOM = vec4(0.0, random_value(seed, 1.0), random_value(seed, 2.0), random_value(seed, 3.0));
	COLOR = vec4(0.39, 0.70, 0.86, 0.0);
}

void process() {
	CUSTOM.x = min(1.0, CUSTOM.x + DELTA / LIFETIME);
	float age = CUSTOM.x;
	float angle = TAU * (float(INDEX) * 0.618034 + CUSTOM.y * 0.06);
	vec3 outward = vec3(cos(angle), 0.0, sin(angle));
	float travel = radius * mix(0.44, 1.0, CUSTOM.z) * (1.0 - pow(1.0 - age, 2.6));
	float height = mix(0.29, 0.86, CUSTOM.w) * 4.0 * age * (1.0 - age);
	vec3 up = normalize(outward * mix(0.60, 1.12, CUSTOM.z) + vec3(0.0, 0.95 - age * 1.5, 0.0));
	vec3 right = normalize(cross(up, vec3(0.0, 1.0, 0.0)));
	vec3 front = cross(right, up);
	float size = mix(0.70, 1.28, CUSTOM.y) * (1.0 - age * 0.43);
	TRANSFORM = mat4(vec4(right * size, 0.0), vec4(up * size, 0.0),
		vec4(front * size, 0.0), vec4(outward * travel + vec3(0.0, height, 0.0), 1.0));
	COLOR.a = smoothstep(0.0, 0.08, age) * (1.0 - smoothstep(0.42, 1.0, age));
}
