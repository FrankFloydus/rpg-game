shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

uniform bool sparks = false;
uniform bool mist = false;
instance uniform vec4 portal_tint : source_color = vec4(0.45, 0.77, 0.69, 1.0);
varying flat float grain;

void vertex() {
	grain = INSTANCE_CUSTOM.z;
	if (sparks) {
		// A mote is a soft point in space and stays readable when viewed edge-on.
		vec3 particle_size = vec3(length(MODELVIEW_MATRIX[0].xyz), length(MODELVIEW_MATRIX[1].xyz), 1.0);
		MODELVIEW_MATRIX = mat4(vec4(particle_size.x, 0.0, 0.0, 0.0),
			vec4(0.0, particle_size.y, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0),
			MODELVIEW_MATRIX[3]);
	}
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float opacity = 0.0;
	if (mist) {
		float drift = sin(p.x * 3.2 + grain * TAU) * 0.20;
		float distance = length(vec2(p.x, (p.y - drift) * 1.5));
		opacity = (1.0 - smoothstep(0.13, 0.84, distance)) * 0.40;
	} else if (sparks) {
		float distance = length(p);
		opacity = exp(-distance * distance * 5.3) * (1.0 - smoothstep(0.55, 1.0, distance));
	} else {
		float curve = p.x * p.x * (0.34 + grain * 0.17) - 0.21;
		curve += sin(p.x * 3.4 + grain * 4.0) * 0.12;
		float axis = p.y - curve;
		float end_fade = 1.0 - smoothstep(0.20, 1.0, abs(p.x));
		float thread = exp(-pow(axis / (0.13 + grain * 0.07), 2.0));
		float vapor = exp(-pow(axis / 0.39, 2.0));
		float ripples = 0.64 + 0.36 * sin(p.x * 10.1 + grain * TAU);
		opacity = end_fade * (thread * 0.54 + vapor * 0.14) * ripples;
	}
	opacity *= 1.0 - smoothstep(0.78, 1.0, abs(p.y));
	ALBEDO = mix(portal_tint.rgb, vec3(0.62, 0.58, 0.54), sparks ? 0.28 : 0.15);
	ALPHA = opacity * COLOR.a * (sparks ? 0.77 : 0.56);
}

