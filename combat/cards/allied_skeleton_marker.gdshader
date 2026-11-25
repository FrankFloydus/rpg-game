shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, shadows_disabled, cull_disabled;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = abs(length(p) - 0.81);
	float ring = 1.0 - smoothstep(0.007, 0.034, d);
	float soft_edge = 1.0 - smoothstep(0.035, 0.10, d);
	float fade = 0.56 + 0.07 * sin(TIME * 1.75);
	ALBEDO = vec3(0.91, 0.74, 0.48);
	ALPHA = (ring * 0.65 + soft_edge * 0.20) * fade;
}
