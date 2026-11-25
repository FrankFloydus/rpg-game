extends Node3D
## A thrown trap that remains where it landed until it triggers or expires.

const HitEffects := preload("res://combat/effects/hit_effects.gd")
const CombatImpact := preload("res://combat/effects/combat_impact.gd")

var _flight_start := Vector3.ZERO
var _landing := Vector3.ZERO
var _duration := 0.40
var _flight_time := 0.0
var _arm_delay := 0.0
var _lifetime := 0.0
var _radius := 0.0
var _landed := false
var _armed := false
var _ability: Dictionary
var _rng: RandomNumberGenerator
var _source: WeakRef
var _target: WeakRef
var _trace: Callable
var _ray := PhysicsRayQueryParameters3D.new()


func launch(start: Vector3, landing: Vector3, profile: Dictionary, target: Node3D, source: Node3D,
		ability: Dictionary, rng: RandomNumberGenerator, trace: Callable) -> void:
	_flight_start = start
	_landing = landing + Vector3.UP * 0.058
	_duration = clampf(start.distance_to(landing) / float(profile.speed), 0.36, 0.76)
	_arm_delay = maxf(0.20, float(profile.arm_delay))
	_lifetime = float(profile.lifetime)
	_radius = float(profile.trigger_radius)
	_ability = ability
	_rng = rng
	_source = weakref(source)
	_target = weakref(target)
	_trace = trace
	_ray.collision_mask = 1
	_ray.hit_from_inside = true
	global_position = start
	$Frost.hide()


func _physics_process(delta: float) -> void:
	if not _landed:
		_advance_flight(delta)
		return
	if not _armed:
		_arm_delay -= delta
		if _arm_delay > 0.0:
			return
		_armed = true
		$Frost.show()
		CombatImpact.contact(get_parent(), global_position, Vector3.UP, &"arcane_cold")
	_lifetime -= delta
	if _lifetime <= 0.0:
		_finish(false)
		return
	var target := _target.get_ref() as Node3D
	if not is_instance_valid(target):
		_finish(false)
		return
	var offset := target.global_position - global_position
	if absf(offset.y) > 0.47 or Vector2(offset.x, offset.z).length_squared() > _radius * _radius:
		return
	var ability: AbilityDefinition = _ability.get("definition")
	if not ability:
		_finish(false)
		return
	var applied := HitEffects.apply_on_hit(ability.on_hit_effects, target, 0.0, 0.0,
		_source.get_ref(), _ability, _rng)
	if applied:
		CombatImpact.contact(get_parent(), global_position + Vector3.UP * 0.07, Vector3.UP, &"arcane_cold")
	_finish(applied)


func _advance_flight(delta: float) -> void:
	_flight_time = minf(_duration, _flight_time + delta)
	var weight := _flight_time / _duration
	var next := _flight_start.lerp(_landing, weight) + Vector3.UP * sin(weight * PI) * 0.58
	_ray.from = global_position
	_ray.to = next
	var collision := get_world_3d().direct_space_state.intersect_ray(_ray)
	if not collision.is_empty():
		if collision.normal.y < 0.55:
			CombatImpact.contact(get_parent(), collision.position, collision.normal, &"metal")
			queue_free()
			return
		_landing = collision.position + Vector3.UP * 0.058
		weight = 1.0
	global_position = next
	if weight < 1.0:
		rotation += Vector3(4.3, 5.1, 1.7) * delta
		return
	_landed = true
	global_position = _landing
	rotation = Vector3.ZERO
	CombatImpact.contact(get_parent(), _landing, Vector3.UP, &"metal")


func _finish(applied: bool) -> void:
	if _trace.is_valid():
		_trace.call({"shape": "disc", "origin": global_position + Vector3.UP * 0.08,
			"direction": Vector3.FORWARD, "reach": _radius, "hit": applied})
	queue_free()
