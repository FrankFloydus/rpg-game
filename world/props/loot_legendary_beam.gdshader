shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 beam_color : source_color = vec4(1.0, 0.45, 0.18, 1.0);

void vertex() {
	vec3 to_camera = INV_VIEW_MATRIX[3].xyz - MODEL_MATRIX[3].xyz;
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), vec3(to_camera.x, 0.0, to_camera.z) + vec3(0.0001, 0.0, 0.0)));
	vec3 point = MODEL_MATRIX[3].xyz + right * VERTEX.x + vec3(0.0, VERTEX.y, 0.0);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(point, 1.0);
}

void fragment() {
	float height = clamp(1.0 - UV.y, 0.0, 1.0);
	float edge = abs(UV.x * 2.0 - 1.0);
	float taper = mix(0.96, 0.31, height);
	float glow = pow(1.0 - smoothstep(0.0, taper, edge), 2.8);
	float core = pow(1.0 - smoothstep(0.0, taper * 0.31, edge), 2.0);
	float fade = pow(1.0 - height, 1.4) * smoothstep(0.0, 0.043, height);
	float moving_light = 0.88 + sin(height * 18.0 - TIME * 3.4) * 0.12;
	ALBEDO = mix(beam_color.rgb, vec3(1.0, 0.79, 0.52), core) * 1.42;
	ALPHA = (glow * 0.27 + core * 0.66) * fade * moving_light;
}
