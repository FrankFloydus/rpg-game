extends "res://combat/enemies/ranged_enemy.gd"

const WaxlingScene := preload("res://combat/enemies/wax_brood/waxling.tscn")
const Waxling := preload("res://combat/enemies/wax_brood/waxling.gd")
const KINDLE := "kindle_brood"
const FLARE := "waxling_flare"

const DEFINITION := {
	"id": 22,
	"name": "Wax Brood",
	"level": 4,
	"additional_moves_level": 1,
	"family": "wax_brood",
	"weapon": "fangs",
	"skin": "a17b48",
	"cloth": "4b3220",
	"accent": "f7a950",
	"height": 1.37,
	"width": 0.58,
	"scale": 1.0,
	"part": "cursed_ember",
	"ranged": true,
}

@export_group("Wax Brood")
## Places each hatchling this far ahead of the hive's center, angled to opposite sides.
@export_range(0.8, 3.0, 0.05, "suffix:m") var hatch_distance := 1.08
## Degrees to either side of the brood's aim. A wider spread separates the hatchlings.
@export_range(15.0, 80.0, 1.0, "suffix:°") var hatch_spread := 48.0

var _waxlings: Array[Waxling] = []


func definition() -> Dictionary:
	return DEFINITION


func _ready() -> void:
	super._ready()
	died.connect(_quench_brood)


func _attack_is_ready(move: String) -> bool:
	return super._attack_is_ready(move) and (move != KINDLE or _waxlings.is_empty())


func select_attack(ready_attacks: Array[String]) -> String:
	if ready_attacks.has(KINDLE):
		return KINDLE
	return super.select_attack(ready_attacks)


func _release_attack() -> bool:
	var ability := _cast_definition()
	if ability == null or ability.action_key != KINDLE:
		return super._release_attack()
	if not _has_sight():
		_finish_attack_cast(&"cast_cancel", "Lost line of sight")
		return false
	var seats := _hatch_points()
	if seats.is_empty():
		_commit_attack_cost(ability)
		_finish_attack_cast(&"cast_cancel", "No clear floor for the brood")
		return false
	if not _commit_attack_cost(ability):
		return false
	_strike_time = 0.0
	_finish_attack_cast(&"cast_end")
	var burst_ability := _abilities_by_id[FLARE] as AbilityDefinition
	for seat in seats:
		var hatchling := WaxlingScene.instantiate() as Waxling
		add_child(hatchling)
		hatchling.global_position = seat
		hatchling.release(_player, burst_ability, _log_flare, _flare_hit)
		_waxlings.append(hatchling)
		hatchling.tree_exiting.connect(_remove_hatchling.bind(hatchling))
	return true


func _remove_hatchling(hatchling: Waxling) -> void:
	_waxlings.erase(hatchling)


func _hatch_points() -> Array[Vector3]:
	var result: Array[Vector3] = []
	for side in [-1.0, 1.0]:
		var direction := _windup_toward.rotated(Vector3.UP, deg_to_rad(hatch_spread) * side)
		var candidate := global_position + direction * hatch_distance * _attack_scale()
		var spawn := Waxling.clear_floor(get_world_3d().direct_space_state, global_position, candidate)
		if spawn.is_finite():
			result.append(spawn)
	return result


func _log_flare(event: StringName, detail: String) -> void:
	_emit_cast(event, _combat_ability(FLARE), "Player", detail)


func _flare_hit(waxling: Waxling, origin: Vector3, profile: Dictionary, contacts_player: bool) -> void:
	var landed := false
	if contacts_player and is_instance_valid(_player) and _player.has_method("receive_enemy_hit"):
		var ability := _combat_ability(FLARE)
		ability["unblockable"] = true
		var damage := EnemyStats.hit_damage(_base_damage, float(profile["damage"]))
		if _enraged():
			damage *= 1.31
		landed = _player.receive_enemy_hit(damage, "fire", "", waxling, ability) == true
		if landed:
			on_projectile_hit()
	if _ability_trace.is_valid():
		_ability_trace.call({
			"shape": "disc", "origin": origin + Vector3.UP * ABILITY_TRACE_HEIGHT,
			"direction": Vector3.FORWARD, "reach": profile["reach"], "hit": landed,
		})


func _quench_brood(_enemy: CharacterBody3D) -> void:
	for hatchling in _waxlings:
		hatchling.quench("Wax Brood defeated")
