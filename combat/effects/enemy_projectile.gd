extends Node3D

const Impacts := preload("res://combat/effects/combat_impact.gd")
const MAGIC_STYLE := {"fire": 1, "cold": 2, "lightning": 3, "poison": 4}
const TRAIL_FADE_MARGIN := 0.04

var recycler := Callable()
var _direction := Vector3.ZERO
var _speed := 0.0
var _damage := 0.0
var _type := ""
var _status := ""
var _ability: Dictionary = {}
var _source: WeakRef
var _player: WeakRef
var _travel_left := 0.0
var _ray := PhysicsRayQueryParameters3D.new()
var _trace := Callable()
var _trace_origin := Vector3.ZERO
var _fade_remaining := 0.0

@onready var _arrow: Node3D = $Arrow
@onready var _bolt: Node3D = $Bolt
@onready var _core: MeshInstance3D = $Bolt/Core
@onready var _trail: GPUParticles3D = $Bolt/Trail


func _ready() -> void:
	set_physics_process(false)


func in_flight() -> bool:
	return _speed > 0.0

func launch(start: Vector3, target: Vector3, speed: float, damage: float, damage_type: String, status: String,
		source: Node3D, player: Node3D, color: Color, travel_limit := 20.0, ability: Dictionary = {},
		trace: Callable = Callable()) -> void:
	global_position = start
	show()
	set_physics_process(true)
	_trace_origin = start
	_trace = trace
	_direction = (target - start).normalized()
	if _direction == Vector3.ZERO:
		_direction = Vector3.FORWARD
	_speed = speed
	_travel_left = maxf(0.0, travel_limit)
	_ray.collision_mask = 3
	_ray.hit_from_inside = true
	_damage = damage
	_type = damage_type
	_status = status
	_ability = ability
	_source = weakref(source)
	_player = weakref(player)
	var aim_up := Vector3.FORWARD if absf(_direction.dot(Vector3.UP)) > 0.99 else Vector3.UP
	look_at(start + _direction, aim_up)
	_build_model(color)

func _physics_process(delta: float) -> void:
	if not in_flight():
		_fade_remaining -= delta
		if _fade_remaining <= 0.0:
			_return_or_free()
		return
	var distance := minf(_travel_left, _speed * delta)
	if distance <= 0.0:
		if _travel_left <= 0.0:
			_end_flight(global_position, false)
		return
	var old := global_position
	var next := old + _direction * distance
	_ray.from = old
	_ray.to = next
	var collision := get_world_3d().direct_space_state.intersect_ray(_ray)
	if not collision.is_empty():
		var landed := false
		var player: Node3D = _player.get_ref()
		if is_instance_valid(player) and collision.collider == player and player.has_method("receive_enemy_hit"):
			var source: Node3D = _source.get_ref()
			landed = player.receive_enemy_hit(_damage, _type, _status, source, _ability) == true
			if landed and is_instance_valid(source):
				source.on_projectile_hit()
		elif collision.collider is StaticBody3D:
			var surface := &"arrow" if _type == "physical" else StringName("arcane_" + _type)
			Impacts.contact(get_parent() as Node3D, collision.position, collision.normal, surface)
		_end_flight(collision.position, landed)
		return
	global_position = next
	_travel_left -= distance
	if _travel_left <= 0.0:
		_end_flight(global_position, false)

func _end_flight(point: Vector3, hit: bool) -> void:
	if _trace.is_valid():
		_trace.call({"shape": "line", "origin": _trace_origin, "end": point, "hit": hit})
	_retire_visual()

func _build_model(color: Color) -> void:
	var physical := _type == "physical"
	_arrow.visible = physical
	_bolt.visible = not physical
	_core.visible = not physical
	if physical:
		_trail.emitting = false
		return
	_core.set_instance_shader_parameter(&"bolt_tint", color)
	var element: int = MAGIC_STYLE.get(_type, 0)
	_core.set_instance_shader_parameter(&"element", element)
	_trail.set_instance_shader_parameter(&"element", element)
	var process := _trail.process_material as ParticleProcessMaterial
	process.color = color
	_trail.restart()
	_trail.emitting = true


func _retire_visual() -> void:
	_direction = Vector3.ZERO
	_speed = 0.0
	_travel_left = 0.0
	_damage = 0.0
	_type = ""
	_status = ""
	_ability = {}
	_source = null
	_player = null
	_trace = Callable()
	_trace_origin = Vector3.ZERO
	_ray.from = Vector3.ZERO
	_ray.to = Vector3.ZERO
	_arrow.hide()
	_core.hide()
	if _trail.emitting:
		# The particles use world space. Keep them alive without the core until they dissipate.
		_trail.emitting = false
		_fade_remaining = _trail.lifetime + TRAIL_FADE_MARGIN
	else:
		_return_or_free()


func _return_or_free() -> void:
	_fade_remaining = 0.0
	hide()
	_bolt.hide()
	set_physics_process(false)
	if recycler.is_valid():
		recycler.call(self)
	else:
		queue_free()
