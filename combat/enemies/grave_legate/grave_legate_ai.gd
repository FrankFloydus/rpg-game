extends "res://combat/enemies/ranged_enemy.gd"

signal summon_requested(enemy: Node3D)

const LEVY := "raise_the_levy"
const LevyVisual := preload("res://combat/enemies/grave_legate/levy_fx.tscn")
const DEFINITION := {
	"id": 25,
	"name": "Grave Legate",
	"level": 3,
	"family": "grave_legate",
	"weapon": "unarmed",
	"skin": "807262",
	"cloth": "4a332b",
	"accent": "c2a976",
	"height": 1.77,
	"width": 0.29,
	"scale": 1.0,
	"part": "bone_shard",
	"ranged": true,
	"spawn_in_pool": false,
	"proper_name": true,
}

var _spent := false
var _levy_visual: GPUParticles3D


func definition() -> Dictionary:
	return DEFINITION


func setup(player: Node3D, spawn_level: int, rank: String, rng: RandomNumberGenerator,
		route: Callable = Callable(), ability_details: Callable = Callable(),
		selected_affixes: Array[String] = [], depth_multiplier := 1.0) -> void:
	super.setup(player, spawn_level, rank, rng, route, ability_details, selected_affixes, depth_multiplier)
	max_health = 1.0
	health = 1.0
	# This invader exists to raise the levy. Elite side effects must not turn it into a damage dealer.
	affixes.clear()


func _attack_is_ready(move: String) -> bool:
	return not _spent and super._attack_is_ready(move)


func _sample_perception() -> void:
	if not _attack_cast_open:
		super._sample_perception()


func _begin_attack(direction: Vector3) -> void:
	super._begin_attack(direction)
	if _levy_visual == null:
		_levy_visual = LevyVisual.instantiate() as GPUParticles3D
		add_child(_levy_visual)
	_levy_visual.emitting = true


func _reset_attack() -> void:
	super._reset_attack()
	if is_instance_valid(_levy_visual):
		_levy_visual.emitting = false


func _release_attack() -> bool:
	var ability := _cast_definition()
	if ability == null or ability.action_key != LEVY:
		return false
	if not _commit_attack_cost(ability):
		return false
	_spent = true
	_finish_attack_cast(&"cast_end")
	summon_requested.emit(self)
	_depart.call_deferred()
	return true


func _depart() -> void:
	if not _dead and is_inside_tree():
		_die(null)
	queue_free()
