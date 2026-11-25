shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

instance uniform float windup = 0.0;
instance uniform int shape_kind = 0;
instance uniform float ring_inner = 0.0;

void fragment() {
	// The perimeter marks the full impact area from the start. Only the fill advances.
	float radius = length(UV);
	float footprint = radius - 1.0;
	float progress_position = radius;
	if (dot(UV2, UV2) > 0.5) {
		footprint = max(footprint, dot(vec2(abs(UV.x), UV.y), UV2));
	}
	if (shape_kind == 1) {
		footprint = max(abs(UV.x), abs(UV.y)) - 1.0;
		progress_position = (UV.y + 1.0) * 0.5;
	} else if (shape_kind == 2) {
		footprint = max(footprint, ring_inner - radius);
		progress_position = (radius - ring_inner) / (1.0 - ring_inner);
	}

	float aa = clamp(fwidth(footprint), 0.006, 0.026);
	float inside = 1.0 - smoothstep(-aa, aa, footprint);
	float edge = 1.0 - smoothstep(0.009, 0.019 + aa, abs(footprint));
	float halo = 1.0 - smoothstep(0.024, 0.067, abs(footprint));

	float charge = clamp(windup, 0.0, 1.0);
	float started = smoothstep(0.006, 0.040, charge);
	float fill = (1.0 - smoothstep(charge - aa, charge + aa, progress_position)) * started;
	float leading_edge = (1.0 - smoothstep(0.008, 0.024 + aa, abs(progress_position - charge)))
		* started * (1.0 - smoothstep(0.92, 1.0, charge));

	float etched = 0.90 + 0.10 * sin(UV.x * 73.0 + sin(UV.y * 66.0) * 1.6)
		* sin(UV.y * 91.0);
	vec3 red = vec3(0.94, 0.021, 0.036);
	ALBEDO = red * (0.44 + 0.23 * fill + 0.27 * edge) * etched;
	EMISSION = red * (0.10 * fill + 0.39 * edge + 0.20 * leading_edge);
	ALPHA = clamp(inside * (0.075 + 0.30 * fill + 0.21 * leading_edge) * etched
		+ 0.53 * edge + 0.10 * halo, 0.0, 0.82);
}
