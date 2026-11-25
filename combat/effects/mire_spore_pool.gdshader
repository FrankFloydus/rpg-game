shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

instance uniform float pool_density : hint_range(0.0, 1.0) = 1.0;

float grain(vec2 point) {
	return fract(sin(dot(point, vec2(29.3, 73.1))) * 43758.5453);
}

void fragment() {
	vec2 point = UV * 2.0 - 1.0;
	float radius = length(point);
	float angle = atan(point.y, point.x);
	float edge = 0.952 + sin(angle * 9.0 + 0.7) * 0.021 + sin(angle * 17.0) * 0.013;
	float outline = smoothstep(edge - 0.05, edge - 0.018, radius) * (1.0 - smoothstep(edge, 1.0, radius));
	float stain = 1.0 - smoothstep(edge - 0.19, edge + 0.025, radius);
	float tide = 0.5 + 0.5 * sin(radius * 19.0 + sin(angle * 7.0 + TIME) * 0.7 - TIME * 2.6);
	float flecks = grain(floor(point * 95.0));
	vec3 sediment = vec3(0.063, 0.089, 0.025);
	vec3 active = vec3(0.34, 0.39, 0.09);
	ALBEDO = mix(sediment, active, clamp(outline * 0.87 + tide * tide * 0.27 + flecks * 0.18, 0.0, 1.0));
	ALPHA = (stain * (0.33 + tide * 0.14) + outline * 0.48) * pool_density;
}
