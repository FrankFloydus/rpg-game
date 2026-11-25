extends "res://combat/enemies/ranged_enemy.gd"

const DEFINITION := {
	"id": 28, "name": "Sevenfold Maw", "level": 5, "family": "manymouth",
	"weapon": "maws", "height": 1.56, "width": 0.42, "scale": 1.0,
	"part": "ghoul_tongue", "ranged": true,
}
const MOUTH_COUNT := 7

@export_group("Sevenfold Volley")
## Angle between adjacent spittle shots on the ground plane.
@export_range(2.0, 15.0, 0.1, "suffix:°") var spread_per_mouth := 8.0
## Share of the ability's hit damage dealt by one individual shot.
@export_range(0.1, 1.0, 0.01, "suffix:x") var damage_per_mouth := 0.71
var _muzzles: Array[Node3D] = []


func definition() -> Dictionary:
	return DEFINITION


func _ready() -> void:
	super._ready()
	for number in range(1, MOUTH_COUNT + 1):
		var muzzle := _model.find_child("Mouth%d" % number, true, false) as Node3D
		_muzzles.append(muzzle)


func _is_projectile_attack() -> bool:
	return true


func _fire_volley() -> void:
	var middle := float(MOUTH_COUNT - 1) * 0.5
	for index in MOUTH_COUNT:
		var side := float(index) - middle
		var muzzle := _muzzles[index]
		var point := (muzzle.global_position if is_instance_valid(muzzle)
			else to_global(Vector3(side * 0.18, 0.70 + 0.12 * float(index % 3), -0.45)))
		var aim := point.direction_to(_aim_position).rotated(Vector3.UP, deg_to_rad(-side * spread_per_mouth))
		_spawn_projectile(point, aim, damage_per_mouth)
