extends "res://combat/enemies/ranged_enemy.gd"

const GroundCast := preload("res://combat/effects/ground_cast.gd")
const Snare := preload("res://combat/effects/rime_snare.tscn")

const DEFINITION := {
	"id": 8,
	"name": "Gutter Marksman",
	"level": 2,
	"family": "rat",
	"weapon": "crossbow",
	"skin": "69584f",
	"cloth": "4a4230",
	"accent": "b9945b",
	"height": 1.52,
	"width": 0.29,
	"scale": 0.80,
	"part": "carrion_eye",
	"ranged": true,
	"additional_moves_level": 1,
}

var _snare_destination := Vector3.INF


func definition() -> Dictionary:
	return DEFINITION


func _begin_attack(direction: Vector3) -> void:
	if _move_id == "rime_snare":
		var point := global_position.lerp(_player.global_position, 0.64)
		_snare_destination = GroundCast.floor_point(self, point)
	super._begin_attack(direction)


func _fire_volley() -> void:
	if _move_id != "rime_snare":
		super._fire_volley()
		return
	if not _snare_destination.is_finite():
		return
	var start := global_position + Vector3.UP * _body_height * 0.63
	var snare := Snare.instantiate() as Node3D
	get_parent().add_child(snare)
	snare.launch(start, _snare_destination, _profile, _player, self, _attack_ability, _attack_rng, _ability_trace)
