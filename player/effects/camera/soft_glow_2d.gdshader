shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

uniform vec4 glow_color : source_color = vec4(1.0);
uniform float glow_intensity : hint_range(0.0, 2.0, 0.01) = 0.65;
// Radius in viewport pixels. Leave transparent padding around the texture's silhouette.
uniform float glow_radius : hint_range(0.0, 48.0, 0.5) = 16.0;
// Use for an additive overlay when another material draws the original artwork.
uniform bool glow_only = false;

const float BLUR_WEIGHTS[7] = {0.015625, 0.09375, 0.234375, 0.3125, 0.234375, 0.09375, 0.015625};
varying vec4 item_tint;

void vertex() {
	item_tint = COLOR;
}

void fragment() {
	// REGION_RECT identifies the active atlas region.
	vec2 lower = max(vec2(0.0), REGION_RECT.xy);
	vec2 upper = min(vec2(1.0), REGION_RECT.xy + abs(REGION_RECT.zw));
	vec2 half_texel = min(TEXTURE_PIXEL_SIZE * 0.5, (upper - lower) * 0.5);
	bool cropped = any(greaterThan(lower, vec2(0.0))) || any(lessThan(upper, vec2(1.0)));
	vec2 sample_min = lower + half_texel;
	vec2 sample_max = upper - half_texel;

	COLOR = vec4(0.0);
	if (!glow_only) {
		vec4 body = cropped ? textureLod(TEXTURE, clamp(UV, sample_min, sample_max), 0.0) : texture(TEXTURE, UV);
		body *= item_tint;
		COLOR = vec4(body.rgb * body.a, body.a);
	}
	if (glow_radius > 0.0 && glow_intensity > 0.0) {
		vec2 dx = dFdx(UV);
		vec2 dy = dFdy(UV);
		float spacing = glow_radius / 3.0;
		vec2 blur_dx = dx * spacing;
		vec2 blur_dy = dy * spacing;
		vec2 edge_width = max(TEXTURE_PIXEL_SIZE * 0.5, (abs(dx) + abs(dy)) * max(0.5, spacing * 0.75));
		float texels_per_pixel = max(length(dx / TEXTURE_PIXEL_SIZE), length(dy / TEXTURE_PIXEL_SIZE));
		// Prefilter overlapping footprints so thin artwork doesn't reappear at every tap.
		float blur_lod = log2(max(1.0, texels_per_pixel * max(1.0, spacing * 1.5)));
		vec2 limit_lower = mix(vec2(-1.0), lower, greaterThan(lower, vec2(0.0)));
		vec2 limit_upper = mix(vec2(2.0), upper, lessThan(upper, vec2(1.0)));
		float coverage = 0.0;
		for (int y = 0; y < 7; y++) {
			for (int x = 0; x < 7; x++) {
				vec2 sample_uv = UV + blur_dx * float(x - 3) + blur_dy * float(y - 3);
				// Fade a tap across the boundary as its footprint enters transparent space.
				vec2 edge = min(sample_uv - lower, upper - sample_uv);
				vec2 edge_weight = smoothstep(-edge_width, edge_width, edge);
				float clip_weight = edge_weight.x * edge_weight.y;
				if (clip_weight > 0.0) {
					vec2 clamped_uv = clamp(sample_uv, sample_min, sample_max);
					float lod = blur_lod;
					if (cropped) {
						// Cap the coarsest mip used by trilinear filtering before its bilinear
						// footprint can reach across an internal atlas boundary.
						vec2 edge_texels = min(sample_uv - limit_lower, limit_upper - sample_uv) / TEXTURE_PIXEL_SIZE;
						float safe_lod = log2(max(1.0, min(edge_texels.x, edge_texels.y) * 0.25));
						lod = min(lod, safe_lod);
					}
					float mask = textureLod(TEXTURE, clamped_uv, lod).a;
					coverage += mask * clip_weight * BLUR_WEIGHTS[x] * BLUR_WEIGHTS[y];
				}
			}
		}
		COLOR.rgb += glow_color.rgb * item_tint.rgb * (coverage * glow_intensity * glow_color.a * item_tint.a);
	}
}
