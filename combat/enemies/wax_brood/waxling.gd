extends "res://world/modules/breakable_prop.gd"
## A short-lived, strikeable creature. It belongs to its hive's attack, never to the encounter roster.

const Telegraph := preload("res://combat/effects/enemy_telegraph.gd")
const TelegraphRules := preload("res://data/telegraph_rules.tres")
const WORLD_LAYER := 1
const MAX_STEP := 0.27
const SAME_FLOOR_HEIGHT := 0.89
const RUNOUT_TIME := 0.65
const CLUTCH_SPACING := 0.64
const HAZARD_GROUP := &"waxling_hazards"

enum Phase { HATCHING, CHASING, BURNING, SPENT }

static var _clearance_shape: SphereShape3D

@onready var _wick: Node3D = $Intact/Wick
@onready var _glow: OmniLight3D = $Glow
@onready var _sparks: GPUParticles3D = $Sparks

var _phase := Phase.HATCHING
var _player: Node3D
var _log: Callable
var _hit: Callable
var _time := 0.0
var _warning_seconds := 0.0
var _settings: Dictionary
var _footprint: Dictionary
var _warning: MeshInstance3D
var _clutch_group: StringName


func release(player: Node3D, ability: AbilityDefinition, log_event: Callable, hit: Callable) -> void:
	_player = player
	_settings = ability.runtime_profile()
	_footprint = {"shape": "disc", "reach": _settings["flare_radius"], "damage": _settings["damage"]}
	_log = log_event
	_hit = hit
	_time = float(_settings["wake_seconds"])
	_clutch_group = StringName("waxlings_%d" % get_parent().get_instance_id())
	add_to_group(_clutch_group)
	_intact.scale = Vector3.ONE * 0.58
	_wick.hide()


static func clear_floor(space: PhysicsDirectSpaceState3D, previous: Vector3, candidate: Vector3) -> Vector3:
	var cast := PhysicsRayQueryParameters3D.create(candidate + Vector3.UP * 0.52,
			candidate - Vector3.UP * 0.52, WORLD_LAYER)
	var ground := space.intersect_ray(cast)
	if ground.is_empty() or (ground.normal as Vector3).y < 0.68:
		return Vector3.INF
	var point: Vector3 = ground.position
	if absf(point.y - previous.y) > MAX_STEP:
		return Vector3.INF
	if not _clear_line(space, previous + Vector3.UP * 0.40, point + Vector3.UP * 0.40):
		return Vector3.INF
	if _clearance_shape == null:
		_clearance_shape = SphereShape3D.new()
		_clearance_shape.radius = 0.25
	var clearance := PhysicsShapeQueryParameters3D.new()
	clearance.shape = _clearance_shape
	clearance.collision_mask = WORLD_LAYER
	clearance.transform.origin = point + Vector3.UP * 0.28
	return point if space.intersect_shape(clearance, 1).is_empty() else Vector3.INF


static func _clear_line(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, WORLD_LAYER)).is_empty()


func _physics_process(delta: float) -> void:
	if _phase == Phase.SPENT or _settings.is_empty():
		return
	if not is_instance_valid(_player):
		quench("Target left")
		return
	_time -= delta
	match _phase:
		Phase.HATCHING:
			var growth := smoothstep(0.0, 1.0, 1.0 - _time / float(_settings["wake_seconds"]))
			_intact.scale = Vector3.ONE * lerpf(0.58, 1.0, growth)
			_glow.light_energy = lerpf(0.13, 0.27, growth)
			if _time <= 0.0:
				_phase = Phase.CHASING
				_time = float(_settings["chase_seconds"])
				_wick.show()
		Phase.CHASING:
			if _time <= 0.0:
				quench("Waxling cooled")
			else:
				_chase(delta)
		Phase.BURNING:
			var progress := 1.0 - _time / _warning_seconds
			Telegraph.set_progress(_warning, progress)
			_glow.light_energy = lerpf(0.34, 0.82, smoothstep(0.08, 0.95, progress))
			if _time <= 0.0:
				_resolve()


func _chase(delta: float) -> void:
	var toward := _player.global_position - global_position
	if absf(toward.y) > SAME_FLOOR_HEIGHT:
		return
	toward.y = 0.0
	var space := get_world_3d().direct_space_state
	if not _clear_line(space, global_position + Vector3.UP * 0.37,
			_player.global_position + Vector3.UP * 0.55):
		return
	if toward.length_squared() <= pow(float(_settings["arm_distance"]), 2):
		if _can_light_fuse():
			_light_fuse()
		return
	var heading := toward.normalized() + _clutch_spacing()
	var travel := heading.normalized() * float(_settings["chase_speed"]) * delta
	var step := clear_floor(space, global_position, global_position + travel)
	if step.is_finite():
		global_position = step
		_intact.rotation.y = atan2(-travel.x, -travel.z)
		_intact.rotation.x = sin(_time * 18.0) * 0.05


func _clutch_spacing() -> Vector3:
	var steering := Vector3.ZERO
	for sibling: Node3D in get_tree().get_nodes_in_group(_clutch_group):
		if sibling == self:
			continue
		var offset := global_position - sibling.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > 0.001 and distance < CLUTCH_SPACING:
			steering += offset * (1.0 - distance / CLUTCH_SPACING) / distance
	return steering


func _can_light_fuse() -> bool:
	for active: Node3D in get_tree().get_nodes_in_group(HAZARD_GROUP):
		var offset := active.global_position - global_position
		if active.get_parent() == get_parent():
			return false
		if absf(offset.y) < SAME_FLOOR_HEIGHT:
			offset.y = 0.0
			if offset.length() < float(_footprint["reach"]) + active.flare_radius():
				return false
	return true


func _light_fuse() -> void:
	_phase = Phase.BURNING
	_intact.rotation.x = 0.0
	add_to_group(HAZARD_GROUP)
	_warning_seconds = TelegraphRules.warning_seconds(float(_settings["windup"]),
			Telegraph.escape_distance(_footprint), _player)
	_time = _warning_seconds
	_warning = Telegraph.make_node()
	add_child(_warning)
	Telegraph.present(_warning, _footprint, global_position)
	_log.call(&"cast_start", "")


func flare_radius() -> float:
	return float(_footprint["reach"])


func _resolve() -> void:
	var origin := global_position
	var target := _player.global_position
	var contacts := absf(target.y - origin.y) <= SAME_FLOOR_HEIGHT \
		and Telegraph.contains(_footprint, origin, Vector3.FORWARD, target) \
		and _clear_line(get_world_3d().direct_space_state, origin + Vector3.UP * 0.37, target + Vector3.UP * 0.55)
	_finish()
	_log.call(&"cast_end", "")
	_hit.call(self, origin, _footprint, contacts)
	_sparks.emitting = true
	_glow.light_energy = 2.15
	var fade := create_tween()
	fade.tween_property(_glow, "light_energy", 0.0, 0.27)


func break_from(direction: Vector3, point := Vector3.INF, normal := Vector3.ZERO) -> void:
	if _phase == Phase.SPENT:
		return
	if point.is_finite():
		CombatImpact.contact(get_parent() as Node3D, point,
				-direction if normal.is_zero_approx() else normal, &"wax")
	quench("Waxling shattered")
	_sparks.speed_scale = 1.5
	_sparks.emitting = true


func quench(reason: String) -> void:
	if _phase == Phase.SPENT:
		return
	if _phase == Phase.BURNING:
		_log.call(&"cast_cancel", reason)
	_finish()


func _finish() -> void:
	_phase = Phase.SPENT
	remove_from_group(_clutch_group)
	if is_in_group(HAZARD_GROUP):
		remove_from_group(HAZARD_GROUP)
	if is_instance_valid(_warning):
		_warning.hide()
	_disable_intact()
	_glow.light_energy = 0.0
	get_tree().create_timer(RUNOUT_TIME, false, true).timeout.connect(queue_free)
