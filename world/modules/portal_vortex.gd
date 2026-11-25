@tool
extends Node3D
## Shared portal effect. Keep tints on the scene instances so materials stay reusable.

## Main color of the mist, sparks and spill light.
@export_color_no_alpha var tint := Color("#84bfad"):
	set(value):
		tint = value
		if is_node_ready():
			_apply_palette()

## Strength of the light cast onto the surfaces around the portal.
@export_range(0.0, 2.0, 0.01) var light_energy := 0.48:
	set(value):
		light_energy = value
		if is_node_ready():
			_light.light_energy = light_energy

@onready var _veil: MeshInstance3D = $Veil
@onready var _strands: GPUParticles3D = $CurlingStrands
@onready var _sparks: GPUParticles3D = $DriftingMotes
@onready var _mist: GPUParticles3D = $ForegroundMist
@onready var _light: OmniLight3D = $Spill


func _ready() -> void:
	_apply_palette()
	_update_emission()
	visibility_changed.connect(_update_emission)


func _apply_palette() -> void:
	_veil.set_instance_shader_parameter(&"portal_tint", tint)
	_strands.set_instance_shader_parameter(&"portal_tint", tint)
	_sparks.set_instance_shader_parameter(&"portal_tint", tint)
	_mist.set_instance_shader_parameter(&"portal_tint", tint)
	_light.light_color = tint
	_light.light_energy = light_energy


func _update_emission() -> void:
	var active := is_visible_in_tree()
	_strands.emitting = active
	_sparks.emitting = active
	_mist.emitting = active

