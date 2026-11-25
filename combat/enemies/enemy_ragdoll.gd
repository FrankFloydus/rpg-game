extends RefCounted
## Builds terrain-only physical bodies for the weighted bones of a defeated enemy.

const CUT_BONES := &"engore_severed_bones"
const WORLD_LAYER := 1


static func start(corpse: Node3D, momentum: Vector3) -> void:
	if not is_instance_valid(corpse) or not corpse.is_inside_tree():
		return
	var skeletons := corpse.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty() and _start_skeleton(corpse, skeletons[0] as Skeleton3D, momentum):
		return
	_start_rigid(corpse, momentum)


static func _start_skeleton(corpse: Node3D, skeleton: Skeleton3D, momentum: Vector3) -> bool:
	var severed := PackedInt32Array()
	for cut: StringName in corpse.get_meta(CUT_BONES, []):
		var id := skeleton.find_bone(cut)
		if id >= 0:
			severed.append(id)
	var multi_legged := _has_four_or_more_legs(skeleton)
	var trunk := skeleton.find_bone(&"Pelvis") if multi_legged else -1
	var spine := skeleton.find_bone(&"Spine") if multi_legged else -1
	# The hound and spider rigs attach their legs to Pelvis while weighting the
	# body to Spine. These two bones carry a single physical trunk.
	var merge_trunk := trunk >= 0 and spine >= 0 and skeleton.get_bone_parent(spine) == trunk
	skeleton.force_update_all_bone_transforms()
	var points := _bone_points(corpse, skeleton)
	if merge_trunk and points.has(spine):
		var to_trunk := skeleton.get_bone_global_pose(trunk).affine_inverse() * skeleton.get_bone_global_pose(spine)
		var trunk_points: PackedVector3Array = points.get(trunk, PackedVector3Array())
		for point in points[spine]:
			trunk_points.append(to_trunk * point)
		points[trunk] = trunk_points
		points.erase(spine)
	if points.is_empty():
		return false
	var bounds: Dictionary[int, AABB] = {}
	for index in points:
		bounds[index] = _point_bounds(points[index])
	_add_joint_anchors(skeleton, bounds)
	var simulator := PhysicalBoneSimulator3D.new()
	simulator.name = "DeathRagdoll"
	skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_PHYSICS
	skeleton.add_child(simulator)
	var bodies: Array[PhysicalBone3D] = []
	for index in skeleton.get_bone_count():
		if not bounds.has(index) or _cut_branch(skeleton, index, severed):
			continue
		var surface: PackedVector3Array = points.get(index, PackedVector3Array())
		var body := _create_bone(skeleton, index, bounds[index], surface, multi_legged)
		simulator.add_child(body)
		PhysicsServer3D.body_set_enable_continuous_collision_detection(body.get_rid(), true)
		bodies.append(body)
	if bodies.is_empty():
		simulator.queue_free()
		return false
	skeleton.force_update_all_bone_transforms()
	simulator.physical_bones_start_simulation()
	for body in bodies:
		body.linear_velocity = momentum
		if skeleton.get_bone_parent(body.get_bone_id()) < 0:
			body.angular_velocity = Vector3.UP.cross(momentum) * 1.4
	return true


static func _has_four_or_more_legs(skeleton: Skeleton3D) -> bool:
	var legs := 0
	for index in skeleton.get_bone_count():
		var name := String(skeleton.get_bone_name(index))
		if name.begins_with("Leg") and not name.ends_with("Bend"):
			legs += 1
	return legs >= 4


static func _add_joint_anchors(skeleton: Skeleton3D, bounds: Dictionary[int, AABB]) -> void:
	# Weightless ancestors can still be shared attachment points for limbs.
	var indices := bounds.keys()
	for index: int in indices:
		var ancestor := skeleton.get_bone_parent(index)
		var world_center := skeleton.get_bone_global_rest(index) * bounds[index].get_center()
		var spine := skeleton.find_bone(&"Spine")
		if spine >= 0 and bounds.has(spine):
			world_center = skeleton.get_bone_global_rest(spine) * bounds[spine].get_center()
		while ancestor >= 0 and not bounds.has(ancestor):
			var center := skeleton.get_bone_global_rest(ancestor).affine_inverse() * world_center
			bounds[ancestor] = AABB(center - Vector3.ONE * 0.08, Vector3.ONE * 0.16)
			ancestor = skeleton.get_bone_parent(ancestor)


static func _create_bone(skeleton: Skeleton3D, index: int, bounds: AABB,
		points: PackedVector3Array, multi_legged: bool) -> PhysicalBone3D:
	var id := skeleton.get_bone_name(index)
	var body := PhysicalBone3D.new()
	body.name = "Body_" + String(id)
	body.set("bone_name", id)
	body.collision_layer = 0
	body.collision_mask = WORLD_LAYER
	body.friction = 0.82
	body.linear_damp = 0.28
	body.angular_damp = 1.65
	var is_root := skeleton.get_bone_parent(index) < 0
	var limb := String(id).begins_with("Arm") or String(id).begins_with("Leg") or String(id).begins_with("Wing")
	var extent := bounds.size
	var center := bounds.get_center()
	if limb and not multi_legged:
		# Weapons share the hand's weights. Limit physics to the anatomical segment.
		var span := _limb_span(skeleton, index)
		extent.y = minf(extent.y, span * 1.7)
		extent.x = minf(extent.x, span * 1.3)
		extent.z = minf(extent.z, span * 1.3)
		center = center.limit_length(span * 0.8)
	body.body_offset = Transform3D(Basis.IDENTITY, center)
	body.mass = 5.0 if is_root else clampf(extent.length() * (1.3 if limb else 2.2), 0.35, 2.4)
	if not is_root:
		body.joint_type = PhysicalBone3D.JOINT_TYPE_PIN
	var collision := CollisionShape3D.new()
	collision.name = "ContactShape"
	if multi_legged and points.size() >= 4:
		collision.shape = _surface_hull(points, center)
	else:
		var capsule := CapsuleShape3D.new()
		capsule.radius = maxf(0.04, maxf(extent.x, extent.z) * 0.5)
		capsule.height = maxf(capsule.radius * 2.0, extent.y + capsule.radius * (0.55 if limb else 0.9))
		collision.shape = capsule
	body.add_child(collision)
	return body


static func _surface_hull(points: PackedVector3Array, center: Vector3) -> Shape3D:
	# Sample the extreme vertices in opposing directions to retain the animal's
	# true length and thickness without a hull built from every render vertex.
	var extremes := PackedVector3Array()
	for x in range(-1, 2):
		for y in range(-1, 2):
			for z in range(-1, 2):
				var direction := Vector3(x, y, z)
				if direction == Vector3.ZERO:
					continue
				var best := -INF
				var extreme := Vector3.ZERO
				for point in points:
					var projection := point.dot(direction)
					if projection > best:
						best = projection
						extreme = point - center
				if not extremes.has(extreme):
					extremes.append(extreme)
	var bounds := _point_bounds(extremes)
	if extremes.size() < 4 or bounds.get_shortest_axis_size() < 0.006:
		var box := BoxShape3D.new()
		box.size = bounds.size.max(Vector3.ONE * 0.012)
		return box
	var shape := ConvexPolygonShape3D.new()
	shape.margin = 0.004
	shape.points = extremes
	return shape


static func _point_bounds(points: PackedVector3Array) -> AABB:
	var bounds := AABB(points[0], Vector3.ZERO)
	for i in range(1, points.size()):
		bounds = bounds.expand(points[i])
	return bounds


static func _limb_span(skeleton: Skeleton3D, index: int) -> float:
	var children := skeleton.get_bone_children(index)
	var span := skeleton.get_bone_rest(children[0] if not children.is_empty() else index).origin.length()
	return clampf(span, 0.16, 0.65)


static func _cut_branch(skeleton: Skeleton3D, index: int, severed: PackedInt32Array) -> bool:
	while index >= 0:
		if index in severed:
			return true
		index = skeleton.get_bone_parent(index)
	return false


static func _bone_points(corpse: Node3D, skeleton: Skeleton3D) -> Dictionary[int, PackedVector3Array]:
	var points: Dictionary[int, PackedVector3Array] = {}
	for mesh: MeshInstance3D in corpse.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or mesh.skin == null or mesh.get_node_or_null(mesh.skeleton) != skeleton:
			continue
		var indices := PackedInt32Array()
		var binds: Array[Transform3D] = []
		for i in mesh.skin.get_bind_count():
			var name := mesh.skin.get_bind_name(i)
			indices.append(skeleton.find_bone(name) if not name.is_empty() else mesh.skin.get_bind_bone(i))
			binds.append(mesh.skin.get_bind_pose(i))
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			if arrays.is_empty() or arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null:
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			if vertices.is_empty() or joints.size() != weights.size():
				continue
			var stride := floori(float(joints.size()) / vertices.size())
			if stride > 0 and joints.size() == vertices.size() * stride:
				_collect_points(vertices, joints, weights, stride, indices, binds, points)
	return points


static func _collect_points(vertices: PackedVector3Array, joints: PackedInt32Array,
		weights: PackedFloat32Array, stride: int, indices: PackedInt32Array, binds: Array[Transform3D],
		points: Dictionary[int, PackedVector3Array]) -> void:
	for i in vertices.size():
		var begin := i * stride
		var strongest := begin
		for j in range(begin + 1, begin + stride):
			if weights[j] > weights[strongest]:
				strongest = j
		var bind := joints[strongest]
		if bind < 0 or bind >= indices.size() or indices[bind] < 0 or weights[strongest] <= 0.0:
			continue
		var bone := indices[bind]
		var point := binds[bind] * vertices[i]
		if not points.has(bone):
			points[bone] = PackedVector3Array()
		points[bone].append(point)


static func _start_rigid(corpse: Node3D, momentum: Vector3) -> void:
	var bounds := AABB()
	var world_to_corpse := corpse.global_transform.affine_inverse()
	for mesh: MeshInstance3D in corpse.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh != null and mesh.is_visible_in_tree():
			var local_box := world_to_corpse * mesh.global_transform * mesh.get_aabb()
			bounds = bounds.merge(local_box) if bounds.has_volume() else local_box
	if not bounds.has_volume():
		return
	var body := RigidBody3D.new()
	body.name = "DeathRagdoll"
	body.collision_layer = 0
	body.collision_mask = WORLD_LAYER
	body.linear_damp = 0.45
	body.angular_damp = 1.45
	body.continuous_cd = true
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	var dimensions := bounds.size * corpse.global_transform.basis.get_scale().abs()
	capsule.radius = maxf(0.06, maxf(dimensions.x, dimensions.z) * 0.5)
	capsule.height = maxf(capsule.radius * 2.0, dimensions.y + 0.09)
	shape.shape = capsule
	body.add_child(shape)
	corpse.get_parent().add_child(body)
	body.global_transform = Transform3D(corpse.global_basis.orthonormalized(), corpse.to_global(bounds.get_center()))
	corpse.reparent(body, true)
	body.linear_velocity = momentum
	body.angular_velocity = Vector3.UP.cross(momentum) * 1.8
