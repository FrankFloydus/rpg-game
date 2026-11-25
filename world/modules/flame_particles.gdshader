shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform int layer = 0;
uniform float density : hint_range(0.0, 1.0) = 0.7;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
instance uniform vec4 flame_tint : source_color = vec4(1.0);
varying flat float particle_age;
varying flat float variation;

float hash_cell(vec2 cell) {
	vec3 p = fract(vec3(cell.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float flow_noise(vec2 uv) {
	vec2 cell = floor(uv);
	vec2 blend = smoothstep(vec2(0.0), vec2(1.0), fract(uv));
	return mix(mix(hash_cell(cell), hash_cell(cell + vec2(1.0, 0.0)), blend.x),
		mix(hash_cell(cell + vec2(0.0, 1.0)), hash_cell(cell + 1.0), blend.x), blend.y);
}

void vertex() {
	particle_age = clamp(INSTANCE_CUSTOM.y, 0.0, 1.0);
	// Animation offset is sampled at birth. Draw-order changes cannot reseed the pattern.
	variation = fract(INSTANCE_CUSTOM.z + INSTANCE_CUSTOM.w * 0.618);
	vec2 extent = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	vec4 center = MODELVIEW_MATRIX[3];
	if (layer == 0) {
		vec3 up = normalize(MODEL_MATRIX[1].xyz);
		vec3 to_camera = CAMERA_POSITION_WORLD - MODEL_MATRIX[3].xyz;
		vec3 right = cross(up, to_camera);
		if (dot(right, right) < 0.0001) {
			right = INV_VIEW_MATRIX[0].xyz;
		}
		MODELVIEW_MATRIX = mat4(
			VIEW_MATRIX * vec4(normalize(right) * extent.x, 0.0),
			VIEW_MATRIX * vec4(up * extent.y, 0.0), vec4(0.0, 0.0, 1.0, 0.0), center);
	} else {
		MODELVIEW_MATRIX = mat4(
			vec4(extent.x, 0.0, 0.0, 0.0), vec4(0.0, extent.y, 0.0, 0.0),
			vec4(0.0, 0.0, 1.0, 0.0), center);
		if (layer == 1) {
			float s = sin(INSTANCE_CUSTOM.x);
			float c = cos(INSTANCE_CUSTOM.x);
			VERTEX.xy = mat2(vec2(c, s), vec2(-s, c)) * VERTEX.xy;
		}
	}
}

float soft_intersection(vec2 screen_uv, float fragment_depth, mat4 inverse_projection) {
	float depth = texture(scene_depth, screen_uv).x;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		vec3 ndc = vec3(screen_uv, depth) * 2.0 - 1.0;
	#else
		vec3 ndc = vec3(screen_uv * 2.0 - 1.0, depth);
	#endif
	vec4 surface = inverse_projection * vec4(ndc, 1.0);
	return smoothstep(0.0, 0.19, fragment_depth - surface.z / surface.w);
}

vec2 flame_density(vec2 uv, float clock) {
	float height = 1.0 - uv.y;
	float horizontal = uv.x - 0.5;
	float sway = flow_noise(vec2(variation * 6.3, height * 2.4 - clock));
	float fold = flow_noise(vec2(uv.x * 7.3 + variation * 3.0, height * 4.4 - clock * 1.18));
	float peak = 0.77 + 0.14 * sway;
	float root = smoothstep(0.015, 0.14, height);
	float taper = pow(max(0.0, 1.0 - height / peak), 0.74);
	float center = (sway - 0.5) * (0.08 + 0.32 * height);
	float width = 0.025 + (0.255 + (fold - 0.5) * 0.19) * taper;
	float plume = 1.0 - smoothstep(width * 0.22, width, abs(horizontal - center));
	plume *= root * (1.0 - smoothstep(peak - 0.15, peak + 0.025, height));

	float curl_side = variation < 0.5 ? -1.0 : 1.0;
	float curl_center = center + curl_side * (0.06 + height * 0.18);
	float curl_width = (0.035 + taper * 0.085) * (0.69 + fold * 0.42);
	float curl = 1.0 - smoothstep(curl_width * 0.28, curl_width, abs(horizontal - curl_center));
	curl *= smoothstep(0.16, 0.33, height) * (1.0 - smoothstep(0.44, 0.73, height));
	float body = max(plume, curl * 0.74) * (0.65 + 0.35 * fold);
	float heat = pow(plume, 1.17) * (1.0 - smoothstep(0.18, 0.72, height)) * (0.62 + 0.38 * fold);
	// Reserve transparent texels on every edge, including at the widest turbulent lobe.
	float edge = smoothstep(0.025, 0.14, uv.x) * smoothstep(0.025, 0.14, 1.0 - uv.x);
	edge *= smoothstep(0.0, 0.07, uv.y) * smoothstep(0.0, 0.07, 1.0 - uv.y);
	return vec2(body * edge, heat);
}

void fragment() {
	float clock = TIME * (0.63 + 0.21 * variation) + variation * 11.0 + particle_age * 0.64;
	float shaded_flame = smoothstep(0.12, 0.44, max(flame_tint.g, flame_tint.b) - flame_tint.r);
	float opacity = 0.0;
	if (layer == 0) {
		vec2 flame = flame_density(UV, clock);
		float heat = flame.y * (1.0 - 0.24 * smoothstep(0.42, 1.0, particle_age));
		vec3 rim = vec3(0.75, 0.112, 0.023);
		vec3 body = vec3(1.19, 0.43, 0.097);
		vec3 core = vec3(1.62, 1.03, 0.49);
		vec3 pigment = mix(mix(rim, body, smoothstep(0.12, 0.65, heat)),
			core, smoothstep(0.52, 0.88, heat));
		ALBEDO = mix(pigment, vec3(0.23 + 0.64 * heat), shaded_flame) * flame_tint.rgb;
		opacity = flame.x;
	} else if (layer == 1) {
		vec2 p = (UV - 0.5) * 2.0;
		float body = 1.0 - smoothstep(0.06, 0.92, length(p * vec2(1.16, 0.77)));
		float heart = smoothstep(0.24, 0.93, body);
		vec3 glow = mix(vec3(0.75, 0.077, 0.011), vec3(1.36, 0.74, 0.21), heart);
		ALBEDO = mix(glow, vec3(0.27 + 0.72 * heart), shaded_flame) * flame_tint.rgb;
		opacity = body * body;
	} else {
		vec2 uv = UV - 0.5;
		uv.x += (flow_noise(vec2(uv.y * 2.8, clock * 0.19)) - 0.5) * 0.11;
		float roll = flow_noise(uv * 4.2 + vec2(variation * 9.0, -clock * 0.22));
		float grain = flow_noise(uv * 9.3 + vec2(-clock * 0.20, variation * 3.7));
		float soft_edge = 1.0 - smoothstep(0.09, 0.47, length(uv * vec2(1.04, 0.96)));
		float volume = smoothstep(0.29, 0.87, roll * 0.72 + grain * 0.28 + soft_edge * 0.10);
		float warmth = (1.0 - particle_age) * (0.45 + 0.55 * volume);
		if (layer == 3) {
			ALBEDO = mix(vec3(0.059, 0.090, 0.036), vec3(0.22, 0.31, 0.107), warmth);
		} else {
			ALBEDO = mix(vec3(0.058, 0.055, 0.054), vec3(0.24, 0.144, 0.088), warmth);
		}
		opacity = volume * soft_edge * soft_intersection(SCREEN_UV, VERTEX.z, INV_PROJECTION_MATRIX);
	}
	ALPHA = opacity * COLOR.a * density * flame_tint.a;
}
