shader_type spatial;
render_mode cull_disabled, depth_draw_never, shadows_disabled, diffuse_burley, specular_schlick_ggx;

// The smoke flipbook is an sRGB color texture whose red channel supplies density.
#define BLOOD_SMOKE_SRGB
// Godot reads uniform descriptions from this shader before expanding its includes.
#ifdef BLOOD_INSPECTOR_DOCUMENTATION
/** Render as mist (0), a sheet (1), a drop (2), or a clot (3). In Niagara materials, 0 selects smoke and the other values select liquid. */
uniform int particle_kind;
/** Density texture for legacy mist and elongated sheets. */
uniform sampler2D sprite_mask;
/** Density texture for legacy camera-facing sheets. */
uniform sampler2D radial_mask;
/** Surface normal texture for legacy elongated sheets. */
uniform sampler2D sheet_normal_map;
/** Surface normal texture for legacy camera-facing sheets. */
uniform sampler2D radial_normal_map;
/** Strength of normal mapping in the legacy liquid material. */
uniform float normal_strength;
/** Base roughness of legacy liquid particles. Lower values give sharper highlights. */
uniform float wet_roughness;
/** Use the Niagara-style material and emitter parameters. */
uniform bool source_graph;
/** Use dithered coverage for the masked liquid. Use the Masked Draw shader for depth writing. */
uniform bool source_masked;
/** Density of the liquid sheet or droplet, or the 8 by 8 smoke flipbook. The red channel supplies opacity. */
uniform sampler2D source_alpha_map;
/** Normal texture that steers the baked liquid reflection. */
uniform sampler2D source_normal_map;
/** Sample Source Normal Map Anisotropic in place of the standard normal map. */
uniform bool source_normal_anisotropic;
/** Optional anisotropically filtered normal texture for oblique views. */
uniform sampler2D source_normal_map_anisotropic;
/** Repeating noise texture that warps the liquid UVs. */
uniform sampler2D source_distortion_map;
/** Baked highlight texture sampled using the liquid normal. */
uniform sampler2D source_reflection_map;
/** Linear RGB for thin liquid or for the smoke tint. */
uniform vec3 source_main_color;
/** Linear RGB for dense liquid. */
uniform vec3 source_secondary_color;
/** Linear RGB tint multiplied into the baked highlight. */
uniform vec3 source_specular_tint;
/** Strength of the liquid UV warp. Zero keeps the original UVs. */
uniform float source_distort_intensity;
/** Number of noise repetitions across the liquid sprite. */
uniform float source_distort_tiling;
/** UV scroll speed of the liquid distortion noise. */
uniform vec2 source_distort_speed;
/** Brightness multiplier for the baked liquid highlight. */
uniform float source_specular_value;
/** Exponent applied to the reflection texture. Larger values suppress dim highlights. */
uniform float source_specular_power;
/** Density range over which the liquid transitions from transparent to opaque. */
uniform float source_softness;
/** Density exponent that shapes the blend between thin and dense liquid colors. */
uniform float source_power;
/** How far the normal shifts the reflection lookup away from its center. */
uniform float source_normal_strength;
/** Brightness multiplier on low-density liquid. A value of 1 leaves its brightness unchanged. */
uniform float source_darkness;
/** Rotation of the liquid textures around the sprite center, in turns. */
uniform float source_rotation;
/** Use Source Test Dissolve as a fixed threshold for material preview. */
uniform bool source_dissolve_test;
/** Fixed dissolve threshold used when Source Dissolve Test is enabled. */
uniform float source_test_dissolve;
/** Repeating texture that breaks up the smoke density. */
uniform sampler2D source_smoke_detail;
/** Camera depth texture used to fade smoke near opaque geometry. */
uniform sampler2D source_scene_depth;
/** Distance in metres over which smoke fades as it approaches opaque geometry. */
uniform float source_smoke_fade_distance;
/** Scale of the randomized smoke detail tiles. */
uniform float source_smoke_detail_randomization;
/** Strength of the smoke detail contribution to opacity. */
uniform float source_smoke_detail_opacity;
/** Exponent applied to smoke density before opacity and depth fade. */
uniform float source_smoke_power;
/** Enable the emitter's dissolve curve. The effect sets this when the curve is assigned. */
uniform bool has_dissolve_curve;
/** Enable the emitter's opacity curve. The effect sets this when the curve is assigned. */
uniform bool has_alpha_curve;
/** Enable the emitter's width curve. The effect sets this when the curve is assigned. */
uniform bool has_size_x_curve;
/** Enable the emitter's height curve. The effect sets this when the curve is assigned. */
uniform bool has_size_y_curve;
/** Enable the emitter's speed interpolation curve. The effect sets this when the curve is assigned. */
uniform bool has_speed_scale_curve;
/** Texture that sets the dissolve threshold over normalized particle age. */
uniform sampler2D source_dissolve_curve;
/** Texture that multiplies opacity over normalized particle age. */
uniform sampler2D source_alpha_curve;
/** Texture that scales sprite width over normalized particle age. */
uniform sampler2D source_size_x_curve;
/** Texture that scales sprite height over normalized particle age. */
uniform sampler2D source_size_y_curve;
/** Texture that remaps normalized speed before size interpolation. */
uniform sampler2D source_speed_scale_curve;
/** Width and height multipliers at zero speed. */
uniform vec2 source_speed_scale_min;
/** Width and height multipliers at or above the speed threshold. */
uniform vec2 source_speed_scale_max;
/** Speed in m/s at which the maximum size multiplier is reached. Zero disables speed scaling. */
uniform float source_speed_scale_threshold;
/** Offset toward the camera in metres. Negative values move the sprite away. */
uniform float source_camera_offset;
/** How far the smoke flipbook advances over a particle's lifetime. */
uniform float source_smoke_frame_span;
/** Sprite anchor in normalized UV coordinates. (0.5, 0.5) centers it. */
uniform vec2 source_sprite_pivot;
/** Perspective coverage mode. 0 is automatic, 1 is disabled, 2 adjusts geometry, and 3 adjusts geometry and RGBA. */
uniform int source_pixel_coverage;
/** Strength of the subpixel color and opacity compensation. */
uniform float source_pixel_coverage_blend;
#endif

#include "res://addons/godot-dismemberment/effects/blood_gpu_draw.gdshaderinc"

void light() {
	// First two spherical-harmonic bands of the source's directional volume lighting.
	float irradiance = max(0.0, 0.25 + 0.5 * dot(NORMAL, LIGHT));
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * irradiance / PI;
}
