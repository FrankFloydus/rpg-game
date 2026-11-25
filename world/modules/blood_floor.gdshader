shader_type spatial;

#include "res://addons/godot-dismemberment/effects/projection/blood_projected_decals.gdshaderinc"

uniform sampler2D stone_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 stone_tint : source_color = vec4(1.0);
uniform float stone_metallic : hint_range(0.0, 1.0);
uniform float world_texture_scale : hint_range(0.0, 2.0);
uniform bool use_vertex_tint = false;
uniform bool world_aligned_stone = false;

varying vec3 receiver_position;
varying mat3 receiver_normal_to_view;
varying vec2 world_floor_position;

void vertex() {
	receiver_position = VERTEX;
	receiver_normal_to_view = MODELVIEW_NORMAL_MATRIX;
	world_floor_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 tile_uv = UV;
	if (world_texture_scale > 0.0) {
		vec2 stone_position = world_aligned_stone ? world_floor_position : receiver_position.xz * vec2(1.0, -1.0);
		tile_uv = stone_position * world_texture_scale;
	}
	ALBEDO = texture(stone_albedo, tile_uv).rgb * stone_tint.rgb;
	if (use_vertex_tint) {
		ALBEDO *= COLOR.rgb;
	}
	ROUGHNESS = 1.0;
	METALLIC = stone_metallic;
	SPECULAR = 0.0;
	blood_apply_projected_decals(receiver_position, receiver_normal_to_view,
		ALBEDO, NORMAL, ROUGHNESS, METALLIC, SPECULAR, AO);
}
