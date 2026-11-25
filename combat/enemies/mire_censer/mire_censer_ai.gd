extends "res://combat/enemies/ranged_enemy.gd"

const SporeLob := preload("res://combat/abilities/mire_spore_lob.gd")
const PodScene := preload("res://combat/effects/mire_spore_pod.tscn")
const DEFINITION := {
	"id": 20,
	"name": "Mire Censer",
	"level": 3,
	"family": "mire",
	"weapon": "",
	"skin": "746559",
	"cloth": "393530",
	"accent": "a8ad62",
	"height": 1.26,
	"width": 0.61,
	"scale": 1.0,
	"part": "venom_sac",
	"ranged": true,
}

var _lob_center := Vector3.INF
var _lob_travel := 0.0
var _lob_area: Dictionary = {}


func definition() -> Dictionary:
	return DEFINITION


func _begin_attack(direction: Vector3) -> void:
	_lob_center = Vector3.INF
	super._begin_attack(direction)
	var spore := _cast_definition() as SporeLob
	if spore == null:
		return
	_lob_center = _find_landing_floor(_target.global_position)
	if not _lob_center.is_finite():
		return
	_lob_area = {"shape": "disc", "reach": spore.pool_radius}
	_lob_travel = _travel_seconds(spore, _muzzle())
	_floor_warning_locked = true
	_windup_total = TelegraphRules.warning_seconds(_windup_total / _attack_speed_factor(),
		Telegraph.escape_distance(_lob_area), _player)
	_attack_remaining = _windup_total
	_attack_ability["unblockable"] = true
	if _attack_warning == null:
		_attack_warning = Telegraph.make_node()
		add_child(_attack_warning)
	Telegraph.present(_attack_warning, _lob_area, _lob_center)


func _find_landing_floor(point: Vector3) -> Vector3:
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.26,
		point - Vector3.UP * 1.65, WORLD_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.68:
		return Vector3.INF
	return hit.position


func _muzzle() -> Vector3:
	return global_position + Vector3.UP * _body_height * 0.69 + _windup_toward * 0.34


func _profile_warns_on_floor() -> bool:
	return not (_cast_definition() is SporeLob) and super._profile_warns_on_floor()


func _travel_seconds(spore: SporeLob, start: Vector3) -> float:
	return maxf(0.26, start.distance_to(_lob_center) / maxf(0.1, spore.flight_speed * _projectile_speed_multiplier))


func _set_warning_progress(fraction: float) -> void:
	if _cast_definition() is SporeLob and _lob_center.is_finite():
		var attack_duration := _windup_total + _lob_travel
		Telegraph.set_progress(_attack_warning, fraction * (_windup_total / attack_duration))
		return
	super._set_warning_progress(fraction)


func _release_attack() -> bool:
	var spore := _cast_definition() as SporeLob
	if spore == null:
		return super._release_attack()
	if not _lob_center.is_finite():
		_finish_attack_cast(&"cast_cancel", "No floor for the pod")
		return false
	if not _commit_attack_cost(spore):
		return false
	_strike_time = 0.0
	_finish_attack_cast(&"cast_end")
	var launch := _muzzle()
	var pod := PodScene.instantiate() as Node3D
	get_parent().add_child(pod)
	var flight := _travel_seconds(spore, launch)
	pod.launch(spore, launch, _lob_center, flight, _windup_total / (_windup_total + flight),
		_attack_damage(), self, _player, _attack_ability, _ability_trace)
	_attack_warning.hide()
	return true
