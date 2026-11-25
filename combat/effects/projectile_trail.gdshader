shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

instance uniform int element = 0;
varying flat float particle_age;
varying flat float strand;

void vertex() {
	particle_age = INSTANCE_CUSTOM.y;
	strand = INSTANCE_CUSTOM.z;
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
	vec2 p = (UV - 0.5) * 2.0;
	float body = 1.0 - smoothstep(0.07, 0.97, length(p));
	float life = (1.0 - smoothstep(0.11, 0.95, particle_age));
	float opacity = body * body * life;
	vec3 pigment = COLOR.rgb;
	if (element == 1) {
		pigment = mix(vec3(0.29, 0.043, 0.021), vec3(1.1, 0.43, 0.11), life);
	} else if (element == 2) {
		opacity *= 0.72 + sin(p.x * 3.8 - p.y * 4.1 + strand * TAU) * 0.26;
		pigment *= 0.88 + 0.32 * body;
	} else if (element == 3) {
		float branch = abs(p.x - sin(p.y * 5.4 + strand * TAU) * 0.24);
		opacity *= 0.37 + (1.0 - smoothstep(0.05, 0.38, branch)) * 0.61;
		pigment = mix(pigment, vec3(0.73, 0.61, 1.16), body * 0.64);
	} else if (element == 4) {
		pigment *= 0.41 + 0.45 * life;
		opacity = body * life * (0.68 + 0.26 * sin((p.x + p.y) * 4.0 + strand * TAU));
	}
	ALBEDO = pigment;
	ALPHA = opacity * COLOR.a * 0.67;
}
