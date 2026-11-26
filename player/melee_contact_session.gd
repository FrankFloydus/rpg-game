extends RefCounted
## Orders a strike's contacts and holds secondary actors during a precision cut.

const WORLD_LAYER := 1
const ENEMY_LAYER := 4
const MAX_AIM_CANDIDATES := 32

var _uses_precision: bool
var _precision_range: float
var _precision_dot: float
var _precision_target: Node3D
var _lost_priority := false
var _priority_contacted := false
var _deferred: Array[Dictionary] = []


func _init(uses_precision: bool, precision_range := 2.85, precision_dot := 0.90) -> void:
	_uses_precision = uses_precision
	_precision_range = precision_range
	_precision_dot = precision_dot


func begin(space: PhysicsDirectSpaceState3D, aim: Transform3D, owner: RID) -> void:
	_precision_target = null
	_lost_priority = false
	_priority_contacted = false
	_deferred.clear()
	if not _uses_precision:
		return
	var ray := PhysicsRayQueryParameters3D.create(aim.origin, aim.origin - aim.basis.z * _precision_range,
		WORLD_LAYER | ENEMY_LAYER, [owner])
	var hit := space.intersect_ray(ray)
	var target := hit.get("collider") as Node3D
	if _still_aimed_at(target, aim):
		_precision_target = target
		return
	_precision_target = _visible_aim_target(space, aim, owner)


## The caller passes the closure query separately to replay held contacts at Trace End.
func take_contacts(aim: Transform3D, contacts: Array[Dictionary], closes_window := false,
		fits_saved := Callable()) -> Array[Dictionary]:
	var order := range(contacts.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		var first := float(contacts[a].get("fraction", 1.0))
		var second := float(contacts[b].get("fraction", 1.0))
		return a < b if first == second else first < second)
	var result: Array[Dictionary] = []
	if closes_window:
		_precision_target = null
		for held in _deferred:
			_append_replay(result, held, 1.0)
		_deferred.clear()
	elif _precision_target != null and not _still_aimed_at(_precision_target, aim):
		_precision_target = null
		_lost_priority = true
	if not closes_window and _lost_priority and not order.is_empty():
		_lost_priority = false
		_replay_latest(result, float(contacts[order[0]].get("fraction", 1.0)), false)
	for index in order:
		var contact := contacts[index]
		if not closes_window and _priority_contacted:
			_priority_contacted = false
			_replay_latest(result, float(contact.get("fraction", 1.0)), true)
		if contact.get("kind", &"actor") != &"actor":
			result.append(contact)
			continue
		var target: Variant = contact.get("target")
		if not _is_live_enemy(target):
			continue
		if _precision_target == null or target == _precision_target:
			result.append(contact)
			if _precision_target != null:
				_precision_target = null
				_priority_contacted = true
		else:
			var held := contact.duplicate()
			held.fits_saved_mass = not fits_saved.is_valid() or bool(fits_saved.call(target))
			_deferred.append(held)
	return result


func _replay_latest(result: Array[Dictionary], fraction: float, require_fit: bool) -> void:
	if _deferred.is_empty():
		return
	var held: Dictionary = _deferred.back()
	if require_fit and not bool(held.fits_saved_mass):
		return
	_deferred.pop_back()
	_append_replay(result, held, fraction)


func _append_replay(result: Array[Dictionary], contact: Dictionary, fraction: float) -> void:
	if _is_live_enemy(contact.get("target")):
		# Keep the measured point and normal. Time the response to the current sample.
		contact.fraction = fraction
		result.append(contact)


func _visible_aim_target(space: PhysicsDirectSpaceState3D, aim: Transform3D, owner: RID) -> Node3D:
	var proximity := SphereShape3D.new()
	proximity.radius = _precision_range
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = proximity
	query.transform = Transform3D(Basis.IDENTITY, aim.origin)
	query.collision_mask = ENEMY_LAYER
	query.exclude = [owner]
	var target: Node3D
	var best_alignment := -INF
	var best_distance := INF
	var forward := -aim.basis.z
	var ray := PhysicsRayQueryParameters3D.create(aim.origin, aim.origin, WORLD_LAYER, [owner])
	for overlap in space.intersect_shape(query, MAX_AIM_CANDIDATES):
		var candidate := overlap.get("collider") as Node3D
		if not _still_aimed_at(candidate, aim):
			continue
		var point: Vector3 = candidate.aim_point()
		var displacement := point - aim.origin
		var alignment := forward.dot(displacement.normalized())
		var distance := displacement.length_squared()
		if alignment < best_alignment or (alignment == best_alignment and distance >= best_distance):
			continue
		ray.to = point
		if space.intersect_ray(ray).is_empty():
			target = candidate
			best_alignment = alignment
			best_distance = distance
	return target


func _still_aimed_at(target: Variant, aim: Transform3D) -> bool:
	if not _is_live_enemy(target):
		return false
	var offset: Vector3 = target.aim_point() - aim.origin
	return offset.length_squared() <= _precision_range * _precision_range \
		and (-aim.basis.z).dot(offset.normalized()) >= _precision_dot


static func _is_live_enemy(target: Variant) -> bool:
	return is_instance_valid(target) and target is Node3D and not target.is_queued_for_deletion() \
		and target.is_in_group(&"enemies") and target.health > 0.0
