extends RefCounted
## Traces the enlarged attack volume across a short contact window. The held model
## has its own camera scale, so the trace is authored in world units.

const WORLD_LAYER := 1
const ENEMY_LAYER := 4
const MAX_OVERLAPS := 24
const MAX_STEPS := 10
const ANGULAR_STEP := 0.12
const LINEAR_STEP := 0.14
const HILT := Vector3(0.04, -0.30, -0.30)
const CONTACT_WINDOW := 0.074
const HEAVY_WINDOW := 0.093
const REACH_SCALE := 1.10
## Reach, lateral thickness, vertical thickness, light half-angle in radians.
const PROFILES := {
	"unarmed": Vector4(1.70, 0.44, 0.70, 0.34),
	"dagger_1h": Vector4(1.92, 0.40, 0.73, 0.50),
	"sword_1h": Vector4(2.55, 0.47, 0.82, 0.58),
	"mace_1h": Vector4(2.37, 0.53, 0.93, 0.43),
	"axe_1h": Vector4(2.48, 0.56, 0.90, 0.52),
	"sword_2h": Vector4(3.19, 0.53, 0.94, 0.76),
	"mace_2h": Vector4(2.94, 0.67, 1.04, 0.51),
	"axe_2h": Vector4(3.12, 0.69, 1.00, 0.65),
}

var _profile: Vector4
var _heavy: bool
var _window: float
var _owner: RID
var _view := Transform3D.IDENTITY
var _progress := 0.0
var _seen: Dictionary[RID, Dictionary] = {}
var _pending: Array[Dictionary] = []
var _world_hit: Dictionary = {}
var _world_hit_offset := INF
var _box := BoxShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var debug_volume: Callable


func _init(weapon_type: String, heavy: bool, owner: RID, view: Transform3D) -> void:
	_profile = PROFILES.get(weapon_type, PROFILES["unarmed"])
	_heavy = heavy
	_window = HEAVY_WINDOW if heavy else CONTACT_WINDOW
	_owner = owner
	_view = view
	var extension := 0.40 if heavy else 0.0
	_box.size = Vector3(_profile.y, _profile.z, _profile.x + extension + HILT.z)
	if heavy:
		_box.size += Vector3(0.09, 0.12, 0.0)
	_query.shape = _box
	_query.collision_mask = WORLD_LAYER | ENEMY_LAYER
	_query.exclude = [_owner]


func sample(space: PhysicsDirectSpaceState3D, view: Transform3D, remaining: float) -> void:
	if remaining >= _window:
		_view = view
		return
	sample_fraction(space, view, clampf(1.0 - remaining / _window, 0.0, 1.0))


func sample_fraction(space: PhysicsDirectSpaceState3D, view: Transform3D, progress: float) -> void:
	if progress <= _progress:
		return
	var angle := _profile.w + (0.30 if _heavy else 0.0)
	# Interpolate translation and rotation even when the player moves or turns mid-swing.
	var turn := _view.basis.get_rotation_quaternion().angle_to(view.basis.get_rotation_quaternion())
	var rotation_steps := ceili((turn + (progress - _progress) * angle * 2.0) / ANGULAR_STEP)
	var translation_steps := ceili(view.origin.distance_to(_view.origin) / LINEAR_STEP)
	var steps := clampi(maxi(rotation_steps, translation_steps), 1, MAX_STEPS)
	var origin := _view
	for index in range(steps + 1):
		var fraction := float(index) / steps
		var pose := origin.interpolate_with(view, fraction)
		_sample_volume(space, pose, lerpf(_progress, progress, fraction), angle)
	_view = view
	_progress = progress


func trace_blade(space: PhysicsDirectSpaceState3D, view: Transform3D,
		previous: PackedVector3Array, current: PackedVector3Array) -> void:
	var movement := maxf(previous[0].distance_to(current[0]), previous[1].distance_to(current[1]))
	var steps := clampi(ceili(movement / LINEAR_STEP), 1, MAX_STEPS)
	var previous_axis := previous[0].direction_to(previous[1])
	var current_axis := current[0].direction_to(current[1])
	steps = clampi(maxi(steps, ceili(previous_axis.angle_to(current_axis) / ANGULAR_STEP)), 1, MAX_STEPS)
	var travel := (current[0] + current[1] - previous[0] - previous[1]).normalized()
	var blade_moved := not travel.is_zero_approx()
	if travel.is_zero_approx():
		travel = -view.basis.z
	for step in range(steps + 1):
		var fraction := float(step) / steps
		var heel := previous[0].lerp(current[0], fraction)
		var tip := previous[1].lerp(current[1], fraction)
		var span := tip - heel
		if span.is_zero_approx():
			continue
		# Shoulder reach is part of the blade motion. Add tolerance to the
		# moving strike edge without introducing a second camera-aimed cone.
		var nominal_length := span.length() * REACH_SCALE
		var view_reach := _profile.x + (0.32 if _heavy else 0.0)
		var assisted_length := maxf(nominal_length, view_reach - heel.distance_to(view.origin))
		var length := minf(assisted_length, nominal_length + (0.55 if _heavy else 0.38))
		var axis := span.normalized()
		var up := view.basis.y if absf(axis.dot(view.basis.y)) < 0.96 else view.basis.x
		_box.size = Vector3(_profile.y * (0.92 if _heavy else 0.75),
			_profile.z * (0.88 if _heavy else 0.70), length)
		_query.transform = Transform3D(Basis.looking_at(axis, up), heel + axis * (length * 0.5))
		_collect(space, view, heel, travel, fraction, axis if blade_moved else Vector3.ZERO)


func take_contacts() -> Array[Dictionary]:
	var result := _pending
	_pending = []
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	return result


func _sample_volume(space: PhysicsDirectSpaceState3D, view: Transform3D, progress: float,
		angle: float) -> void:
	var yaw := lerpf(angle, -angle, progress)
	var pitch := lerpf(0.22, -0.30, progress) if _heavy else lerpf(0.16, -0.14, progress)
	var forward := view.basis * Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var origin := view * HILT
	var basis := Basis.looking_at(forward, view.basis.y)
	_query.transform = Transform3D(basis, origin + forward * (_box.size.z * 0.5))
	var travel := (-view.basis.z * 0.65 - view.basis.x * 0.72
		- view.basis.y * (0.29 if _heavy else 0.14)).normalized()
	_collect(space, view, origin, travel)


func _collect(space: PhysicsDirectSpaceState3D, view: Transform3D, origin: Vector3, travel: Vector3,
		fraction := 1.0, blade_axis := Vector3.ZERO) -> void:
	if debug_volume.is_valid():
		debug_volume.call(_query.transform, _box.size)
	_query.collision_mask = WORLD_LAYER | ENEMY_LAYER
	_query.exclude = [_owner]
	var overlaps := space.intersect_shape(_query, MAX_OVERLAPS)
	if overlaps.is_empty():
		return
	for hit in overlaps:
		var target := hit.collider as Node3D
		if not is_instance_valid(target):
			continue
		if target.is_in_group(&"enemies") or target.is_in_group(&"breakable_props"):
			_remember_target(space, view, origin, target, hit.rid, overlaps, travel, fraction, blade_axis)
	_remember_terrain(space, view, overlaps)


func _remember_terrain(space: PhysicsDirectSpaceState3D, view: Transform3D,
		overlaps: Array[Dictionary]) -> void:
	var ignored: Array[RID] = [_owner]
	var has_terrain := false
	for hit in overlaps:
		var body := hit.collider as CollisionObject3D
		if not is_instance_valid(body) or (body.collision_layer & WORLD_LAYER) == 0:
			continue
		if body.is_in_group(&"breakable_props"):
			ignored.append(hit.rid)
		else:
			has_terrain = true
	if not has_terrain or _world_hit_offset <= 1.0:
		return
	var forward := -view.basis.z
	var ray := PhysicsRayQueryParameters3D.create(
		view.origin, view.origin + forward * (_profile.x + (0.41 if _heavy else 0.01)), WORLD_LAYER, [_owner])
	var centered := space.intersect_ray(ray)
	if not centered.is_empty() and not centered.rid in ignored:
		var contact_in_box: Vector3 = (_query.transform.affine_inverse() * centered.position).abs()
		var bounds := _box.size * 0.5 + Vector3.ONE * 0.006
		if contact_in_box.x <= bounds.x and contact_in_box.y <= bounds.y and contact_in_box.z <= bounds.z:
			for hit in overlaps:
				if hit.rid == centered.rid:
					centered["point"] = centered.position
					_world_hit = centered
					_world_hit_offset = 1.0
					return
	_query.collision_mask = WORLD_LAYER
	_query.exclude = ignored
	var contact := space.get_rest_info(_query)
	if contact.is_empty():
		return
	var offset: Vector3 = contact.point - view.origin
	var depth := -view.basis.z.dot(offset)
	if depth <= 0.0:
		return
	# Select a real contact nearer the aim from the full swing. The first side
	# contact can be outside the player's view even when the center hits a wall.
	var deviation := offset.length_squared() / (depth * depth)
	if deviation < _world_hit_offset:
		_world_hit_offset = deviation
		_world_hit = contact


func _remember_target(space: PhysicsDirectSpaceState3D, view: Transform3D, origin: Vector3,
		target: Node3D, rid: RID, overlaps: Array[Dictionary], direction: Vector3, fraction: float,
		blade_axis: Vector3) -> void:
	if _seen.has(rid):
		return
	var aim: Vector3 = target.aim_point()
	var aimed := aim - view.origin
	# A body must have a visible surface inside the attack, even if its collider
	# projects through a nearby wall. Other actors may be cleaved in the same strike.
	# The held geometry can already be through a nearby wall when the trace
	# opens. Also test from the actual attacker so this cannot bypass cover.
	var ray := PhysicsRayQueryParameters3D.create(view.origin, aim, WORLD_LAYER, [_owner])
	var obstruction := space.intersect_ray(ray)
	if not obstruction.is_empty() and obstruction.rid != rid:
		return
	ray.from = origin
	var hit := space.intersect_ray(ray)
	if not hit.is_empty() and hit.rid != rid:
		return
	if hit.is_empty() or not blade_axis.is_zero_approx():
		var excluded: Array[RID] = [_owner]
		for entry in overlaps:
			if entry.rid != rid:
				excluded.append(entry.rid)
		_query.exclude = excluded
		var blade_contact := space.get_rest_info(_query)
		if not blade_contact.is_empty():
			hit = blade_contact
		_query.exclude = [_owner]
	var contact: Vector3 = hit.get("point", hit.get("position", aim))
	var camera_forward := -view.basis.z
	var recorded := {"target": target, "point": contact, "direction": direction,
		"normal": hit.get("normal", -direction), "fraction": fraction, "blade_axis": blade_axis,
		"score": camera_forward.dot(aimed.normalized()) * 4.0 - aimed.length() * 0.16}
	_seen[rid] = recorded
	_pending.append(recorded)


func contacts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hit: Dictionary in _seen.values():
		if is_instance_valid(hit.target):
			result.append(hit)
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	return result


func terrain_contact() -> Dictionary:
	return _world_hit
