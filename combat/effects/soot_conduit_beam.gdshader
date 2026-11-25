shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color;
uniform float lurch = 0.0;
uniform float streakness = 0.0;

void vertex() {
	float along = (VERTEX.y + 1.0) * 0.5;
	float strength = sin(along * 3.14159265);
	float pulse = TIME * 24.0 + along * 34.0;
	vec2 jitter = vec2(sin(pulse) * sin(pulse * 0.31), cos(pulse * 1.18));
	VERTEX.xz += jitter * (strength * lurch);
}

void fragment() {
	float pulse = sin(UV.y * 96.0 - TIME * 41.0 + sin(TIME * 13.0) * 2.1);
	float branching = sin(UV.x * 18.8496 + UV.y * 23.0 - TIME * 5.0 + pulse);
	float flicker = max(smoothstep(0.35, 1.0, branching) * 0.81, (0.22 + 0.22 * pulse));
	float facing = pow(abs(dot(normalize(NORMAL), VIEW)), 1.7);
	float end_fade = smoothstep(0.0, 0.027, UV.y) * (1.0 - smoothstep(0.96, 1.0, UV.y));
	ALBEDO = tint.rgb * (0.84 + 0.23 * pulse);
	ALPHA = tint.a * end_fade * facing * mix(0.85, flicker, streakness);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
