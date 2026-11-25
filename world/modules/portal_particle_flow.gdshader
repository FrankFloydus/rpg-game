shader_type particles;
render_mode disable_force, disable_velocity;

uniform bool sparks = false;
uniform bool mist = false;

float hash_particle(uint key) {
	key = (key ^ (key >> uint(16))) * uint(2246822519);
	key = (key ^ (key >> uint(13))) * uint(3266489917);
	return float(key & uint(65535)) / 65535.0;
}

void start() {
	uint seed = RANDOM_SEED + NUMBER * uint(104729) + INDEX * uint(8191);
	CUSTOM = vec4(0.0, hash_particle(seed), hash_particle(seed + uint(9283)),
		hash_particle(seed + uint(37853)));
	COLOR = vec4(1.0, 1.0, 1.0, 0.0);
	VELOCITY = vec3(0.0);
}

void process() {
	CUSTOM.x = min(CUSTOM.x + DELTA / LIFETIME, 1.0);
	float phase = CUSTOM.x;
	float spread = CUSTOM.z;
	float age = CUSTOM.w;
	// Spread births around the whole rim before adding random angular drift.
	float direction = fract(float(INDEX) * 0.618034 + CUSTOM.y * 0.13) * TAU;
	float fade = smoothstep(0.0, 0.16, phase) * (1.0 - smoothstep(0.55, 1.0, phase));
	float radius = 0.0;
	float depth = 0.0;
	float horizontal = 0.0;
	float vertical = 0.0;
	if (mist) {
		direction -= phase * mix(0.66, 1.40, age);
		radius = mix(0.80 + spread * 0.17, 0.42 + spread * 0.36, phase);
		depth = mix(-0.015, 0.21, age) + sin(phase * PI) * 0.29;
		horizontal = mix(0.40, 0.65, age);
		vertical = mix(0.14, 0.28, spread);
	} else if (sparks) {
		direction -= phase * mix(0.58, 1.46, age);
		radius = mix(0.67 + spread * 0.31, 0.92 + spread * 0.24, phase);
		depth = mix(-0.21, 0.24, age) + phase * 0.23;
		horizontal = mix(0.021, 0.051, spread);
		vertical = horizontal;
	} else {
		direction -= phase * mix(1.35, 2.58, age);
		radius = mix(0.93 + spread * 0.07, 0.34 + spread * 0.31, phase);
		depth = mix(-0.14, 0.15, spread) + sin(phase * PI) * 0.11;
		horizontal = mix(0.25, 0.50, age) * (0.82 + phase * 0.38);
		vertical = mix(0.059, 0.107, spread);
	}
	vec2 radial = vec2(cos(direction), sin(direction));
	vec2 tangent = vec2(-radial.y, radial.x);
	vec2 position = radial * radius;
	if (sparks) {
		position.y += phase * 0.13;
	}
	TRANSFORM = mat4(vec4(tangent * horizontal, 0.0, 0.0),
		vec4(-radial * vertical, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0),
		vec4(position, depth, 1.0));
	COLOR = vec4(1.0, 1.0, 1.0, fade);
}

