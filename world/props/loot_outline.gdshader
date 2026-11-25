shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform vec4 edge_color : source_color = vec4(1.0, 0.73, 0.37, 1.0);
uniform float edge_width = 0.009;

void vertex() {
	vec4 point = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	point.xyz += normalize(MODELVIEW_NORMAL_MATRIX * NORMAL) * edge_width;
	POSITION = PROJECTION_MATRIX * point;
}

void fragment() {
	ALBEDO = edge_color.rgb;
}
