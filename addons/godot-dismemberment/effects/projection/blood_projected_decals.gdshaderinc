uniform sampler2DArray blood_decal_color : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2DArray blood_decal_coverage : filter_linear_mipmap, repeat_disable;
uniform bool blood_coverage_only = false;
uniform sampler2DArray blood_decal_normal : filter_linear_mipmap, repeat_disable;
#ifdef BLOOD_PROJECTED_COOKED_NORMALS
uniform sampler2DArray blood_decal_cooked_normal : filter_linear_mipmap, repeat_disable;
uniform int blood_cooked_normal_layers[20];
#endif
#ifdef BLOOD_PROJECTED_DISTORTION
uniform sampler2D blood_decal_distortion : filter_linear_mipmap, repeat_enable;
uniform bool blood_decal_distortion_enabled = false;
uniform float blood_decal_distortion_time = -1.0;
#endif
uniform sampler2DArray blood_decal_orm : filter_linear_mipmap, repeat_disable;
uniform bool blood_surface_finish_enabled = false;
uniform float blood_alpha_cutoff : hint_range(0.0, 1.0, 0.01) = .27;
uniform sampler2D blood_grunge : filter_linear_mipmap, repeat_enable, hint_default_white;
uniform float blood_grunge_repeats_per_meter : hint_range(0.0, 16.0, 0.1) = 4.0;
uniform float blood_grunge_strength : hint_range(0.0, 1.0, 0.01) = .45;
uniform int blood_projector_count = 0;
uniform mat4 blood_receiver_to_projector[16];
uniform vec4 blood_projector_state[16]; // slot, dissolve or opacity, UV turns, native decal flag
uniform vec4 blood_projector_tint[16]; // linear RGB from the native decal
uniform vec4 blood_projector_footprint[16]; // width, length, upper and lower fade
uniform vec4 blood_material_tint[20];
uniform vec4 blood_material_parameters[20]; // source darkness (-1 custom RGB), normal scale, metallic, specular
uniform vec4 blood_material_roughness[20]; // ORM roughness multiplier, AO multiplier, alpha, normal use

float blood_finish_coverage(float alpha, vec2 dx, vec2 dy, vec2 texels) {
	if (blood_alpha_cutoff <= 0.0) {
		return alpha;
	}
	// Keep fractional coverage after filtering. Promoting every sample
	// above the cutoff to opaque makes small droplets jagged and too dark.
	float span = max(length(dx * texels), length(dy * texels));
	float edge_width = clamp(.14 + span * .025, .14, .29);
	float edge = smoothstep(blood_alpha_cutoff - edge_width, blood_alpha_cutoff + edge_width, alpha);
	return alpha + alpha * (1.0 - alpha) * mix(-.38, .55, edge);
}

void blood_apply_projected_decals(vec3 local_position, mat3 local_normal_to_view,
		inout vec3 albedo, inout vec3 surface_normal, inout float roughness, inout float metallic,
		inout float specular, inout float ambient_occlusion) {
	vec3 geometric_normal = normalize(surface_normal);
	vec3 local_dx = dFdx(local_position);
	vec3 local_dy = dFdy(local_position);
	for (int i = 0; i < blood_projector_count; i++) {
		mat4 projection = blood_receiver_to_projector[i];
		vec3 p = (projection * vec4(local_position, 1)).xyz;
		if (any(greaterThan(abs(p), vec3(.5)))) {
			continue;
		}
		vec4 state = blood_projector_state[i];
		int slot = int(state.x);
		bool native_decal = state.w > 0.0;
		if (native_decal && state.y <= 0.0) {
			continue;
		}
		vec3 outward_local = normalize(vec3(projection[0].y, projection[1].y, projection[2].y));
		vec3 outward = normalize(local_normal_to_view * outward_local);
		float incidence = .8 + .2 * dot(geometric_normal, outward);
		float depth = clamp(4.0 - 8.0 * abs(p.y), 0.0, 1.0);
		vec4 footprint = blood_projector_footprint[i];
		if (native_decal) {
			incidence = smoothstep(.6, 1.0, dot(geometric_normal, outward) * .5 + .5);
			float exponent = p.y > 0.0 ? footprint.z : footprint.w;
			depth = pow(max(1.0 - 2.0 * abs(p.y), .00001), exponent);
		}
		float turn = state.z * TAU;
		mat2 rot = mat2(vec2(cos(turn), sin(turn)), vec2(-sin(turn), cos(turn)));
		vec2 uv = rot * p.xz + .5;
		vec2 base_dx = (mat3(projection) * local_dx).xz;
		vec2 base_dy = (mat3(projection) * local_dy).xz;
		vec2 dx = rot * base_dx;
		vec2 dy = rot * base_dy;
		vec4 props = blood_material_parameters[slot];
		vec4 tuning = blood_material_roughness[slot];
		bool source_material = !native_decal && props.x >= 0.0;
#ifdef BLOOD_PROJECTED_DISTORTION
		if (source_material && blood_decal_distortion_enabled) {
			float seconds = blood_decal_distortion_time < 0.0 ? TIME : blood_decal_distortion_time;
			vec2 noise_uv = (p.xz + .5) * 3.0 + vec2(0.0, seconds * .02);
			float warp = .01 * textureGrad(blood_decal_distortion, noise_uv, base_dx * 3.0, base_dy * 3.0).r;
			uv += vec2(warp);
		}
#endif
		bool separate_coverage = native_decal && blood_coverage_only;
		vec4 art;
		if (separate_coverage) {
			float alpha = textureGrad(blood_decal_coverage, vec3(uv, state.x), dx, dy).r;
			// Linear equivalent of the stock grunge's mean sRGB value (219/255).
			art = vec4(vec3(.708376), alpha);
		} else {
			art = textureGrad(blood_decal_color, vec3(uv, state.x), dx, dy);
		}
		float coverage = clamp((art.a - state.y) / .21792, 0.0, 1.0) * incidence * depth * tuning.z;
		if (native_decal) {
			vec2 texels = separate_coverage ? vec2(textureSize(blood_decal_coverage, 0).xy)
				: vec2(textureSize(blood_decal_color, 0).xy);
			float mask = blood_surface_finish_enabled ? blood_finish_coverage(art.a, dx, dy, texels) : art.a;
			coverage = mask * incidence * depth * state.y;
		}
		if (coverage <= 0.0) {
			continue;
		}
		vec3 color = art.rgb;
		if (source_material) {
			color = mix(vec3(.177083,0,.001471),vec3(.151042,0,0),art.a) * mix(props.x,1.0,art.a);
		}
		if (native_decal && blood_surface_finish_enabled && blood_grunge_strength > 0.0 && blood_grunge_repeats_per_meter > 0.0) {
			vec2 meters_to_uv = footprint.xy * blood_grunge_repeats_per_meter;
			vec2 grunge_uv = rot * (p.xz * meters_to_uv);
			float grunge = textureGrad(blood_grunge, grunge_uv,
				rot * (base_dx * meters_to_uv), rot * (base_dy * meters_to_uv)).r;
			color *= 1.0 + blood_grunge_strength * clamp((grunge - .86) * 5.5, -1.0, 1.0);
		}
		vec3 tint = native_decal ? blood_projector_tint[i].rgb : blood_material_tint[slot].rgb;
		albedo = mix(albedo, color * tint, coverage);
		// Source roughness samples its own unrotated coordinates.
		vec2 orm_uv = source_material ? p.xz + .5 : uv;
		vec3 orm = textureGrad(blood_decal_orm, vec3(orm_uv, state.x),
			source_material ? base_dx : dx, source_material ? base_dy : dy).rgb;
		ambient_occlusion = mix(ambient_occlusion, native_decal ? orm.r : mix(1.0, orm.r, tuning.y), coverage);
		roughness = mix(roughness, native_decal ? orm.g : orm.g * tuning.x, coverage);
		metallic = mix(metallic, native_decal ? orm.b : orm.b * props.z, coverage);
		if (source_material) {
			// Unreal blends the scalar before mapping F0 = .08 * S.
			// Godot maps F0 = .16 * S², so match reflectance without changing the lighting model.
			specular = sqrt(max(0.0, mix(specular * specular, 0.5 * props.w, coverage)));
		} else if (!native_decal) {
			specular = mix(specular, props.w, coverage);
		}
		if (tuning.w > .5) {
			vec2 packed_normal;
#ifdef BLOOD_PROJECTED_COOKED_NORMALS
			int layer = blood_cooked_normal_layers[slot];
			if (source_material && layer >= 0) {
				packed_normal = textureGrad(blood_decal_cooked_normal, vec3(uv, float(layer)), dx, dy).rg;
			} else
#endif
			{
				packed_normal = textureGrad(blood_decal_normal, vec3(uv, state.x), dx, dy).rg;
			}
			vec2 rg = packed_normal * 2.0 - 1.0;
			float z = sqrt(max(0.,1.0 - dot(rg,rg)));
			// Unreal rotates the lookup UV and uses the unscaled projector axes for the normal.
			vec2 normal_xy = props.y * (source_material ? rg * vec2(1.0, -1.0) : transpose(rot) * rg);
			if (native_decal) {
				normal_xy = rg * vec2(1.0, -1.0);
			}
			vec3 u = normalize(local_normal_to_view * vec3(projection[0].x,projection[1].x,projection[2].x));
			vec3 v = normalize(local_normal_to_view * vec3(projection[0].z,projection[1].z,projection[2].z));
			vec3 detail = normalize(u * normal_xy.x + v * normal_xy.y + outward * (source_material ? 2.0 - z : z));
			surface_normal = normalize(mix(surface_normal,detail,coverage));
		}
	}
}
