shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

instance uniform vec4 tint : source_color = vec4(1.0, 0.55, 0.26, 1.0);
instance uniform float age = 0.0;

void fragment() {
	vec2 point = UV * 2.0 - 1.0;
	float wave = 1.0 - pow(max(0.0, 1.0 - age), 2.2);
	float angle = atan(point.y, point.x + 0.00001);
	float roughness = sin(angle * 8.0 - age * 8.0 + sin(angle * 5.0)) * 0.015;
	roughness += sin(angle * 23.0 + age * 2.0) * 0.008;
	float radial = length(point) + roughness;
	float edge_gap = abs(radial - wave);
	float edge = 1.0 - smoothstep(0.009, 0.048, edge_gap);
	float vapor = 1.0 - smoothstep(0.045, 0.17, edge_gap);
	float tail = (1.0 - smoothstep(0.018, 0.048, abs(radial - wave * 0.73)))
		* (0.48 + 0.46 * sin(angle * 14.0 + sin(angle * 3.0)));
	float heave = smoothstep(0.04, 0.20, wave) * (1.0 - smoothstep(0.57, 1.0, age));
	ALBEDO = mix(tint.rgb * 0.71, mix(tint.rgb, vec3(1.0, 0.87, 0.68), 0.23), edge);
	ALPHA = (edge * 0.61 + vapor * 0.14 + tail * 0.17) * heave;
}
