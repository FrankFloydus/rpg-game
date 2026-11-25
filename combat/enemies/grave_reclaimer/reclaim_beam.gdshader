shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled;

instance uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float fringe = pow(abs(dot(NORMAL, VIEW)), 1.2);
	float longitudinal = smoothstep(0.0, 0.12, UV.y) * smoothstep(0.0, 0.12, 1.0 - UV.y);
	float strand = sin(UV.y * 29.0 + UV.x * 12.566 - TIME * 6.0);
	float ripple = 0.4 + smoothstep(-0.43, 0.9, strand) * 0.6;
	ALBEDO = vec3(0.29, 0.80, 0.62) * (0.6 + progress * 0.4);
	ALPHA = fringe * longitudinal * ripple * (0.36 + 0.13 * progress);
}
