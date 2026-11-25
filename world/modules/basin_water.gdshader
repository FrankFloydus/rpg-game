shader_type spatial;
render_mode cull_disabled, depth_draw_never, specular_disabled;

varying vec3 water_world;

void vertex() {
	water_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 position = water_world.xz;
	float long_wave = sin(dot(position, vec2(7.2, 3.0)) + TIME * 1.05);
	float short_wave = cos(dot(position, vec2(-5.2, 9.8)) - TIME * 1.42);
	float ripples = long_wave * 0.58 + short_wave * 0.42;
	float along = dot(position, vec2(0.86, 0.51));
	float across = dot(position, vec2(-0.51, 0.86));
	float bend = sin(across * 2.35 + sin(along * 1.89 - TIME * 0.32) * 1.24);
	float wave_phase = along * 9.80 + bend * 0.93 + sin(across * 5.63) * 0.26 - TIME * 1.37;
	float crest_distance = abs(sin(wave_phase));
	float edge_softness = max(fwidth(crest_distance), 0.064);
	float line = 1.0 - smoothstep(0.05, 0.22 + edge_softness, crest_distance);
	float interruption = sin(across * 5.6 + along * 1.98 + sin(along * 2.45 + TIME * 0.41) * 1.46);
	float thin_crest = line * smoothstep(-0.26, 0.72, interruption);
	float edge_distance = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float shoreline = (1.0 - smoothstep(0.0, 0.057, edge_distance)) * (0.64 + ripples * 0.25);
	float grazing = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.2);
	vec3 dark_water = vec3(0.027, 0.095, 0.102);
	vec3 crest = vec3(0.134, 0.277, 0.269);
	ALBEDO = mix(dark_water, crest, grazing * 0.36 + thin_crest * 0.19 + shoreline * 0.22);
	EMISSION = crest * (0.18 + thin_crest * 0.18 + shoreline * 0.28);
	ROUGHNESS = 1.0;
	ALPHA = clamp(0.34 + grazing * 0.31 + thin_crest * 0.09 + shoreline * 0.11, 0.0, 0.78);
}
