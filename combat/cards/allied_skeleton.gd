extends CharacterBody3D
## A temporary companion maintains its formation slot and commits a real melee swing.

const Slash := preload("res://combat/cards/allied_skeleton_slash.tres")
const Floaters := preload("res://combat/effects/combat_floaters.gd")
const WORLD_LAYER := 1
const STRIKE_CONTACT_PHASE := 8.0 / 30.0
const ROUTE_INTERVAL := 0.22

var owner_player: CharacterBody3D
var target: CharacterBody3D
var formation_offset := Vector3.ZERO
var index := 0
var _cohort: Node3D
var _victim: CharacterBody3D
var _raise_time := 0.0
var _windup := 0.0
var _swing_time := -1.0
var _cooldown := 0.0
var _contact_done := false
var _route_timer := 0.0
var _path := PackedVector3Array()
var _next_waypoint := 0
var _route_goal := Vector3.INF
var _attack_profile: Dictionary = Slash.runtime_profile()
var _strike_duration := maxf(0.05, Slash.recovery)

@onready var _model := $Model


func _ready() -> void:
	_model.configure("normal")
	_model.position.y = -0.60
	set_physics_process(false)


func bind_player(player: CharacterBody3D, cohort: Node3D, slot: int, offset: Vector3) -> void:
	owner_player = player
	_cohort = cohort
	index = slot
	formation_offset = offset
	_cooldown = 0.17 * float(slot)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(owner_player) or not owner_player.combat_enabled or not owner_player.gameplay_enabled:
		return
	if _raise_time < 0.29:
		_raise_time += delta
		_model.position.y = lerpf(-0.60, 0.0, smoothstep(0.0, 0.29, _raise_time))
	_cooldown = maxf(0.0, _cooldown - delta)
	_route_timer -= delta
	var walking := Vector3.ZERO
	if _swing_time >= 0.0:
		_advance_strike(delta)
	elif _victim != null:
		_advance_windup(delta)
	else:
		walking = _choose_movement(delta)
	var acceleration := 17.0 * delta
	velocity.x = move_toward(velocity.x, walking.x, acceleration)
	velocity.z = move_toward(velocity.z, walking.z, acceleration)
	velocity.y = -0.08 if is_on_floor() else velocity.y - 18.0 * delta
	move_and_slide()
	var stride := clampf(_ground(get_real_velocity()).length() / 3.5, 0.0, 1.0)
	var windup_pose := clampf(_windup / Slash.windup, 0.0, 1.0)
	var strike_pose := _swing_time / _strike_duration if _swing_time >= 0.0 else -1.0
	if strike_pose >= 0.0:
		windup_pose = 1.0 - smoothstep(0.0, 0.22, strike_pose)
	_model.animate(delta, stride, windup_pose, strike_pose)


func _choose_movement(delta: float) -> Vector3:
	if _is_hostile_present(target):
		var target_offset := target.global_position - global_position
		var reach := _ground(target_offset).length()
		if reach <= float(_attack_profile.start) and absf(target_offset.y) < 0.75 and _sees_target(target):
			_turn(target_offset, delta)
			if _raise_time >= 0.28 and _cooldown <= 0.0 and _cohort.reserve_strike(self, target):
				_victim = target
				_windup = 0.0
				_contact_done = false
				_emit_cast(&"cast_start", _victim)
			return Vector3.ZERO
		var flank := _ground(global_position - target.global_position).normalized()
		var approach := target.global_position + flank.rotated(Vector3.UP, float(index - 1) * 0.49) * 1.04
		return _steer(approach, 3.85, delta)
	var formation := owner_player.global_position + owner_player.global_basis * formation_offset
	if absf(formation.y - global_position.y) < 0.75 and _ground(formation - global_position).length() < 0.57:
		_turn(-owner_player.global_basis.z, delta)
		return Vector3.ZERO
	var catch_up := clampf(_ground(formation - global_position).length() * 0.30, 0.0, 2.3)
	var owner_speed := _ground(owner_player.get_real_velocity()).length()
	return _steer(formation, maxf(2.5 + catch_up, owner_speed + 0.10), delta)


func _steer(goal: Vector3, speed: float, delta: float) -> Vector3:
	var displacement := goal - global_position
	var direction := _ground(displacement)
	var direct := absf(displacement.y) < 0.35 and not test_move(global_transform, direction)
	if not direct:
		if (_route_timer <= 0.0 or not _route_goal.is_finite() or _route_goal.distance_squared_to(goal) > 2.25):
			_route_timer = ROUTE_INTERVAL
			_route_goal = goal
			_path = _cohort.navigation_route(global_position, goal)
			_next_waypoint = 0
		while _next_waypoint < _path.size():
			var step := _path[_next_waypoint] - global_position
			if _ground(step).length_squared() > 0.13 or absf(step.y) > 0.60:
				break
			_next_waypoint += 1
		if _next_waypoint >= _path.size():
			return Vector3.ZERO
		direction = _ground(_path[_next_waypoint] - global_position)
	var separation: Vector3 = _cohort.separation_for(self)
	var desired := direction.normalized() * minf(speed, direction.length() * 8.0) + separation
	_turn(desired, delta)
	return desired.limit_length(speed)


func _advance_windup(delta: float) -> void:
	if not _is_hostile_present(_victim):
		_emit_cast(&"cast_cancel", _victim)
		_victim = null
		_windup = 0.0
		return
	_windup += delta
	if _windup <= Slash.windup * 0.71:
		_turn(_victim.global_position - global_position, delta)
	if _windup >= Slash.windup:
		_swing_time = 0.0
		_cooldown = Slash.cooldown + float(index) * 0.06
		_contact_done = false
		_emit_cast(&"cast_end", _victim)


func _advance_strike(delta: float) -> void:
	_swing_time += delta
	if not _contact_done and _swing_time >= _strike_duration * STRIKE_CONTACT_PHASE:
		_contact_done = true
		_contact()
	if _swing_time >= _strike_duration:
		_swing_time = -1.0
		_victim = null
		_windup = 0.0


func _contact() -> void:
	if not _is_hostile_present(_victim) or not _sees_target(_victim):
		return
	var body := _victim.global_position - global_position
	var offset := _ground(body)
	if absf(body.y) > 0.90 or offset.length_squared() > Slash.reach * Slash.reach \
			or (-global_basis.z).dot(offset.normalized()) < cos(deg_to_rad(Slash.half_angle)):
		return
	var stats: Dictionary = owner_player.stats
	var power := (float(stats.damage_min) + float(stats.damage_max)) * 0.5
	var point: Vector3 = _victim.aim_point()
	var attack_direction := global_position.direction_to(_victim.global_position)
	var result: Dictionary = _victim.take_hit({"physical": 1.0 + power * Slash.damage_multiplier},
		owner_player, point, attack_direction, {"allied_summon": true})
	if float(result.dealt) <= 0.0:
		return
	Floaters.damage(_victim, point, int(result.amount), false, false)
	var loss := "Physical · %d Life" % int(result.dealt)
	_emit_event(&"damage", _victim, int(result.amount), loss)


func _sees_target(enemy: CharacterBody3D) -> bool:
	var to: Vector3 = enemy.aim_point()
	var from := global_position + Vector3.UP * 1.10
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _is_hostile_present(enemy: CharacterBody3D) -> bool:
	return is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and float(enemy.health) > 0.0


func holds_strike(enemy: CharacterBody3D) -> bool:
	return is_instance_valid(_victim) and _victim == enemy and not _contact_done



func _emit_cast(kind: StringName, enemy: CharacterBody3D) -> void:
	_emit_event(kind, enemy)


func _emit_event(kind: StringName, enemy: CharacterBody3D, amount := 0, detail := "") -> void:
	if not is_instance_valid(owner_player):
		return
	var event := {"kind": kind, "side": &"player", "actor": "Oathbound Skeleton",
		"target": enemy.display_name if is_instance_valid(enemy) else "", "ability_id": Slash.id,
		"ability": Slash.display_name, "description": Slash.description, "detail": detail}
	if amount > 0:
		event["amount"] = amount
	owner_player.combat_event.emit(event)


func _turn(direction: Vector3, delta: float) -> void:
	var flat := _ground(direction)
	if flat.length_squared() > 0.001:
		rotation.y = lerp_angle(rotation.y, atan2(-flat.x, -flat.z), minf(1.0, delta * 13.0))


static func _ground(value: Vector3) -> Vector3:
	return Vector3(value.x, 0.0, value.z)
