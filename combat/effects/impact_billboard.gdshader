shader_type spatial;
render_mode unshaded, blend_mix, shadows_disabled, cull_disabled, depth_draw_never;

uniform sampler2D mask_texture : filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(0.36, 0.037, 0.025, 0.9);
uniform bool radial_falloff = false;
uniform bool contact_flash = false;
instance uniform vec4 surface_tint : source_color = vec4(1.0);

varying float particle_age;

void vertex() {
	particle_age = INSTANCE_CUSTOM.y;
	vec2 size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	MODELVIEW_MATRIX = mat4(vec4(size.x, 0.0, 0.0, 0.0),
		vec4(0.0, size.y, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), MODELVIEW_MATRIX[3]);
	float spin = INSTANCE_CUSTOM.x;
	float c = cos(spin);
	float s = sin(spin);
	VERTEX.xy = mat2(vec2(c, s), vec2(-s, c)) * VERTEX.xy;
}

void fragment() {
	vec2 center = UV - vec2(0.5);
	float radius = length(center);
	float coverage = smoothstep(0.16, 0.72, texture(mask_texture, UV).r);
	if (radial_falloff) {
		coverage *= 1.0 - smoothstep(0.12, 0.48, radius);
	}
	float fade = 1.0 - smoothstep(0.14, 1.0, particle_age);
	vec3 brightness = vec3(mix(1.0, 0.54, particle_age));
	if (contact_flash) {
		float point = 1.0 - smoothstep(0.01, 0.31, radius);
		float fan = (1.0 - smoothstep(0.014, 0.067, abs(center.y + center.x * 0.29)))
			* (1.0 - smoothstep(0.06, 0.46, abs(center.x)));
		coverage = point * point * 0.73 + fan * 0.24;
		fade = 1.0 - smoothstep(0.02, 0.76, particle_age);
		brightness = vec3(1.38);
	}
	ALBEDO = tint.rgb * surface_tint.rgb * brightness;
	ALPHA = coverage * tint.a * surface_tint.a * fade;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
