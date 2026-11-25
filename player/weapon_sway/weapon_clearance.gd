extends RefCounted
## Fits the held geometry around the eye against nearby world collision.

const SEARCH_STEPS := 8

var _pose: Node3D
var _bounds: AABB
var _mesh_bounds: Array[AABB] = []
var _mesh_points := PackedVector3Array()
var _box := BoxShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()


func _init(pose: Node3D) -> void:
	_pose = pose
	_query.shape = _box
	var to_pose := pose.global_transform.affine_inverse()
	for child in pose.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null or mesh.skin != null:
			continue
		var hull := mesh.mesh.create_convex_shape()
		if hull == null or hull.points.size() < 4:
			continue
		var mesh_to_pose := to_pose * mesh.global_transform
		var bounds := mesh_to_pose * mesh.get_aabb()
		_bounds = bounds if _mesh_points.is_empty() else _bounds.merge(bounds)
		_mesh_bounds.append(bounds)
		_mesh_points.append_array(mesh_to_pose * hull.points)


func minimum_scale(camera: Camera3D, padding: float, applied_scale: float) -> float:
	if not _has_geometry():
		return 0.0
	var view := camera.get_camera_transform()
	var pose := _unscaled_pose(view.origin, applied_scale)
	var local_back := pose.basis.transposed() * view.basis.z
	var closest_offset := -INF
	for point in _mesh_points:
		closest_offset = maxf(closest_offset, point.dot(local_back))
	var nearest := (view.origin - pose.origin).dot(view.basis.z) - closest_offset
	var safe_depth := maxf(camera.near * 2.5, camera.near + padding)
	return clampf(safe_depth / maxf(nearest, safe_depth), 0.0, 1.0)


func scale_limit(camera: Camera3D, mask: int, padding: float, minimum: float,
		applied_scale: float, excluded: Array[RID]) -> float:
	if not _has_geometry():
		return 1.0
	var space := camera.get_world_3d().direct_space_state
	var eye := camera.get_camera_transform().origin
	var pose := _unscaled_pose(eye, applied_scale)
	var local_eye := pose.affine_inverse() * eye
	var envelope := _bounds.expand(local_eye)
	var border := Vector3.ONE * (2.0 * padding)
	var world_scale := pose.basis.get_scale().abs()
	_query.collision_mask = mask
	_query.exclude = excluded
	_query.transform = Transform3D(pose.basis.orthonormalized(), pose * envelope.get_center())
	if not _overlaps(space, envelope.size * world_scale + border, _query.transform.origin):
		return 1.0

	# Keep each mesh's eye-to-geometry volume clear, including across thin walls.
	var limit := 1.0
	for bounds in _mesh_bounds:
		var part := bounds.expand(local_eye)
		var size := part.size * world_scale
		var center := pose * part.get_center()
		if not _overlaps(space, size * limit + border, eye.lerp(center, limit)):
			continue
		if _overlaps(space, size * minimum + border, eye.lerp(center, minimum)):
			return minimum
		var clear := minimum
		var blocked := limit
		for step in SEARCH_STEPS:
			var scale := (clear + blocked) * 0.5
			if _overlaps(space, size * scale + border, eye.lerp(center, scale)):
				blocked = scale
			else:
				clear = scale
		limit = clear
	return limit


func _has_geometry() -> bool:
	return not _mesh_points.is_empty() and is_instance_valid(_pose) and _pose.is_visible_in_tree()


func _unscaled_pose(eye: Vector3, applied_scale: float) -> Transform3D:
	# Previous rendered sockets have already been fit. Recover the current authored envelope first.
	var visible_pose := _pose.global_transform
	return Transform3D(visible_pose.basis.scaled(Vector3.ONE / applied_scale),
		eye.lerp(visible_pose.origin, 1.0 / applied_scale))


func _overlaps(space: PhysicsDirectSpaceState3D, size: Vector3, center: Vector3) -> bool:
	_box.size = size.max(Vector3.ONE * 0.001)
	_query.transform.origin = center
	return not space.intersect_shape(_query, 1).is_empty()
