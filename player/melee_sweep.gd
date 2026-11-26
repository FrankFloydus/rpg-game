extends RefCounted
## Traces the enlarged attack volume across a short contact window. The held model
## has its own camera scale, so the trace is authored in world units.

const BreakableProp := preload("res://world/modules/breakable_prop.gd")

const WORLD_LAYER := 1
const ENEMY_LAYER := 4
const MAX_OVERLAPS := 24
const MAX_STEPS := 10
const ANGULAR_STEP := 0.12
const LINEAR_STEP := 0.14
const MACE_HEAD_STEP := 0.07
const MACE_HEAD_WIDTH := 0.22
const MACE_HEAD_HEIGHT := 0.22
const MACE_HEAD_CONTACT_MARGIN := 0.02
const MACE_TERRAIN_HALF_VIEW := Vector2(57.775, 60.0)
const SHAFT_CROSS_DEPTH := 0.005
const CAST_PROBE_DEPTH := 0.008
const ROTATION_CAST_STEP := 0.36
const FLOOR_STOP_RADIUS := 0.15
const FLOOR_AIM_TOLERANCE := 0.45
const MACE_CUT_HALF_YAW := 25.0
const MACE_CUT_MAX_RISE := 15.0
const MACE_CUT_MAX_DROP := 28.0
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
var _charged_terrain_contact: Dictionary = {}
var _world_hit_offset := INF
var _contact_cast := false
var _swept_targets: Dictionary[RID, Dictionary] = {}
var _pending_terrain: Array[Dictionary] = []
var _reported_surfaces: Dictionary = {}
var _box := BoxShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var _head_box: BoxShape3D
var _head_query: PhysicsShapeQueryParameters3D
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
		previous: PackedVector3Array, current: PackedVector3Array, stop_at_terrain := false,
		terrain_fraction := 0.0, terrain_impact_fraction := 0.0) -> void:
	var movement := maxf(previous[0].distance_to(current[0]), previous[1].distance_to(current[1]))
	var linear_step := MACE_HEAD_STEP if stop_at_terrain else LINEAR_STEP
	var steps := clampi(ceili(movement / linear_step), 1, MAX_STEPS)
	var previous_axis := previous[0].direction_to(previous[1])
	var current_axis := current[0].direction_to(current[1])
	steps = clampi(maxi(steps, ceili(previous_axis.angle_to(current_axis) / ANGULAR_STEP)), 1, MAX_STEPS)
	var heel_motion := current[0] - previous[0]
	var tip_motion := current[1] - previous[1]
	var world_to_aim := view.affine_inverse() if stop_at_terrain else Transform3D.IDENTITY
	var travel := (heel_motion + tip_motion).normalized()
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
		var head := (heel + tip) * 0.5
		if stop_at_terrain and fraction >= terrain_fraction and movement > 0.0001 \
				and _mace_head_in_cut(world_to_aim * head):
			var contact := _mace_terrain_contact(space, view.origin, world_to_aim, head, heel, tip,
				heel_motion, tip_motion, travel, fraction >= terrain_impact_fraction)
			if not contact.is_empty():
				contact.fraction = fraction
				_world_hit = contact
				break
		_collect(space, view, heel, travel, fraction, axis if blade_moved else Vector3.ZERO, not stop_at_terrain)


## Samples the previous shaft, rotation around its heel, and translation to the
## current pose as three continuous fixed-orientation casts.
func trace_contact_sweep(space: PhysicsDirectSpaceState3D, previous_aim: Transform3D,
		current_aim: Transform3D, previous: PackedVector3Array, current: PackedVector3Array,
		options: Dictionary = {}) -> void:
	if previous.size() < 2 or current.size() < 2:
		return
	var old_span := previous[1] - previous[0]
	var new_span := current[1] - current[0]
	if old_span.is_zero_approx() or new_span.is_zero_approx():
		return
	_contact_cast = true
	_swept_targets.clear()
	var old_axis := old_span.normalized()
	var new_axis := new_span.normalized()
	var old_basis: Basis = options.get("previous_basis", _blade_basis(old_axis, previous_aim.basis.y))
	var new_basis: Basis = options.get("current_basis", _blade_basis(new_axis, current_aim.basis.y))
	var dims := Vector2(
		float(options.get("width", _profile.y * (0.92 if _heavy else 0.75))) * float(options.get("width_scale", 1.0)),
		float(options.get("height", _profile.z * (0.88 if _heavy else 0.70))) * float(options.get("height_scale", 1.0)))
	var arc := old_basis.get_rotation_quaternion().angle_to(new_basis.get_rotation_quaternion())
	var steps := clampi(ceili(arc / ROTATION_CAST_STEP), 1, MAX_STEPS)
	var travel := (current[0] + current[1] - previous[0] - previous[1]).normalized()
	if travel.is_zero_approx():
		travel = -current_aim.basis.z
	var context := {
		"old_aim": previous_aim, "new_aim": current_aim, "travel": travel, "options": options,
		"old_heel": previous[0], "new_heel": current[0],
		"old_tip": previous[1], "new_tip": current[1],
		"weapon_moved": not previous[0].is_equal_approx(current[0]) or not previous[1].is_equal_approx(current[1]),
	}
	var before := _damage_pose(previous[0], old_span.length(), old_basis, previous_aim, options)
	for step in range(1, steps + 1):
		var fraction := float(step) / steps
		var orientation := old_basis.slerp(new_basis, fraction)
		var after := _damage_pose(previous[0].lerp(current[0], fraction),
			lerpf(old_span.length(), new_span.length(), fraction), orientation,
			previous_aim.interpolate_with(current_aim, fraction), options)
		_trace_cast_interval(space, before, after, dims, Vector2(float(step - 1) / steps, fraction), context)
		before = after
	if options.get("mace_head_stop", false):
		var old_head: PackedVector3Array = options.get("previous_head", previous)
		var new_head: PackedVector3Array = options.get("current_head", current)
		_trace_contact_head(space, previous_aim, current_aim, old_head, new_head, options)
	for rid: RID in _swept_targets:
		var contact: Dictionary = _swept_targets[rid]
		_seen[rid] = contact
		_pending.append(contact)


func _blade_basis(axis: Vector3, up: Vector3) -> Basis:
	var stable_up := up if absf(axis.dot(up)) < 0.96 else up.cross(axis).normalized()
	return Basis.looking_at(axis, stable_up if not stable_up.is_zero_approx() else Vector3.FORWARD)


func _damage_pose(heel: Vector3, span: float, basis: Basis, aim: Transform3D, options: Dictionary) -> Dictionary:
	var nominal := span * float(options.get("length_scale", REACH_SCALE))
	var reach := float(options.get("reach_target", _profile.x + (0.32 if _heavy else 0.0)))
	var assist := float(options.get("reach_assist", 0.55 if _heavy else 0.38))
	var length := minf(maxf(nominal, reach - heel.distance_to(aim.origin)), nominal + assist)
	length *= float(options.get("reach_scale", 1.0))
	var offset := basis.y * float(options.get("up_offset", 0.0)) - Vector3.UP * float(options.get("down_offset", 0.0))
	return {"heel": heel + offset, "basis": basis, "half": maxf(0.005, length * 0.5)}


func _trace_cast_interval(space: PhysicsDirectSpaceState3D, before: Dictionary, after: Dictionary,
		dims: Vector2, fractions: Vector2, context: Dictionary) -> void:
	var previous_heel: Vector3 = before.heel
	var next_heel: Vector3 = after.heel
	var previous_basis: Basis = before.basis
	var next_basis: Basis = after.basis
	var old_half: float = before.half
	var new_half: float = after.half
	var old_arm := -previous_basis.z * old_half
	var new_arm := -next_basis.z * new_half
	_cast_contact_box(space, Transform3D(previous_basis, previous_heel), old_arm * 2.0,
		Vector3(dims.x, dims.y, SHAFT_CROSS_DEPTH), 5, Vector2(fractions.x, fractions.x), context)
	var turn := (new_arm - old_arm) * 2.0
	if not turn.is_zero_approx():
		_cast_contact_box(space, Transform3D(previous_basis, previous_heel + old_arm), turn,
			Vector3(dims.x, dims.y, old_half * 2.0), 20, fractions, context)
	_cast_contact_box(space, Transform3D(next_basis, previous_heel + new_arm), next_heel - previous_heel,
		Vector3(dims.x, dims.y, new_half * 2.0), 5, fractions, context)


func _cast_contact_box(space: PhysicsDirectSpaceState3D, start: Transform3D, motion: Vector3, size: Vector3,
		limit: int, fractions: Vector2, context: Dictionary) -> void:
	_box.size = size
	var excluded: Array[RID] = [_owner]
	excluded.append_array(_seen.keys())
	_query.collision_mask = WORLD_LAYER | ENEMY_LAYER
	_query.transform = start
	_query.motion = Vector3.ZERO
	_query.exclude = excluded
	if debug_volume.is_valid():
		debug_volume.call(start, size)
		if not motion.is_zero_approx():
			debug_volume.call(start.translated(motion), size)
	# Godot's motion query omits shapes already overlapping the start box.
	var found := 0
	while found < limit:
		var hit := space.get_rest_info(_query)
		if hit.is_empty():
			break
		_record_cast_hit(space, hit, fractions.x, -start.basis.z, context)
		excluded.append(hit.rid)
		_query.exclude = excluded
		found += 1
	if motion.is_zero_approx():
		return
	var probe := CAST_PROBE_DEPTH / motion.length()
	while found < limit:
		_query.transform = start
		_query.motion = motion
		var interval := space.cast_motion(_query)
		_query.motion = Vector3.ZERO
		if interval.size() < 2 or interval[0] >= 1.0:
			break
		# Probe just through first contact to recover the Godot collider and point.
		var hit: Dictionary = {}
		for blend in [0.25, 1.0, 2.0]:
			_query.transform = start.translated(motion * minf(1.0, interval[1] + probe * blend))
			hit = space.get_rest_info(_query)
			if not hit.is_empty():
				break
		if hit.is_empty():
			break
		var fraction := lerpf(fractions.x, fractions.y, interval[1])
		_record_cast_hit(space, hit, fraction, -start.basis.z, context)
		excluded.append(hit.rid)
		_query.exclude = excluded
		found += 1


func _record_cast_hit(space: PhysicsDirectSpaceState3D, hit: Dictionary, fraction: float,
		blade_axis: Vector3, context: Dictionary) -> void:
	var collider := instance_from_id(hit.collider_id) as CollisionObject3D
	if not is_instance_valid(collider) or collider.is_queued_for_deletion():
		return
	var old_aim: Transform3D = context.old_aim
	var aim := old_aim.interpolate_with(context.new_aim, fraction)
	var point: Vector3 = hit.point
	var options: Dictionary = context.options
	var local := aim.affine_inverse() * point
	if not _contact_in_view(local, options):
		return
	var travel: Vector3 = context.travel
	var rid: RID = hit.rid
	var prop := collider.is_in_group(&"breakable_props")
	hit["direction"] = travel
	hit["fraction"] = fraction
	if collider.is_in_group(&"enemies") or prop:
		if _seen.has(rid) or (_swept_targets.has(rid) and _swept_targets[rid].fraction <= fraction):
			return
		var heel: Vector3 = context.old_heel
		heel = heel.lerp(context.new_heel, fraction)
		if not _cast_contact_visible(space, aim.origin, point, rid) or not _cast_contact_visible(space, heel, point, rid):
			return
		var aimed: Vector3 = collider.aim_point() - aim.origin
		hit["target"] = collider
		hit["blade_axis"] = blade_axis if context.weapon_moved else Vector3.ZERO
		hit["score"] = -aim.basis.z.dot(aimed.normalized()) * 4.0 - aimed.length() * 0.16
		_swept_targets[rid] = hit
	elif collider.collision_layer & WORLD_LAYER:
		var normal: Vector3 = hit.normal
		if normal.dot(aim.origin - point) <= 0.0 or not _mace_surface_visible(space, aim.origin, hit):
			return
		var armed := fraction >= float(options.get("terrain_fraction", 0.0))
		var reached_impact := fraction >= float(options.get("terrain_impact_fraction", 0.0))
		hit["can_stop"] = (armed and reached_impact and travel.dot(normal) < -0.04
			and not options.get("mace_head_stop", false)
			and (normal.y < 0.65 or _aimed_floor_contact(space, hit, aim, fraction, context)))
		_queue_terrain_contact(hit)


func _aimed_floor_contact(space: PhysicsDirectSpaceState3D, hit: Dictionary,
		aim: Transform3D, fraction: float, context: Dictionary) -> bool:
	# Assisted actor volumes can graze the floor while both actual weapons are clear.
	var point: Vector3 = hit.point
	var old_heel: Vector3 = context.old_heel
	var old_tip: Vector3 = context.old_tip
	var heel := old_heel.lerp(context.new_heel, fraction)
	var tip := old_tip.lerp(context.new_tip, fraction)
	var blade_point := Geometry3D.get_closest_point_to_segment(point, heel, tip)
	if blade_point.distance_squared_to(point) > FLOOR_STOP_RADIUS * FLOOR_STOP_RADIUS:
		return false
	var ray_end := aim.origin - aim.basis.z * (aim.origin.distance_to(point) + FLOOR_AIM_TOLERANCE)
	var centered := _mace_surface_on_ray(space, aim.origin, ray_end)
	return (_same_mace_surface(centered, hit)
		and Vector3(centered.point).distance_squared_to(point) <= FLOOR_AIM_TOLERANCE * FLOOR_AIM_TOLERANCE)


func _cast_contact_visible(space: PhysicsDirectSpaceState3D, from: Vector3, point: Vector3, target: RID) -> bool:
	if from.distance_squared_to(point) <= 0.0001:
		return true
	var ray := PhysicsRayQueryParameters3D.create(from, point, WORLD_LAYER, [_owner])
	ray.hit_from_inside = true
	var excluded: Array[RID] = [_owner]
	for _obstacle in MAX_OVERLAPS:
		var cover := space.intersect_ray(ray)
		if cover.is_empty() or cover.rid == target:
			return true
		var prop := cover.collider as BreakableProp
		if prop == null or not prop.allow_melee_damage or not prop.melee_hit_through:
			return false
		excluded.append(cover.rid)
		ray.exclude = excluded
	return false


func _contact_in_view(point: Vector3, options: Dictionary) -> bool:
	var depth := -point.z
	var yaw := float(options.get("horizontal_half_angle", MACE_TERRAIN_HALF_VIEW.x))
	var pitch := float(options.get("vertical_half_angle", MACE_TERRAIN_HALF_VIEW.y))
	return (depth > 0.0 and absf(point.x) <= depth * tan(deg_to_rad(yaw))
		and absf(point.y) <= Vector2(point.x, depth).length() * tan(deg_to_rad(pitch)))


func _trace_contact_head(space: PhysicsDirectSpaceState3D, previous_aim: Transform3D, current_aim: Transform3D,
		previous: PackedVector3Array, current: PackedVector3Array, options: Dictionary) -> void:
	if previous.size() < 2 or current.size() < 2:
		return
	var heel_motion := current[0] - previous[0]
	var tip_motion := current[1] - previous[1]
	var movement := maxf(heel_motion.length(), tip_motion.length())
	if movement <= 0.0001:
		return
	var steps := clampi(ceili(movement / MACE_HEAD_STEP), 1, MAX_STEPS)
	var travel := (heel_motion + tip_motion).normalized()
	var terrain_fraction := float(options.get("terrain_fraction", 0.0))
	var impact_fraction := float(options.get("terrain_impact_fraction", 0.0))
	for step in range(steps + 1):
		var fraction := float(step) / steps
		if fraction < terrain_fraction:
			continue
		var aim := previous_aim.interpolate_with(current_aim, fraction)
		var world_to_aim := aim.affine_inverse()
		var heel := previous[0].lerp(current[0], fraction)
		var tip := previous[1].lerp(current[1], fraction)
		var head := (heel + tip) * 0.5
		if heel.is_equal_approx(tip) or not _mace_head_in_cut(world_to_aim * head):
			continue
		_query.transform = Transform3D(_blade_basis(heel.direction_to(tip), aim.basis.y), head)
		var hit := _mace_terrain_contact(space, aim.origin, world_to_aim, head, heel, tip,
			heel_motion, tip_motion, travel, fraction >= impact_fraction)
		if hit.is_empty() or not _contact_in_view(world_to_aim * Vector3(hit.point), options):
			continue
		hit["fraction"] = fraction
		hit["can_stop"] = true
		_queue_terrain_contact(hit)
		return


func _queue_terrain_contact(hit: Dictionary) -> void:
	var key: Array = [hit.rid, hit.shape, hit.can_stop]
	if _reported_surfaces.has(key):
		for index in _pending_terrain.size():
			var candidate: Dictionary = _pending_terrain[index]
			if candidate.rid == hit.rid and candidate.shape == hit.shape and candidate.can_stop == hit.can_stop:
				if float(hit.fraction) < float(candidate.fraction):
					_pending_terrain[index] = hit
				return
		return
	_reported_surfaces[key] = true
	_pending_terrain.append(hit)
	if _world_hit.is_empty() or bool(hit.can_stop):
		_world_hit = hit


func take_terrain_contacts() -> Array[Dictionary]:
	var result := _pending_terrain
	_pending_terrain = []
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.fraction < b.fraction)
	return result


func _mace_terrain_contact(space: PhysicsDirectSpaceState3D, eye: Vector3, world_to_aim: Transform3D,
		head: Vector3, heel: Vector3, tip: Vector3, heel_motion: Vector3, tip_motion: Vector3,
		travel: Vector3, reached_impact: bool) -> Dictionary:
	if not _heavy:
		var overlap := _trace_mace_head(space, eye, heel, tip, heel_motion, tip_motion, world_to_aim)
		if not overlap.is_empty():
			return overlap
	var front := _mace_surface_on_ray(space, eye, head)
	# A charged cut can reach a close face slightly before its contact pose.
	# Keep that approach only while the same face still blocks the cut.
	if _heavy and reached_impact and not _charged_terrain_contact.is_empty():
		var approach := _charged_terrain_contact
		_charged_terrain_contact = {}
		if _same_mace_surface(front, approach):
			front.direction = approach.direction
			return front
	var contact := {}
	if not front.is_empty() and travel.dot(front.normal) < -0.04:
		front.direction = travel
		contact = front
	elif _heavy and front.is_empty():
		contact = _trace_mace_head(space, eye, heel, tip, heel_motion, tip_motion, world_to_aim)
	if reached_impact or not _heavy:
		return contact
	if not contact.is_empty():
		_charged_terrain_contact = contact
	return {}


func _same_mace_surface(a: Dictionary, b: Dictionary) -> bool:
	return not a.is_empty() and not b.is_empty() and a.rid == b.rid and a.shape == b.shape


func _trace_mace_head(space: PhysicsDirectSpaceState3D, eye: Vector3, heel: Vector3, tip: Vector3,
		heel_motion: Vector3, tip_motion: Vector3, world_to_aim: Transform3D) -> Dictionary:
	if _head_query == null:
		_head_box = BoxShape3D.new()
		_head_query = PhysicsShapeQueryParameters3D.new()
		_head_query.shape = _head_box
		_head_query.collision_mask = WORLD_LAYER
	# Terrain must meet the actual head, without the reach and width assistance used for enemies.
	_head_box.size = Vector3(MACE_HEAD_WIDTH, MACE_HEAD_HEIGHT, heel.distance_to(tip))
	_head_query.transform = Transform3D(_query.transform.basis, (heel + tip) * 0.5)
	_head_query.exclude = [_owner]
	if debug_volume.is_valid():
		debug_volume.call(_head_query.transform, _head_box.size)
	var overlaps := space.intersect_shape(_head_query, MAX_OVERLAPS)
	if overlaps.is_empty():
		return {}
	var excluded: Array[RID] = [_owner]
	var solid_shapes: Dictionary[RID, Array] = {}
	for hit in overlaps:
		var collider := hit.collider as Node3D
		if is_instance_valid(collider) and collider.is_in_group(&"breakable_props"):
			excluded.append(hit.rid)
		else:
			if not solid_shapes.has(hit.rid):
				solid_shapes[hit.rid] = []
			solid_shapes[hit.rid].append(hit.shape)
	if solid_shapes.is_empty():
		return {}
	var world_to_head := _head_query.transform.affine_inverse()
	var half_size := _head_box.size * 0.5 + Vector3.ONE * MACE_HEAD_CONTACT_MARGIN
	for _attempt in range(MAX_OVERLAPS):
		_head_query.exclude = excluded
		var contact := space.get_rest_info(_head_query)
		if contact.is_empty():
			break
		var colliding_shapes: Array = solid_shapes.get(contact.rid, [])
		var collider: RID = contact.rid
		if contact.shape in colliding_shapes:
			var travel := _mace_contact_travel(contact, world_to_head, half_size, world_to_aim,
				heel, tip, heel_motion, tip_motion)
			if travel.is_zero_approx():
				contact = _probe_mace_surface(space, contact, excluded, half_size)
				travel = _mace_contact_travel(contact, world_to_head, half_size, world_to_aim,
					heel, tip, heel_motion, tip_motion)
			if not travel.is_zero_approx() and _mace_surface_visible(space, eye, contact):
				contact.direction = travel
				return contact
		excluded.append(collider)
	return {}


func _mace_surface_visible(space: PhysicsDirectSpaceState3D, eye: Vector3, contact: Dictionary) -> bool:
	var toward_eye := eye - Vector3(contact.point)
	if toward_eye.dot(contact.normal) <= 0.0:
		return false
	var front := _mace_surface_on_ray(space, eye, contact.point - Vector3(contact.normal) * 0.02)
	return _same_mace_surface(front, contact) and Vector3(front.point).distance_to(contact.point) <= 0.04


func _mace_surface_on_ray(space: PhysicsDirectSpaceState3D, eye: Vector3, end: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(eye, end, WORLD_LAYER, [_owner])
	var hit := space.intersect_ray(ray)
	if not hit.is_empty():
		var collider := hit.collider as Node3D
		if is_instance_valid(collider) and collider.is_in_group(&"breakable_props"):
			return {}
		hit.point = hit.position
	return hit


func _probe_mace_surface(space: PhysicsDirectSpaceState3D, contact: Dictionary, excluded: Array[RID],
		half_size: Vector3) -> Dictionary:
	# The overlap solver can report a cylinder's end cap far from the head.
	# Recover the nearby surface along its normal, on the same overlapping shape.
	var normal := Vector3(contact.normal).normalized()
	if normal.is_zero_approx():
		return {}
	var pose := _head_query.transform
	var offset := normal * (pose.basis.inverse() * normal).abs().dot(half_size)
	var ray := PhysicsRayQueryParameters3D.create(pose.origin + offset, pose.origin - offset,
		WORLD_LAYER, excluded)
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or hit.rid != contact.rid or hit.shape != contact.shape:
		return {}
	hit.point = hit.position
	return hit


func _mace_contact_travel(contact: Dictionary, world_to_head: Transform3D, half_size: Vector3,
		world_to_aim: Transform3D, heel: Vector3, tip: Vector3, heel_motion: Vector3,
		tip_motion: Vector3) -> Vector3:
	if contact.is_empty():
		return Vector3.ZERO
	var point: Vector3 = contact.point
	var local := (world_to_head * point).abs()
	if local.x > half_size.x or local.y > half_size.y or local.z > half_size.z \
			or not _mace_terrain_in_view(world_to_aim * point):
		return Vector3.ZERO
	var span := tip - heel
	var along_head := clampf((point - heel).dot(span) / span.length_squared(), 0.0, 1.0)
	var travel := heel_motion.lerp(tip_motion, along_head).normalized()
	return travel if travel.dot(contact.normal) < -0.04 else Vector3.ZERO


func _mace_terrain_in_view(contact: Vector3) -> bool:
	# Check the physical contact against a fixed gameplay cone, independent of the render lens.
	var depth := -contact.z
	var horizontal_distance := Vector2(contact.x, depth).length()
	return depth > 0.0 and absf(contact.x) <= depth * tan(deg_to_rad(MACE_TERRAIN_HALF_VIEW.x)) \
		and absf(contact.y) <= horizontal_distance * tan(deg_to_rad(MACE_TERRAIN_HALF_VIEW.y))


func _mace_head_in_cut(head: Vector3) -> bool:
	# A pillar can overlap the outer corner of the head while the main cut is still
	# beside or above aim. Require the head centre to have entered the strike region.
	var depth := -head.z
	return depth > 0.0 and absf(head.x) <= depth * tan(deg_to_rad(MACE_CUT_HALF_YAW)) \
		and head.y <= depth * tan(deg_to_rad(MACE_CUT_MAX_RISE)) \
		and head.y >= -depth * tan(deg_to_rad(MACE_CUT_MAX_DROP))


func take_contacts() -> Array[Dictionary]:
	var result := _pending
	_pending = []
	if _contact_cast:
		result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a.fraction < b.fraction if a.fraction != b.fraction else a.score > b.score)
	else:
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
		fraction := 1.0, blade_axis := Vector3.ZERO, record_terrain := true) -> void:
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
	if record_terrain:
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
