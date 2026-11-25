@tool
extends Resource
## Soft rarity color around a model's edges while its original albedo stays visible.

## Cool reflected color of Magic creatures.
@export_color_no_alpha var magic_color := Color("#628fd1")
## Maximum opacity at a Magic creature's silhouette.
@export_range(0.0, 0.6, 0.01) var magic_strength := 0.25
## Tarnished gold reflected color of Rare creatures.
@export_color_no_alpha var rare_color := Color("#c69a4a")
## Maximum opacity at a Rare creature's silhouette.
@export_range(0.0, 0.6, 0.01) var rare_strength := 0.30


func make_layer(rarity: String, surface: StandardMaterial3D, shader: Shader) -> ShaderMaterial:
	var layer := ShaderMaterial.new()
	layer.shader = shader
	layer.render_priority = -1
	layer.next_pass = surface.next_pass
	layer.set_shader_parameter("accent", rare_color if rarity == "rare" else magic_color)
	layer.set_shader_parameter("strength", rare_strength if rarity == "rare" else magic_strength)
	if surface.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		layer.set_shader_parameter("skin_opacity", surface.albedo_color.a)
		if surface.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
			layer.set_shader_parameter("scissor_threshold", surface.alpha_scissor_threshold)
		if surface.albedo_texture != null:
			layer.set_shader_parameter("use_skin_alpha", true)
			layer.set_shader_parameter("skin_alpha", surface.albedo_texture)
			layer.set_shader_parameter("alpha_scale", Vector2(surface.uv1_scale.x, surface.uv1_scale.y))
			layer.set_shader_parameter("alpha_offset", Vector2(surface.uv1_offset.x, surface.uv1_offset.y))
	return layer
