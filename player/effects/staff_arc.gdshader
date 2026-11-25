shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform bool haze = false;
instance uniform vec4 arc_tint : source_color = vec4(0.62, 0.84, 0.81, 1.0);
instance uniform float age = 0.0;
varying float span;

void vertex() {
	span = VERTEX.y + 0.5;
	float ends = sin(span * PI);
	float speed = TIME * 18.0;
	float bend = sin(span * TAU * 2.4 - speed) + sin(span * TAU * 6.2 + speed * 0.58) * 0.32;
	float lift = sin(span * TAU * 3.1 + speed * 0.73);
	VERTEX.x += ends * bend * 0.031;
	VERTEX.z += ends * lift * 0.026;
	float thickness = (0.94 - 0.48 * age) * (0.72 + 0.28 * ends);
	VERTEX.xz *= thickness;
}

void fragment() {
	float face = pow(abs(dot(normalize(NORMAL), VIEW)), haze ? 1.7 : 0.48);
	float center_fade = smoothstep(0.0, 0.08, span) * (1.0 - smoothstep(0.90, 1.0, span));
	float flicker = 0.83 + 0.17 * sin(span * 61.0 - TIME * 17.0);
	float life = 1.0 - smoothstep(0.09, 1.0, age);
	vec3 pale = mix(arc_tint.rgb, vec3(0.90, 0.95, 0.83), 0.37);
	ALBEDO = haze ? arc_tint.rgb * 0.78 : pale;
	ALPHA = face * center_fade * flicker * life * (haze ? 0.17 : 0.79);
}
