extends Node3D
## The committed disc stays at the same ground point throughout the arc, burst and pool.

const Telegraph := preload("res://combat/effects/enemy_telegraph.gd")
const SporeLob := preload("res://combat/abilities/mire_spore_lob.gd")
const WORLD_LAYER := 1
const CONTACT_HEIGHT := 0.78

var _spore: SporeLob
var _caster: Node3D
var _player: Node3D
var _ability: Dictionary
var _trace: Callable
var _start: Vector3
var _landing: Vector3
var _area: Dictionary
var _warning: MeshInstance3D
var _flight_seconds := 0.0
var _warning_start := 0.0
var _since_launch := 0.0
var _since_impact := 0.0
var _next_tick := 0.0
var _damage := 0.0
var _airborne := true

@onready var _pod: Node3D = $Pod
@onready var _wake: GPUParticles3D = $Pod/Wake
@onready var _pool: MeshInstance3D = $GroundPool
@onready var _motes: GPUParticles3D = $PoolMotes


func _ready() -> void:
	set_physics_process(false)


func launch(spore: SporeLob, start: Vector3, center: Vector3, flight: float, warning_start: float,
		damage: float, caster: Node3D, player: Node3D, ability: Dictionary, trace: Callable) -> void:
	_spore = spore
	_caster = caster
	_player = player
	_ability = ability.duplicate()
	_trace = trace
	_start = start
	_landing = center + Vector3.UP * 0.13
	_flight_seconds = flight
	_warning_start = warning_start
	_damage = damage
	var radius: float = spore.pool_radius
	_area = {"shape": "disc", "reach": radius}
	global_position = center
	_pod.global_position = start
	_wake.emitting = true
	_pool.scale = Vector3(radius, radius, 1.0)
	_motes.process_material.emission_ring_radius = radius * 0.86
	_motes.process_material.emission_ring_inner_radius = radius * 0.15
	_warning = Telegraph.make_node()
	add_child(_warning)
	Telegraph.present(_warning, _area, global_position)
	Telegraph.set_progress(_warning, _warning_start)
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player):
		queue_free()
		return
	if _player.get("gameplay_enabled") == false:
		return
	if _airborne:
		_advance_flight(delta)
	else:
		_advance_pool(delta)


func _advance_flight(delta: float) -> void:
	_since_launch += delta
	var phase := clampf(_since_launch / _flight_seconds, 0.0, 1.0)
	var next := _start.lerp(_landing, phase) + Vector3.UP * (4.0 * phase * (1.0 - phase) * _spore.arc_height)
	var obstruction := PhysicsRayQueryParameters3D.create(_pod.global_position, next, WORLD_LAYER)
	if not get_world_3d().direct_space_state.intersect_ray(obstruction).is_empty():
		queue_free()
		return
	_pod.global_position = next
	_pod.rotate_z(delta * 6.0)
	Telegraph.set_progress(_warning, lerpf(_warning_start, 1.0, phase))
	if phase >= 1.0:
		_land()


func _land() -> void:
	_airborne = false
	_warning.hide()
	_pod.hide()
	_wake.emitting = false
	_pool.show()
	_motes.emitting = true
	_next_tick = _spore.tick_interval
	var hit := _apply_contact(_damage)
	if _trace.is_valid():
		_trace.call({"shape": "disc", "origin": global_position + Vector3.UP * 0.075,
			"direction": Vector3.FORWARD, "reach": _spore.pool_radius, "hit": hit})


func _advance_pool(delta: float) -> void:
	_since_impact += delta
	if _since_impact >= _spore.pool_seconds:
		queue_free()
		return
	if _since_impact >= _next_tick:
		_apply_contact(_damage * _spore.tick_damage_multiplier)
		_next_tick += _spore.tick_interval
	var remaining: float = _spore.pool_seconds - _since_impact
	_pool.set_instance_shader_parameter("pool_density", smoothstep(0.0, 0.42, remaining))
	if remaining <= 0.42:
		_motes.emitting = false


func _apply_contact(damage: float) -> bool:
	if _player.get("combat_enabled") == false:
		return false
	var point := _player.global_position
	if absf(point.y - global_position.y) > CONTACT_HEIGHT \
			or not Telegraph.contains(_area, global_position, Vector3.FORWARD, point):
		return false
	var clearance := Vector3.UP * 0.22
	if global_position.distance_squared_to(point) > 0.0001:
		var line := PhysicsRayQueryParameters3D.create(global_position + clearance, point + clearance, WORLD_LAYER)
		if not get_world_3d().direct_space_state.intersect_ray(line).is_empty():
			return false
	var source := _caster if is_instance_valid(_caster) else null
	return _player.receive_ground_damage(damage, "poison", source, _ability) == true
