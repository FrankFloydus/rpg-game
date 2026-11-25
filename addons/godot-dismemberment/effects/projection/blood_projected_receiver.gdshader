shader_type spatial;
render_mode cull_back;

/** Tint multiplied into the receiving surface's base color. */
uniform vec4 receiver_tint : source_color = vec4(1);
/** Base color texture for the receiving surface. */
uniform sampler2D receiver_color : source_color, hint_default_white, filter_linear_mipmap;
/** Packed occlusion, roughness, and metallic texture for the receiving surface. */
uniform sampler2D receiver_orm : hint_default_white, filter_linear_mipmap;
/** Read occlusion, roughness, and metallic from Receiver ORM. */
uniform bool use_receiver_orm = false;
/** Base roughness of the receiving surface. The ORM green channel multiplies it when enabled. */
uniform float receiver_roughness = .72;
/** Base metallic value of the receiving surface. The ORM blue channel multiplies it when enabled. */
uniform float receiver_metallic = 0.;
/** Strength of the receiving surface's specular response. */
uniform float receiver_specular = .5;
/** Tiling of the receiving surface's own textures. Decal UVs come from the projectors. */
uniform vec3 receiver_uv_scale = vec3(1);
/** Offset of the receiving surface's own texture UVs. */
uniform vec3 receiver_uv_offset = vec3(0);

// Godot reads uniform descriptions from this shader before expanding its includes.
#ifdef BLOOD_INSPECTOR_DOCUMENTATION
/** Baked atlas of decal colors and opacity masks. Supplied by the receiver's Atlas. */
uniform sampler2DArray blood_decal_color;
/** Optional linear coverage array for decals with separate tiled color. */
uniform sampler2DArray blood_decal_coverage;
/** Read the splatter shape from the linear coverage array. */
uniform bool blood_coverage_only;
/** Baked atlas of decal normal maps. Supplied by the receiver's Atlas. */
uniform sampler2DArray blood_decal_normal;
/** Optional atlas of filtered source normal maps. */
uniform sampler2DArray blood_decal_cooked_normal;
/** Optional cooked normal layer for each material slot. A value of -1 uses the ordinary atlas. */
uniform int blood_cooked_normal_layers [20];
/** Repeating noise texture for the optional animated decal distortion. */
uniform sampler2D blood_decal_distortion;
/** Enable animated UV distortion for source materials. */
uniform bool blood_decal_distortion_enabled;
/** Fixed distortion time in seconds for preview. A negative value uses live shader time. */
uniform float blood_decal_distortion_time;
/** Baked atlas with occlusion, roughness, and metallic in red, green, and blue. */
uniform sampler2DArray blood_decal_orm;
/** Enable adjustable coverage and tiled grunge for native decal projections. */
uniform bool blood_surface_finish_enabled;
/** Coverage threshold for the solid part of a decal. Lower values keep more of the soft spray. */
uniform float blood_alpha_cutoff;
/** Repeating color variation texture sampled separately from the splatter shape. */
uniform sampler2D blood_grunge;
/** Grunge repeats per metre along the projected surface. */
uniform float blood_grunge_repeats_per_meter;
/** Strength of the tiled color variation. */
uniform float blood_grunge_strength;
/** Number of active projectors. The receiver updates this as marks appear and expire. */
uniform int blood_projector_count;
/** Transforms from receiver-local coordinates into each active projector. Set by the receiver. */
uniform mat4 blood_receiver_to_projector [16];
/** Active projector material slot, dissolve or opacity, UV rotation in turns, and native decal flag. */
uniform vec4 blood_projector_state [16];
/** Linear RGB tint of each native decal. Set by the receiver. */
uniform vec4 blood_projector_tint [16];
/** Width and length in metres and upper and lower depth fade exponents. Set by the receiver. */
uniform vec4 blood_projector_footprint [16];
/** Linear color multiplier for each atlas material. Set by the receiver. */
uniform vec4 blood_material_tint [20];
/** Per-material source darkness, normal strength, metallic, and specular. Set by the receiver. */
uniform vec4 blood_material_parameters [20];
/** Per-material roughness and occlusion multipliers, alpha, and normal toggle. Set by the receiver. */
uniform vec4 blood_material_roughness [20];
#endif

#include "res://addons/godot-dismemberment/effects/projection/blood_projected_decals.gdshaderinc"

varying vec3 local_position;
varying mat3 local_normal_to_view;

void vertex() {
	local_position = VERTEX;
	local_normal_to_view = MODELVIEW_NORMAL_MATRIX;
}

void fragment() {
	vec2 receiver_uv = UV * receiver_uv_scale.xy + receiver_uv_offset.xy;
	ALBEDO = receiver_tint.rgb * texture(receiver_color, receiver_uv).rgb;
	ROUGHNESS = receiver_roughness;
	METALLIC = receiver_metallic;
	SPECULAR = receiver_specular;
	if (use_receiver_orm) {
		vec3 orm = texture(receiver_orm, receiver_uv).rgb;
		AO = orm.r;
		ROUGHNESS *= orm.g;
		METALLIC *= orm.b;
	}
	blood_apply_projected_decals(local_position, local_normal_to_view,
		ALBEDO, NORMAL, ROUGHNESS, METALLIC, SPECULAR, AO);
}
