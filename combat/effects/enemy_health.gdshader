shader_type spatial;
render_mode unshaded, cull_disabled;

instance uniform float health_fraction = 1.0;
instance uniform vec4 bar_color : source_color = vec4(0.67, 0.18, 0.17, 1.0);

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 rim = vec2(0.022, 0.16);
	bool inner = all(greaterThan(UV, rim)) && all(lessThan(UV, 1.0 - rim));
	float normalized = (UV.x - rim.x) / (1.0 - 2.0 * rim.x);
	vec3 paint = vec3(0.004, 0.005, 0.006);
	if (inner && normalized <= health_fraction) {
		paint = bar_color.rgb * mix(1.1, 0.8, UV.y);
	} else if (!inner) {
		paint = vec3(0.14, 0.16, 0.18);
	}
	ALBEDO = paint;
}
