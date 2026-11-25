extends "res://combat/enemies/enemy.gd"

const GroundCast := preload("res://combat/effects/ground_cast.gd")
const BurrowImpact := preload("res://combat/effects/combat_impact.gd")
const TUNNEL := "grave_tunnel"
const MAX_FLOOR_STEP := 0.29

const DEFINITION := {
	"id": 24,
	"name": "Grave Burrower",
	"level": 5,
	"family": "burrower",
	"weapon": "jaw",
	"skin": "665650",
	"cloth": "413738",
	"accent": "af7448",
	"height": 0.91,
	"width": 0.455,
	"scale": 1.0,
	"part": "bone_shard",
	"additional_moves_level": 1,
}

var _submerged := false
var _rise_time := -1.0
var _rest_model_y := 0.0
var _last_dust_distance := 0.0
var _stop_point := Vector3.ZERO
var _exit_footprint: Dictionary
var _tunnel_end_warning: MeshInstance3D


func definition() -> Dictionary:
	return DEFINITION


func _attack_is_ready(move: String) -> bool:
	if move == TUNNEL:
		if not is_inside_tree() or not is_instance_valid(_player):
			return false
		var minimum := float(_attack_profiles[TUNNEL].minimum_distance)
		if _flat(_player.global_position - global_position).length_squared() < minimum * minimum:
			return false
	return super._attack_is_ready(move)


func _update_tactical_goal(distance: float) -> void:
	if _attack_phase == AttackPhase.READY and distance <= float(_attack_profiles[TUNNEL].start) \
			and _attack_is_ready(TUNNEL):
		_move_id = TUNNEL
		_profile = _attack_profiles[TUNNEL]
	super._update_tactical_goal(distance)


func _begin_attack(direction: Vector3) -> void:
	if _move_id == TUNNEL:
		_profile = _profile.duplicate()
		var length := GroundCast.open_length(self, global_position, direction, float(_profile.reach) * _attack_scale(),
			float(_profile.width) * _attack_scale())
		_profile.reach = maxf(0.12, length - 0.18) / _attack_scale()
	super._begin_attack(direction)


func _release_attack() -> bool:
	if not super._release_attack():
		return false
	if _attack_phase == AttackPhase.DASH and _move_id == TUNNEL:
		_rest_model_y = _model.position.y
		_submerged = true
		_model.hide()
		_last_dust_distance = 0.0
		_rise_time = -1.0
		BurrowImpact.contact(get_parent(), global_position, Vector3.UP, &"arrow")
	return true


func _advance_dash(delta: float) -> bool:
	if _move_id != TUNNEL:
		return super._advance_dash(delta)
	if _submerged:
		_tunnel_step(delta)
		return false
	var rise_seconds := float(_profile.rise_seconds)
	_rise_time = minf(_rise_time + delta, rise_seconds)
	_model.position.y = lerpf(_rest_model_y - 0.48, _rest_model_y,
		smoothstep(0.0, rise_seconds, _rise_time))
	Telegraph.set_progress(_tunnel_end_warning, _rise_time / rise_seconds)
	if _rise_time < rise_seconds:
		return false
	_tunnel_end_warning.hide()
	_finish_attack_cast(&"cast_end")
	var landed := GroundCast.target_in_footprint(self, _player, _exit_footprint, _stop_point) \
		and _has_sight() and _damage_player()
	if _ability_trace.is_valid():
		_ability_trace.call({"shape": "disc", "origin": _stop_point + Vector3.UP * ABILITY_TRACE_HEIGHT,
			"direction": _windup_toward, "reach": _exit_footprint.reach, "hit": landed})
	return true


func _tunnel_step(delta: float) -> void:
	var limit := float(_profile.reach) * _attack_scale()
	var motion := _windup_toward * minf(limit - _dash_travel, float(_profile.dash_speed) * delta)
	var ground := GroundCast.floor_point(self, global_position + motion, 0.58)
	if not ground.is_finite() or absf(ground.y - global_position.y) > MAX_FLOOR_STEP:
		_emerge()
		return
	var origin := global_position
	var collision := move_and_collide(motion)
	_dash_travel += maxf(0.0, _windup_toward.dot(global_position - origin))
	if _dash_travel - _last_dust_distance >= 0.63:
		_last_dust_distance = _dash_travel
		BurrowImpact.contact(get_parent(), ground, Vector3.UP, &"arrow")
	if collision != null or _dash_travel >= limit - 0.003:
		_emerge()


func _emerge() -> void:
	_submerged = false
	_stop_point = global_position
	_model.position.y = _rest_model_y - 0.48
	_model.show()
	_rise_time = 0.0
	_turn(_windup_toward, 1.0)
	if _tunnel_end_warning == null:
		_tunnel_end_warning = Telegraph.make_node()
		add_child(_tunnel_end_warning)
	var radius := float(_profile.impact_radius) * _attack_scale()
	_exit_footprint = {"shape": "disc", "reach": radius}
	Telegraph.present(_tunnel_end_warning, _exit_footprint, _stop_point)
	var warning_seconds := TelegraphRules.warning_seconds(float(_profile.rise_seconds), radius, _player)
	_profile.rise_seconds = warning_seconds
	BurrowImpact.contact(get_parent(), _stop_point, Vector3.UP, &"stone")


func _reset_attack() -> void:
	if _submerged or _rise_time >= 0.0:
		_model.position.y = _rest_model_y
		_model.show()
	_submerged = false
	_rise_time = -1.0
	if _tunnel_end_warning != null:
		_tunnel_end_warning.hide()
	super._reset_attack()


func _process(delta: float) -> void:
	super._process(delta)
	if _submerged:
		_bar.hide()
		_title.hide()


func take_hit(damage_by_type: Dictionary, source: Node3D, hit_point := Vector3.INF,
		impact_direction := Vector3.ZERO, weapon_contact: Dictionary = {}) -> Dictionary:
	return super.take_hit({} if _submerged else damage_by_type, source, hit_point, impact_direction, weapon_contact)
