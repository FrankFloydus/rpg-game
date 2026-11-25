uniform int particle_kind = 0;
uniform sampler2D sprite_mask : filter_linear_mipmap, repeat_disable;
uniform sampler2D radial_mask : filter_linear_mipmap, repeat_disable;
uniform sampler2D sheet_normal_map : hint_normal, filter_linear_mipmap, repeat_disable;
uniform sampler2D radial_normal_map : hint_normal, filter_linear_mipmap, repeat_disable;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.86;
uniform float wet_roughness : hint_range(0.05, 1.0) = 0.28;

group_uniforms NiagaraMaterial;
uniform bool source_graph = false;
uniform bool source_masked = false;
#ifdef BLOOD_SMOKE_SRGB
uniform sampler2D source_alpha_map : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
#else
uniform sampler2D source_alpha_map : filter_linear_mipmap_anisotropic, repeat_disable;
#endif
uniform sampler2D source_normal_map : hint_normal, filter_linear_mipmap, repeat_disable;
uniform bool source_normal_anisotropic = false;
uniform sampler2D source_normal_map_anisotropic : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D source_distortion_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D source_reflection_map : source_color, filter_linear, repeat_disable;
uniform vec3 source_main_color = vec3(0.166667, 0.0, 0.0);
uniform vec3 source_secondary_color = vec3(0.052083, 0.0, 0.0);
uniform vec3 source_specular_tint = vec3(1.0, 0.955974, 0.863157);
uniform float source_distort_intensity = 0.01;
uniform float source_distort_tiling = 5.0;
uniform vec2 source_distort_speed = vec2(0.0, 0.5);
uniform float source_specular_value = 5.0;
uniform float source_specular_power = 0.6;
uniform float source_softness = 0.3;
uniform float source_power = 0.8;
uniform float source_normal_strength = 3.0;
uniform float source_darkness = 1.5;
uniform float source_rotation = 0.0;
uniform bool source_dissolve_test = false;
uniform float source_test_dissolve = 0.0;

group_uniforms NiagaraSmoke;
uniform sampler2D source_smoke_detail : filter_linear_mipmap, repeat_enable;
uniform sampler2D source_scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform float source_smoke_fade_distance = 1.0;
uniform float source_smoke_detail_randomization = 400.0;
uniform float source_smoke_detail_opacity = 5.0;
uniform float source_smoke_power = 0.6;

group_uniforms NiagaraEmitter;
uniform bool has_dissolve_curve = false;
uniform bool has_alpha_curve = false;
uniform bool has_size_x_curve = false;
uniform bool has_size_y_curve = false;
uniform bool has_speed_scale_curve = false;
uniform sampler2D source_dissolve_curve : filter_linear, repeat_disable;
uniform sampler2D source_alpha_curve : filter_linear, repeat_disable;
uniform sampler2D source_size_x_curve : filter_linear, repeat_disable;
uniform sampler2D source_size_y_curve : filter_linear, repeat_disable;
uniform sampler2D source_speed_scale_curve : filter_linear, repeat_disable;
uniform vec2 source_speed_scale_min = vec2(1.0);
uniform vec2 source_speed_scale_max = vec2(1.0);
uniform float source_speed_scale_threshold = 0.0;
uniform float source_camera_offset = 0.0;
uniform float source_smoke_frame_span = 63.0;
uniform vec2 source_sprite_pivot = vec2(0.5);
uniform int source_pixel_coverage = 0;
uniform float source_pixel_coverage_blend = 1.0;
group_uniforms;

varying float age;
varying float opacity;
varying float seed;
varying float rounded_sheet;
varying float dissolve_value;
varying float coverage_rgb;

#ifdef BLOOD_SMOKE_SRGB
instance uniform vec3 source_emitter_inverse_x = vec3(1.0, 0.0, 0.0);
instance uniform vec3 source_emitter_inverse_y = vec3(0.0, 1.0, 0.0);
instance uniform vec3 source_emitter_inverse_z = vec3(0.0, 0.0, 1.0);
instance uniform vec3 source_emitter_unscale = vec3(1.0);
#endif

float sample_source_curve(sampler2D curve, float t) {
	// CurveTexture stores i / width at the center of texel i.
	float half_texel = 0.5 / float(textureSize(curve, 0).x);
	return texture(curve, vec2(t + half_texel, 0.5)).r;
}

void vertex() {
	age = clamp(INSTANCE_CUSTOM.y / max(0.001, INSTANCE_CUSTOM.w), 0.0, 1.0);
	opacity = INSTANCE_CUSTOM.y < 0.0 ? 0.0 : COLOR.b;
	float roll = INSTANCE_CUSTOM.x;
	seed = fract(roll * 0.3183);
	vec3 sprite_settings = MODEL_MATRIX[0].xyz;
	vec3 sprite_motion = MODEL_MATRIX[2].xyz;
#ifdef BLOOD_SMOKE_SRGB
	// Local particle transforms are premultiplied by the emitter for rendering.
	mat3 emitter_inverse = transpose(mat3(source_emitter_inverse_x, source_emitter_inverse_y, source_emitter_inverse_z));
	sprite_settings = emitter_inverse * sprite_settings;
	sprite_motion = emitter_inverse * sprite_motion;
#endif
	float alignment = sprite_settings.y;
	float sprite_data = sprite_settings.z;
	int sprite_flags = int(sprite_data);
#ifdef BLOOD_SMOKE_SRGB
	sprite_flags = int(sprite_data + 0.0001);
#endif
	if (source_graph) {
		if ((sprite_flags & 2) != 0) {
			UV.x = 1.0 - UV.x;
		}
		if ((sprite_flags & 4) != 0) {
			UV.y = 1.0 - UV.y;
		}
		dissolve_value = sprite_motion.y < 0.0 ? age : sprite_motion.y;
		if (has_dissolve_curve) {
			dissolve_value = sample_source_curve(source_dissolve_curve, age);
		}
		if (has_alpha_curve) {
			opacity *= sample_source_curve(source_alpha_curve, age);
		} else if (sprite_motion.z >= 0.0) {
			opacity *= sprite_motion.z;
		}
		VERTEX.xy += vec2(0.5 - source_sprite_pivot.x, source_sprite_pivot.y - 0.5);
		vec2 size = vec2(INSTANCE_CUSTOM.z, COLOR.a);
		if (has_size_x_curve) {
			size.x *= sample_source_curve(source_size_x_curve, age);
		}
		if (has_size_y_curve) {
			size.y *= sample_source_curve(source_size_y_curve, age);
		}
		if (source_speed_scale_threshold > 0.0) {
			float t = clamp(sprite_motion.x / source_speed_scale_threshold, 0.0, 1.0);
			if (has_speed_scale_curve) {
				t = clamp(sample_source_curve(source_speed_scale_curve, t), 0.0, 1.0);
			}
			size *= mix(source_speed_scale_min, source_speed_scale_max, t);
		}
		vec4 center = VIEW_MATRIX * MODEL_MATRIX[3];
		coverage_rgb = 1.0;
		bool coverage_enabled = source_pixel_coverage > 1 || (source_pixel_coverage == 0 && !source_masked);
		if (coverage_enabled && PROJECTION_MATRIX[3].w == 0.0) {
			float maximum_size = max(abs(size.x), abs(size.y));
			float minimum_size = max(-center.z, 0.0) * 4.0 / (VIEWPORT_SIZE.x * abs(PROJECTION_MATRIX[0].x));
			if (maximum_size > 0.0 && maximum_size < minimum_size) {
				size *= minimum_size / maximum_size;
				float coverage = min(1.0, 2.0 * maximum_size / minimum_size);
				float color_scale = mix(1.0, coverage * coverage, source_pixel_coverage_blend);
				if (source_pixel_coverage != 2) {
					opacity *= color_scale;
				}
				if (source_pixel_coverage == 3) {
					coverage_rgb = color_scale;
				}
			}
		}
		vec3 forward = vec3(0.0, 0.0, 1.0);
		vec3 up = vec3(0.0, 1.0, 0.0);
		vec3 right = vec3(1.0, 0.0, 0.0);
		vec3 alignment_axis = MODEL_MATRIX[1].xyz;
#ifdef BLOOD_SMOKE_SRGB
		// Niagara applies scale to local centers and rotation to local vectors.
		if (source_emitter_unscale != vec3(1.0) && alignment < 1.5) {
			vec3 local_axis = emitter_inverse * alignment_axis;
			mat3 emitter_basis = inverse(emitter_inverse);
			alignment_axis = emitter_basis * (local_axis * source_emitter_unscale);
		}
#endif
		vec3 axis_in_view = (VIEW_MATRIX * vec4(alignment_axis, 0.0)).xyz;
		if (alignment > 2.5 && dot(axis_in_view, axis_in_view) > 0.00001) {
			forward = normalize(axis_in_view);
			vec3 reference = abs(forward.y) < 0.99 ? up : right;
			if (alignment > 3.5) {
				vec3 world_up = VIEW_MATRIX[1].xyz;
				reference = abs(dot(forward, world_up)) < 0.99 ? world_up : VIEW_MATRIX[0].xyz;
				roll -= fract(sprite_data) * 2.0 * TAU;
			}
			right = normalize(cross(reference, forward));
			up = cross(forward, right);
		} else if (alignment > 0.5 && dot(axis_in_view, axis_in_view) > 0.00001) {
			vec3 camera_direction = normalize(-center.xyz);
			vec3 tangent = cross(axis_in_view, camera_direction);
#ifdef BLOOD_LIQUID_TANGENT
			// Niagara keeps the projected tangent even when an aligned sprite faces end-on.
			// An exactly collinear sprite collapses instead of reverting to a full billboard.
			up = normalize(axis_in_view);
			right = tangent / max(length(tangent), 0.000001);
			vec3 facing = cross(right, up);
			forward = facing / max(length(facing), 0.000001);
#else
			if (dot(tangent, tangent) > 0.00001) {
				up = normalize(axis_in_view);
				right = normalize(tangent);
				forward = normalize(cross(right, up));
			}
#endif
		}
		if (source_camera_offset != 0.0) {
			center.xyz -= normalize(center.xyz) * source_camera_offset;
		}
		// Niagara velocity alignment follows motion without applying sprite rotation.
		float sprite_roll = alignment > 0.5 && alignment < 1.5 ? 0.0 : -roll;
		vec3 rotated_right = right * cos(sprite_roll) + up * sin(sprite_roll);
		vec3 rotated_up = up * cos(sprite_roll) - right * sin(sprite_roll);
		MODELVIEW_MATRIX = mat4(vec4(rotated_right * size.x, 0.0),
			vec4(rotated_up * size.y, 0.0), vec4(forward, 0.0), center);
		MODELVIEW_NORMAL_MATRIX = mat3(rotated_right, rotated_up, forward);
	} else {
		float camera_aligned = 1.0 - step(0.5, alignment);
		rounded_sheet = particle_kind == 1 ? camera_aligned : 0.0;
		vec2 axis = vec2(cos(roll), sin(roll));
		vec2 velocity = (VIEW_MATRIX * vec4(MODEL_MATRIX[1].xyz, 0.0)).xy;
		if (camera_aligned < 0.5 && dot(velocity, velocity) > 0.00001) {
			axis = normalize(velocity);
		}
		float speed = sprite_motion.x;
		float stretch = float(sprite_flags & 1);
		vec2 size = vec2(COLOR.a, INSTANCE_CUSTOM.z);
		if (particle_kind == 0) {
			size *= mix(0.32, 1.15, smoothstep(0.0, 0.80, age));
		} else if (particle_kind == 1) {
			size *= mix(0.49, 1.04, smoothstep(0.0, 0.45, age));
			size.x *= mix(1.0, 0.94 + min(speed, 3.0) * 0.12, stretch);
			if (rounded_sheet > 0.5) {
				size = mix(size, vec2(max(size.x, size.y) * 0.78), 0.74);
			}
		} else if (particle_kind == 2) {
			size.x *= mix(1.0, 0.63 + min(speed, 4.5) * 0.27, stretch);
		}
		vec2 transverse = vec2(-axis.y, axis.x);
		vec4 center = VIEW_MATRIX * MODEL_MATRIX[3];
		MODELVIEW_MATRIX = mat4(vec4(axis * size.x, 0.0, 0.0),
			vec4(transverse * size.y, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), center);
		MODELVIEW_NORMAL_MATRIX = mat3(vec3(axis, 0.0), vec3(transverse, 0.0), vec3(0.0, 0.0, 1.0));
	}
}

vec2 rotate_about_center(vec2 uv, float turns) {
	float angle = TAU * turns;
	vec2 point = uv - vec2(0.5);
	return vec2(dot(point, vec2(cos(angle), -sin(angle))),
		dot(point, vec2(sin(angle), cos(angle)))) + vec2(0.5);
}

float smoke_detail_offset(vec2 tile) {
	// M_Smoke uses the same repeating hash on two integer tile coordinates.
	vec2 point = fract(tile / 128.0) * 128.0 - vec2(64.340622, 72.465622);
	return fract(dot(vec3(point.x * point.x, point.y * point.y, point.x * point.y),
		vec3(20.390625, 60.703125, 2.4281209)));
}

void fragment() {
	if (source_graph) {
#ifndef BLOOD_MASKED_DEPTH
		if (particle_kind == 0) {
			float frame = floor(min(63.0, age * source_smoke_frame_span));
			vec2 cell = vec2(mod(frame, 8.0), floor(frame / 8.0));
			vec2 atlas_uv = (cell + UV) / 8.0;
			float density = texture(source_alpha_map, atlas_uv).r;
			vec2 random_tile = ceil(atlas_uv * source_smoke_detail_randomization);
			vec2 displacement = vec2(smoke_detail_offset(random_tile), smoke_detail_offset(random_tile * 4.0));
			float detail = texture(source_smoke_detail, atlas_uv * source_smoke_detail_randomization + displacement).r;
			float depth = texture(source_scene_depth, SCREEN_UV).r;
			vec4 view_position = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
			float distance_to_geometry = VERTEX.z - view_position.z / view_position.w;
			float depth_fade = clamp(distance_to_geometry / max(source_smoke_fade_distance, 0.001), 0.0, 1.0);
			ALBEDO = source_main_color * coverage_rgb;
			ALPHA = clamp((pow(density, source_smoke_power) + density * detail * source_smoke_detail_opacity)
				* opacity * depth_fade, 0.0, 1.0);
			ROUGHNESS = 1.0;
			SPECULAR = 0.0;
		} else
#endif
		{
			float distortion = texture(source_distortion_map, UV * source_distort_tiling + TIME * source_distort_speed).r;
			vec2 liquid_uv = rotate_about_center(UV + vec2(distortion * source_distort_intensity), source_rotation);
			float density = texture(source_alpha_map, liquid_uv).r;
			float threshold = source_dissolve_test ? source_test_dissolve : dissolve_value;
			float coverage = clamp(clamp((density - threshold) / max(source_softness, 0.0001), 0.0, 1.0) * opacity, 0.0, 1.0);
			if (coverage < 0.003) {
				discard;
			}
			vec3 normal_sample = source_normal_anisotropic
				? texture(source_normal_map_anisotropic, liquid_uv).rgb
				: texture(source_normal_map, liquid_uv).rgb;
			vec3 normal_value = normal_sample * 2.0 - 1.0;
			// The OpenGL normal map already accounts for Unreal's reflection V inversion.
			vec2 reflection_uv = clamp(normal_value.xy
				* source_normal_strength * 0.5 + vec2(0.5), vec2(0.0), vec2(1.0));
			float reflection_mask = clamp(texture(source_reflection_map, reflection_uv).r, 0.0, 1.0);
			vec3 reflection = pow(reflection_mask, source_specular_power)
				* source_specular_value * source_specular_tint;
			float color_weight = pow(max(density, 0.0001), source_power);
			vec3 blood_color = mix(source_main_color, source_secondary_color, color_weight)
				* mix(source_darkness, 1.0, color_weight);
			vec3 pigment = (blood_color + reflection) * coverage_rgb;
			// Unreal saturates the translucent Base Color input before lighting.
			ALBEDO = source_masked ? vec3(0.0) : clamp(pigment, vec3(0.0), vec3(1.0));
			EMISSION = source_masked ? pigment : vec3(0.0);
			if (source_masked) {
				// Only Niagara's masked material uses screen-space dither coverage.
				vec2 pixel = floor(FRAGCOORD.xy);
				float dither = fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
				if (coverage < dither) {
					discard;
				}
				coverage = 1.0;
			}
#ifndef BLOOD_MASKED_DEPTH
			ALPHA = coverage;
#endif
			// Niagara's normal texture steers the baked reflection, not surface lighting.
			ROUGHNESS = 0.5;
			SPECULAR = 0.0;
		}
	}
#ifndef BLOOD_MASKED_DEPTH
	else {
		vec2 local = UV * 2.0 - 1.0;
		float radius = length(local);
		vec3 blood = vec3(0.094, 0.0024, 0.0038);
		vec3 liquid_normal = vec3(0.0, 0.0, 1.0);
		float roughness = 1.0;
		float specular = 0.0;
		float shape;
		float fade;
		if (particle_kind == 0) {
			float density = texture(sprite_mask, UV).r;
			shape = smoothstep(0.07 + age * 0.18, 0.85, density);
			fade = 1.0 - smoothstep(0.12, 1.0, age);
			blood = vec3(0.117, 0.005, 0.008);
		} else if (particle_kind == 1) {
			float threshold = mix(0.10, 0.77, smoothstep(0.13, 1.0, age));
			vec2 sheet_uv = vec2(UV.x, seed > 0.5 ? 1.0 - UV.y : UV.y);
			float density;
			vec3 packed_normal;
			if (rounded_sheet > 0.5) {
				density = texture(radial_mask, sheet_uv).r;
				packed_normal = texture(radial_normal_map, sheet_uv).rgb;
			} else {
				density = texture(sprite_mask, sheet_uv).r;
				packed_normal = texture(sheet_normal_map, sheet_uv).rgb;
			}
			shape = smoothstep(threshold, threshold + 0.10, density);
			fade = 1.0 - smoothstep(0.27, 1.0, age);
			blood *= mix(0.75, 1.15, density);
			float thickness = smoothstep(threshold, min(threshold + 0.30, 0.99), density);
			liquid_normal = packed_normal * 2.0 - 1.0;
			liquid_normal.y *= seed > 0.5 ? -1.0 : 1.0;
			roughness = clamp(wet_roughness + (1.0 - thickness) * 0.20 + age * 0.10, 0.08, 1.0);
			specular = mix(0.29, 0.49, thickness);
		} else if (particle_kind == 2) {
			float taper = abs(local.y) * mix(0.78, 1.42, smoothstep(0.0, 1.0, UV.x));
			radius = length(vec2(local.x, taper));
			shape = 1.0 - smoothstep(0.70, 1.0, radius);
			fade = 1.0 - smoothstep(0.65, 1.0, age);
			blood *= mix(1.08, 0.72, radius);
			vec2 curvature = vec2(local.x * 0.68, -local.y * 0.85);
			liquid_normal = normalize(vec3(curvature, sqrt(max(0.08, 1.0 - dot(curvature, curvature)))));
			roughness = min(wet_roughness + 0.04 + age * 0.12, 1.0);
			specular = 0.45;
		} else {
			float angle = atan(local.y, local.x);
			float edge = 0.82 + 0.10 * cos(angle * 3.0 + seed * TAU) + 0.07 * sin(angle * 5.0);
			shape = 1.0 - smoothstep(edge - 0.12, edge, radius);
			fade = 1.0 - smoothstep(0.72, 1.0, age);
			blood = vec3(0.057, 0.0014, 0.0022) * mix(1.25, 0.72, radius);
			liquid_normal = normalize(vec3(local.x * 0.86, -local.y * 0.86,
				sqrt(max(0.06, 1.0 - dot(local, local)))));
			roughness = min(wet_roughness + 0.11 + age * 0.14, 1.0);
			specular = 0.43;
		}
		ALPHA = shape * fade * opacity;
		if (ALPHA < 0.006) {
			discard;
		}
		ALBEDO = blood;
		NORMAL_MAP = liquid_normal * 0.5 + 0.5;
		NORMAL_MAP_DEPTH = normal_strength;
		ROUGHNESS = roughness;
		SPECULAR = specular;
		CLEARCOAT = specular * 0.38 * (1.0 - age * 0.65);
		CLEARCOAT_ROUGHNESS = max(0.15, roughness * 0.78);
		// The diffuse mist and backlit liquid retain a little color in shadow.
		EMISSION = blood * (particle_kind == 0 ? 0.42 : 0.09);
	}
#endif
}
