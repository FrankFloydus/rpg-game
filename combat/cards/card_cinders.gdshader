shader_type particles;
render_mode disable_force, disable_velocity;

uniform vec4 pigment : source_color = vec4(1.0, 0.60, 0.32, 1.0);

void start() {
	vec2 part = vec2(float(INDEX), float(RANDOM_SEED % uint(65536)));
	CUSTOM = vec4(0.0, 0.0, fract(sin(dot(part, vec2(12.9898, 78.233))) * 43758.5453),
		fract(sin(dot(part, vec2(52.19, 19.37))) * 6394.312));
	COLOR = vec4(pigment.rgb, 0.0);
}

void process() {
	CUSTOM.y = min(1.0, CUSTOM.y + DELTA / LIFETIME);
	float age = CUSTOM.y;
	float variation = CUSTOM.z;
	float angle = (float(INDEX) * 0.618034 + variation * 0.055) * TAU + 0.22 * age;
	float radius = (1.0 - pow(1.0 - age, 2.2)) * mix(0.74, 0.99, CUSTOM.w);
	float rise = sin(PI * age) * mix(0.11, 0.37, variation);
	float size = mix(0.64, 1.23, variation) * (1.0 - age * 0.39);
	TRANSFORM = mat4(vec4(size, 0.0, 0.0, 0.0), vec4(0.0, size, 0.0, 0.0),
		vec4(0.0, 0.0, size, 0.0), vec4(cos(angle) * radius, rise, sin(angle) * radius, 1.0));
	COLOR = vec4(pigment.rgb, smoothstep(0.0, 0.095, age) * (1.0 - smoothstep(0.56, 1.0, age)));
}
