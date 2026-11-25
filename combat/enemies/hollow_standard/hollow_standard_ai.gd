extends "res://combat/enemies/enemy.gd"

const RALLY := "standard_rally"
const StandardRage := preload("res://combat/effects/standard_rage.tres")
const DEFINITION := {
	"id": 23, "name": "Hollow Standard", "level": 5, "family": "hollow_standard",
	"weapon": "standard", "height": 2.36, "width": 0.37, "scale": 1.0, "part": "wraith_dust",
	"additional_moves_level": 1,
}

@export_group("Battle Standard")
## Radius within which the standard can rally living members of its own pack.
@export_range(1.0, 20.0, 0.1, "suffix:m") var rally_radius := 6.3
## Maximum number of nearby allies affected by each rally.
@export_range(1, 10, 1) var rally_targets := 3


func definition() -> Dictionary:
	return DEFINITION


func select_attack(ready_attacks: Array[String]) -> String:
	if RALLY in ready_attacks and not _rally_allies().is_empty():
		return RALLY
	for id in ready_attacks:
		if id != RALLY:
			return id
	return ready_attacks.front()


func _attack_is_ready(move: String) -> bool:
	# Setup picks an attack before the actor has joined a pack.
	return super._attack_is_ready(move) and (move != RALLY or not _rally_allies().is_empty())


func _rally_allies() -> Array[CharacterBody3D]:
	var allies: Array[CharacterBody3D] = []
	if not is_inside_tree() or _pack_group.is_empty():
		return allies
	for ally: Node3D in get_tree().get_nodes_in_group(_pack_group):
		if ally == self or ally.is_cocoon() or global_position.distance_squared_to(ally.global_position) > rally_radius * rally_radius:
			continue
		var ray := PhysicsRayQueryParameters3D.create(aim_point(), ally.aim_point(), WORLD_LAYER)
		if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			allies.append(ally)
			if allies.size() >= rally_targets:
				break
	return allies


func _fire_volley() -> void:
	if _move_id != RALLY:
		super._fire_volley()
		return
	for ally in _rally_allies():
		ally.receive_combat_effect(StandardRage, StandardRage.duration, 1.0, self, _attack_ability)
