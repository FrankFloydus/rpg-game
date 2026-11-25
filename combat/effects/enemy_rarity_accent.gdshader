shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec4 accent : source_color = vec4(0.32, 0.53, 0.86, 1.0);
uniform float strength : hint_range(0.0, 0.6) = 0.20;
uniform sampler2D skin_alpha : source_color, hint_default_white, filter_linear_mipmap;
uniform bool use_skin_alpha = false;
uniform float skin_opacity : hint_range(0.0, 1.0) = 1.0;
uniform float scissor_threshold = -1.0;
uniform vec2 alpha_scale = vec2(1.0);
uniform vec2 alpha_offset = vec2(0.0);

void fragment() {
	float skin = skin_opacity;
	if (use_skin_alpha) {
		skin *= texture(skin_alpha, UV * alpha_scale + alpha_offset).a;
	}
	if (skin <= scissor_threshold) {
		discard;
	}

	// Catch the shoulders, jaw and other edges where the surface turns away.
	float grazing = 1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fringe = smoothstep(0.38, 0.94, grazing);
	ALBEDO = accent.rgb * (0.54 + 0.35 * fringe);
	ALPHA = strength * (0.04 + 0.96 * fringe) * skin;
}
