@tool
extends StaticBody3D
## An unlimited, single-resource refill station for the Training Ground.

@export var restores_mana := false:
	set(value):
		restores_mana = value
		if is_node_ready():
			_apply_appearance()

var interaction_point := Vector3.UP * 1.30
var margin := 0.58
var text: String:
	get:
		return "Refill " + resource_label()
var tint: Color:
	get:
		return Color("8bcfff") if restores_mana else Color("ffa787")


func _ready() -> void:
	_apply_appearance()


func pick_available() -> bool:
	return true


func resource_label() -> String:
	return "Mana" if restores_mana else "Life"


func _apply_appearance() -> void:
	$Label.text = resource_label() + " Well"
	$Label.modulate = tint
	$Glow.light_color = tint
	$Water.material_override.set_shader_parameter(&"liquid_tint", tint)
