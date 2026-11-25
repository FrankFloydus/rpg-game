shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, shadows_disabled, depth_draw_never;

uniform int motif = 0;
uniform float glow = 0.0;

varying vec4 particle_tint;

void vertex() {
	particle_tint = COLOR;
	vec2 billboard = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	MODELVIEW_MATRIX = mat4(vec4(billboard.x, 0.0, 0.0, 0.0),
		vec4(0.0, billboard.y, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), MODELVIEW_MATRIX[3]);
	float spin = INSTANCE_CUSTOM.x;
	float s = sin(spin);
	float c = cos(spin);
	VERTEX.xy = mat2(vec2(c, s), vec2(-s, c)) * VERTEX.xy;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float opacity = 1.0 - smoothstep(0.3, 1.0, r);
	if (motif == 0) {
		vec2 drop = vec2(p.x * (1.5 - p.y * 0.48), p.y + 0.12);
		opacity = 1.0 - smoothstep(0.55, 0.96, length(drop));
	} else if (motif == 1) {
		float core = length(p * vec2(1.0, 1.2));
		float cross_shape = min(abs(p.x), abs(p.y)) + max(abs(p.x), abs(p.y)) * 0.16;
		opacity = max(1.0 - smoothstep(0.12, 0.46, core),
			(1.0 - smoothstep(0.07, 0.20, cross_shape)) * (1.0 - smoothstep(0.42, 0.96, r)));
	} else if (motif == 2) {
		float billow = 0.10 * sin(p.x * 9.1 + p.y * 6.0) + 0.08 * sin(p.y * 13.2 - p.x * 5.0);
		opacity = (1.0 - smoothstep(0.12, 0.93, r + billow)) * 0.64;
	} else if (motif == 3) {
		float line = abs(p.x + abs(p.y + 0.12) * 0.6 - 0.29) + 0.08 * sin(p.y * 11.0);
		opacity = (1.0 - smoothstep(0.08, 0.20, line)) * (1.0 - smoothstep(0.52, 0.99, abs(p.y)));
	} else {
		opacity = (1.0 - smoothstep(0.025, 0.15, abs(p.x))) * (1.0 - smoothstep(0.35, 0.99, abs(p.y)));
	}
	ALBEDO = particle_tint.rgb;
	EMISSION = particle_tint.rgb * glow * opacity;
	ALPHA = particle_tint.a * opacity;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
