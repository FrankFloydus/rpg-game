shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

void vertex() {
	vec3 up = MODELVIEW_MATRIX[1].xyz;
	vec2 height_axis = up.xy;
	if (dot(height_axis, height_axis) < 0.0001) {
		height_axis = vec2(0.0, 1.0);
	}
	height_axis = normalize(height_axis);
	vec2 width_axis = vec2(height_axis.y, -height_axis.x);
	MODELVIEW_MATRIX = mat4(vec4(width_axis * length(MODELVIEW_MATRIX[0].xyz), 0.0, 0.0),
		vec4(height_axis * length(up), 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), MODELVIEW_MATRIX[3]);
}

void fragment() {
	float centered = abs(UV.x * 2.0 - 1.0);
	float width = max(0.0, 1.0 - abs((UV.y - 0.66) / (UV.y > 0.66 ? 0.34 : 0.66)));
	float edge = (1.0 - smoothstep(width - 0.08, width, centered));
	float facet = smoothstep(0.12, 0.60, UV.x + UV.y * 0.21);
	ALBEDO = mix(COLOR.rgb * 0.52, vec3(0.42, 0.57, 0.70), facet);
	ALPHA = edge * COLOR.a * mix(0.43, 0.70, facet);
}
