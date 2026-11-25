extends Node3D
## A thrown web that snags the player only on the first physical impact.

const StatusCatalog = preload("res://combat/effects/status_catalog.gd")

const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const DEFAULT_ROOT_SECONDS: float = StatusCatalog.ROOTED["duration"]
const IMPACT_OFFSET := 0.032
const MISSED_WEB_LIFETIME := 0.72
const SilkScene = preload("res://combat/effects/cobweb_silk.tscn")

static var _windup_silk: StandardMaterial3D

var _target: WeakRef
var _ability: Dictionary = {}
var _root_seconds := DEFAULT_ROOT_SECONDS
var _ray := PhysicsRayQueryParameters3D.new()
var _direction := Vector3.ZERO
var _speed := 0.0
var _range_left := 0.0
var _miss_time := 0.0
var _fade_time := 0.0
var _snared := false
var _web: MeshInstance3D
var _trace := Callable()
var _trace_origin := Vector3.ZERO


func launch(start: Vector3, target: Vector3, speed: float, source: Node3D, player: Node3D,
		travel_limit := 14.0, ability: Dictionary = {}, root_seconds := DEFAULT_ROOT_SECONDS,
		trace: Callable = Callable()) -> void:
	global_position = start
	_trace_origin = start
	_trace = trace
	_direction = (target - start).normalized()
	if _direction.is_zero_approx():
		_direction = Vector3.FORWARD
	_speed = maxf(1.0, speed)
	_range_left = maxf(0.0, travel_limit)
	_target = weakref(player)
	_ability = ability
	_root_seconds = root_seconds
	_ray.collision_mask = WORLD_LAYER | PLAYER_LAYER
	_ray.hit_from_inside = true
	if is_instance_valid(source) and source is CollisionObject3D:
		_ray.exclude = [source.get_rid()]
	_face(_direction)
	_web = $Silk
	reset_physics_interpolation()


static func windup_visual() -> Node3D:
	var visual := SilkScene.instantiate() as MeshInstance3D
	if _windup_silk == null:
		_windup_silk = visual.material_override.duplicate()
		_windup_silk.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_windup_silk.billboard_keep_scale = true
	visual.material_override = _windup_silk
	return visual


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_web):
		return
	if _speed == 0.0:
		_update_landed_web(delta)
		return
	var travel := minf(_range_left, _speed * delta)
	var previous := global_position
	var next := previous + _direction * travel
	_ray.from = previous
	_ray.to = next
	var collision := get_world_3d().direct_space_state.intersect_ray(_ray)
	if not collision.is_empty():
		_impact(collision)
		return
	global_position = next
	_web.rotation.z += delta * 4.3
	_range_left -= travel
	if _range_left <= 0.0:
		_finish_trace(next, false)
		var ground := PhysicsRayQueryParameters3D.create(next, next + Vector3.DOWN * 5.0, WORLD_LAYER)
		var hit := get_world_3d().direct_space_state.intersect_ray(ground)
		if hit.is_empty():
			_land(next, -_direction)
		else:
			_land(hit.position, hit.normal)


func _impact(collision: Dictionary) -> void:
	var player: Node3D = _target.get_ref() if _target else null
	if is_instance_valid(player) and collision.collider == player and player.has_method("apply_cobweb_root"):
		if player.apply_cobweb_root(_ability, _root_seconds):
			_land(player.global_position, Vector3.UP)
			_snared = true
			_finish_trace(collision.position, true)
			return
	_land(collision.position, collision.normal)
	_finish_trace(collision.position, false)


func _finish_trace(point: Vector3, hit: bool) -> void:
	if _trace.is_valid():
		_trace.call({"shape": "line", "origin": _trace_origin, "end": point, "hit": hit})
		_trace = Callable()


func _land(point: Vector3, normal: Vector3) -> void:
	if normal.is_zero_approx():
		normal = -_direction
	_speed = 0.0
	_miss_time = MISSED_WEB_LIFETIME
	global_position = point + normal * IMPACT_OFFSET
	_face(normal)
	_web.scale = Vector3.ONE * 0.78
	reset_physics_interpolation()


func _update_landed_web(delta: float) -> void:
	if _snared:
		var player: Node3D = _target.get_ref()
		if is_instance_valid(player) and player.is_cobweb_rooted():
			global_position = player.global_position + Vector3.UP * IMPACT_OFFSET
			return
		_fade_time += delta
		_web.transparency = clampf(_fade_time / 0.20, 0.0, 1.0)
		if _fade_time >= 0.20:
			queue_free()
		return
	_miss_time -= delta
	_web.transparency = clampf(1.0 - _miss_time / MISSED_WEB_LIFETIME, 0.0, 1.0)
	if _miss_time <= 0.0:
		queue_free()


func _face(direction: Vector3) -> void:
	var up := Vector3.FORWARD if absf(direction.y) > 0.95 else Vector3.UP
	look_at(global_position + direction, up)
