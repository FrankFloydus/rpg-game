extends Node3D
## The continuous beam and its damage ticks share the same clipped lane.

const GroundCast := preload("res://combat/effects/ground_cast.gd")
const BEAM_HEIGHT := 0.87

var _origin := Vector3.ZERO
var _direction := Vector3.FORWARD
var _footprint: Dictionary
var _reach := 0.0
var _damage := 0.0
var _ability: Dictionary
var _target: WeakRef
var _trace: Callable
var _elapsed := 0.0
var _duration := 0.0
var _tick_interval := 0.0
var _next_tick := 0.0


func launch(origin: Vector3, direction: Vector3, footprint: Dictionary, ability: Dictionary, damage: float,
		target: Node3D, profile: Dictionary, trace: Callable) -> void:
	_origin = origin
	_direction = direction.normalized()
	_footprint = footprint.duplicate()
	_reach = float(footprint.reach)
	_ability = ability
	_damage = damage
	_target = weakref(target)
	_trace = trace
	_duration = maxf(0.10, float(profile.channel_duration))
	_tick_interval = maxf(0.075, float(profile.tick_interval))
	_next_tick = _tick_interval
	global_position = _origin + Vector3.UP * BEAM_HEIGHT
	look_at(global_position + _direction)
	_update_beam(_clip_length())


func _physics_process(delta: float) -> void:
	var target := _target.get_ref() as Node3D
	if not is_instance_valid(target):
		queue_free()
		return
	var open := _clip_length()
	_update_beam(open)
	_elapsed = minf(_elapsed + delta, _duration)
	while _next_tick <= _elapsed + 0.00001 and _next_tick <= _duration:
		_apply_tick(target, open)
		_next_tick += _tick_interval
	if _elapsed >= _duration:
		queue_free()


func _clip_length() -> float:
	return GroundCast.open_length(self, _origin, _direction, _reach, float(_footprint.width), BEAM_HEIGHT)


func _update_beam(length: float) -> void:
	$Core.visible = length > 0.08
	$Halo.visible = $Core.visible
	$Endpoint.visible = $Core.visible
	if not $Core.visible:
		return
	var half_width := float(_footprint.width)
	$Core.position.z = -length * 0.5
	$Core.scale = Vector3(half_width * 0.16, length * 0.5, half_width * 0.16)
	$Halo.position.z = $Core.position.z
	$Halo.scale = Vector3(half_width, length * 0.5, half_width)
	$Endpoint.position.z = -length


func _apply_tick(target: Node3D, length: float) -> void:
	if length <= 0.08:
		return
	_footprint.reach = length
	var hit := GroundCast.target_in_footprint(self, target, _footprint, _origin, _direction) \
		and bool(target.receive_ground_damage(_damage, "lightning", get_parent(), _ability))
	if _trace.is_valid():
		_trace.call({"shape": "lane", "origin": _origin + Vector3.UP * BEAM_HEIGHT,
			"direction": _direction, "reach": length, "width": _footprint.width, "hit": hit})
