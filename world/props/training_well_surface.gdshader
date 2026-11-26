shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 liquid_tint : source_color = vec4(1.0, 0.65, 0.53, 1.0);

void fragment() {
	vec2 point = UV * 2.0 - 1.0;
	float radius = length(point);
	if (radius > 1.0) {
		discard;
	}
	float waves = sin(radius * 25.0 - TIME * 2.4 + point.x * point.y * 3.0);
	float rings = pow(waves * 0.5 + 0.5, 3.0);
	float rim = smoothstep(0.76, 0.94, radius);
	ALBEDO = liquid_tint.rgb * (0.25 + 0.38 * rings + 0.19 * rim);
}
