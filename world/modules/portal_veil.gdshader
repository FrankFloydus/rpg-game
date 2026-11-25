shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

instance uniform vec4 portal_tint : source_color = vec4(0.45, 0.77, 0.69, 1.0);

float hash_cell(vec2 point) {
	vec3 p = fract(point.xyx * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float grain(vec2 point) {
	vec2 cell = floor(point);
	vec2 phase = fract(point);
	phase = phase * phase * (3.0 - 2.0 * phase);
	float low = mix(hash_cell(cell), hash_cell(cell + vec2(1.0, 0.0)), phase.x);
	float high = mix(hash_cell(cell + vec2(0.0, 1.0)), hash_cell(cell + 1.0), phase.x);
	return mix(low, high, phase.y);
}

float cloud(vec2 point) {
	float low = grain(point);
	point = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * point + vec2(5.7, 1.2);
	float high = grain(point);
	return low * 0.56 + high * 0.28 + grain(point * 2.15 - vec2(6.2, 3.3)) * 0.16;
}

void fragment() {
	vec2 point = (UV - 0.5) * 2.0;
	float radius = length(point);
	float time = TIME * 0.28 + dot(NODE_POSITION_WORLD.xz, vec2(0.13, -0.19));
	float turn = time + 3.1 * (1.0 - radius);
	vec2 rotation = vec2(cos(turn), sin(turn));
	vec2 swirl = mat2(rotation, vec2(-rotation.y, rotation.x)) * point;
	vec2 drift = vec2(time * 0.27, -time * 0.37);
	float mist = cloud(swirl * 3.4 - drift * 0.6);
	float grain_detail = cloud(swirl * 7.3 + drift);
	float angle = atan(point.y, point.x + 0.00001);
	float hollows = smoothstep(0.09, 0.52, radius);
	float folds = sin(angle * 3.0 + radius * 10.2 - time * 3.3 + mist * 2.4);
	float smoke = smoothstep(0.22, 0.84, mist * 0.71 + grain_detail * 0.29);
	float ribbons = smoothstep(0.20, 1.0, folds) * smoke * hollows;

	float rim_variation = grain(point * 11.2 + drift);
	float rim_at = 0.863 + (rim_variation - 0.5) * 0.078;
	float rim = exp(-pow((radius - rim_at) / 0.051, 2.0));
	float cracks = smoothstep(0.12, 0.66, rim_variation * 0.60 + grain_detail * 0.40);
	float edge = 1.0 - smoothstep(0.84, 0.99, radius);
	float corona = rim * (0.14 + 0.86 * cracks);
	vec3 heart = mix(vec3(0.009, 0.011, 0.013), portal_tint.rgb * 0.24, smoke);
	ALBEDO = mix(heart, portal_tint.rgb * 0.97, ribbons * 0.62 + corona * 0.34);
	EMISSION = portal_tint.rgb * (corona * 0.30 + ribbons * 0.14);
	ALPHA = edge * clamp(0.40 + smoke * 0.27 + ribbons * 0.11 + corona * 0.27, 0.0, 0.87);
}

