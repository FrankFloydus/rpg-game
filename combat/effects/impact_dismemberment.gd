extends RefCounted
## Adapts the animated rigid pivots and skinned rigs to Engore's native cut API.

const ImpactFeedback := preload("res://data/impact_feedback.tres")
const LIMB_LIFETIME := 9.0
const CUT_BONES := &"engore_severed_bones"
const MODULAR_PREFIXES := ["armleft", "armright", "leftarm", "rightarm", "legleft", "legright",
	"leftleg", "rightleg", "wingleft", "wingright", "leftwing", "rightwing"]


static func sever_at(model: Node3D, world: Node3D, hit_point: Vector3, direction: Vector3,
		native_blood := false, overkill := 0.0, body_resistance := 1.0) -> bool:
	if not ClassDB.class_exists(&"GoreComponent"):
		return false
	var extent := ImpactFeedback.cut_extent(overkill, body_resistance)
	var budget := ImpactFeedback.cut_count(overkill, body_resistance)
	var velocity := direction.normalized() * ImpactFeedback.limb_launch_speed / body_resistance
	if _sever_skinned(model, world, hit_point, direction, extent, budget, velocity, native_blood):
		return true

	var detached := 0
	for row in _rigid_candidates(model, hit_point, direction, extent):
		if _sever_rigid(model, world, row.part, velocity, native_blood):
			detached += 1
			if detached >= budget:
				break
	return detached > 0


static func _sever_rigid(model: Node3D, world: Node3D, part: Node3D, velocity: Vector3,
		native_blood: bool) -> bool:
	var cut := Node3D.new()
	cut.name = "RigidModelCut"
	cut.visible = false
	model.add_child(cut, true)
	cut.global_transform = Transform3D(Basis.IDENTITY, part.global_position)
	var partition_source := _bind_rigid_meshes(part, cut.global_transform.affine_inverse())
	if partition_source.get_surface_count() == 0:
		cut.queue_free()
		return false

	var skeleton := Skeleton3D.new()
	skeleton.name = "ContactRig"
	skeleton.add_bone(&"pelvis")
	skeleton.add_bone(part.name)
	skeleton.set_bone_parent(1, 0)
	cut.add_child(skeleton)
	var skin := Skin.new()
	skin.add_bind(0, Transform3D.IDENTITY)
	skin.add_bind(1, Transform3D.IDENTITY)
	var mesh := MeshInstance3D.new()
	mesh.name = "CutSurface"
	mesh.mesh = partition_source
	mesh.skin = skin
	cut.add_child(mesh)
	mesh.skeleton = mesh.get_path_to(skeleton)
	skeleton.force_update_all_bone_transforms()

	var component := _prepare_cut(cut, mesh, skeleton, &"pelvis")
	var bones: Array[StringName] = [part.name]
	if not _launch_batch(component, world, bones, 1, velocity, native_blood).is_empty():
		part.hide()
		return true
	cut.queue_free()
	return false


static func _rigid_candidates(model: Node3D, hit_point: Vector3, direction: Vector3,
		extent: Vector2) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var travel := direction.normalized() * extent.y
	for candidate in model.find_children("*", "Node3D", true, false):
		if candidate is MeshInstance3D or not candidate.is_visible_in_tree():
			continue
		var name_key := String(candidate.name).to_lower().replace("_", "").replace("-", "")
		if not candidate.get_meta(&"gore_breakable_part", false) and not _is_limb(name_key):
			continue
		var minimum := INF
		for rendered: MeshInstance3D in candidate.find_children("*", "MeshInstance3D", true, false):
			if rendered.mesh == null or not rendered.is_visible_in_tree():
				continue
			var box := rendered.get_aabb()
			for point in [hit_point, hit_point - travel, hit_point + travel]:
				var contact := rendered.to_global(rendered.to_local(point).clamp(box.position, box.end))
				minimum = minf(minimum, contact.distance_squared_to(point))
		if minimum < extent.x * extent.x:
			candidates.append({"distance": minimum, "part": candidate})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.distance < b.distance)
	return candidates


static func _is_limb(name_key: String) -> bool:
	if name_key in ["head", "skull"]:
		return true
	for prefix: String in MODULAR_PREFIXES:
		if name_key.begins_with(prefix):
			return true
	return false


static func _sever_skinned(model: Node3D, world: Node3D, hit_point: Vector3, direction: Vector3,
		extent: Vector2, budget: int, velocity: Vector3, native_blood: bool) -> bool:
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.skin == null or mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if skeleton == null or skeleton.get_bone_count() < 2:
			continue
		var pelvis := skeleton.get_bone_name(0)
		for bone in skeleton.get_bone_count():
			var bone_name := skeleton.get_bone_name(bone)
			var name_key := String(bone_name).to_lower()
			if name_key == "pelvis" or name_key == "hips":
				pelvis = bone_name
				break
		skeleton.force_update_all_bone_transforms()
		var candidates := _weighted_limb_candidates(mesh, skeleton, hit_point, direction, extent)
		candidates.erase(pelvis)
		if candidates.is_empty():
			continue
		var overlay := mesh.material_overlay
		if model.has_method(&"overlay_without_hit_flash"):
			overlay = model.overlay_without_hit_flash(mesh)
		var component := _prepare_cut(model, mesh, skeleton, pelvis)
		var detached := _launch_batch(component, world, candidates, budget, velocity, native_blood, overlay)
		if not detached.is_empty():
			model.set_meta(CUT_BONES, detached)
			return true
		component.queue_free()
	return false


static func _closest_weighted_limb(mesh: MeshInstance3D, skeleton: Skeleton3D, point: Vector3) -> StringName:
	var candidates := _weighted_limb_candidates(mesh, skeleton, point, Vector3.ZERO,
		Vector2(ImpactFeedback.base_cut_radius, 0.0))
	return candidates.front() if not candidates.is_empty() else &""


static func _weighted_limb_candidates(mesh: MeshInstance3D, skeleton: Skeleton3D, point: Vector3,
		direction: Vector3, extent: Vector2) -> Array[StringName]:
	var bone_count := skeleton.get_bone_count()
	var canonical := PackedInt32Array()
	canonical.resize(bone_count)
	canonical.fill(-1)
	var positions := PackedVector3Array()
	positions.resize(bone_count)
	for bone in bone_count:
		var name_key := String(skeleton.get_bone_name(bone)).to_lower().replace("_", "").replace("-", "")
		var parent := skeleton.get_bone_parent(bone)
		if name_key.ends_with("bend") and parent >= 0:
			canonical[bone] = canonical[parent]
		elif _is_limb(name_key):
			canonical[bone] = bone
		positions[bone] = skeleton.to_global(skeleton.get_bone_global_pose(bone).origin)

	var weighted := _weighted_limb_roots(mesh, skeleton, canonical)
	var distances: Dictionary[int, float] = {}
	var swing_extension := direction.normalized() * extent.y
	var maximum_distance := extent.x * extent.x
	for bone in bone_count:
		var root := canonical[bone]
		if root < 0 or weighted[root] == 0:
			continue
		var origin := positions[bone]
		var parent := skeleton.get_bone_parent(bone)
		var endpoint := origin
		var has_limb_child := false
		for child in skeleton.get_bone_children(bone):
			if canonical[child] == root:
				endpoint = positions[child]
				has_limb_child = true
				break
		if not has_limb_child and parent >= 0:
			# The imported skeleton stores joints. Extend the last segment toward the
			# tip of a head or limb, which has no exported child joint of its own.
			var axis := origin - positions[parent]
			endpoint += axis.limit_length(0.31) * 0.73
		var contact := Geometry3D.get_closest_point_to_segment(point, origin, endpoint)
		var distance := point.distance_squared_to(contact)
		var directness := distance
		if extent.y > 0.0:
			var points := Geometry3D.get_closest_points_between_segments(
				point - swing_extension, point + swing_extension, origin, endpoint)
			distance = points[0].distance_squared_to(points[1])
		if distance < maximum_distance:
			# A limb directly under the blade comes before a limb found farther down its path.
			var score := distance + directness * 0.20
			distances[root] = minf(float(distances.get(root, INF)), score)
	var order := distances.keys()
	order.sort_custom(func(a: int, b: int) -> bool:
		var difference: float = distances[a] - distances[b]
		return a < b if is_zero_approx(difference) else difference < 0.0)
	var candidates: Array[StringName] = []
	for bone: int in order:
		candidates.append(skeleton.get_bone_name(bone))
	return candidates


static func _weighted_limb_roots(mesh: MeshInstance3D, skeleton: Skeleton3D,
		canonical: PackedInt32Array) -> PackedByteArray:
	var weighted := PackedByteArray()
	weighted.resize(canonical.size())
	var skin := mesh.skin
	var bind_roots := PackedInt32Array()
	bind_roots.resize(skin.get_bind_count())
	bind_roots.fill(-1)
	for bind in bind_roots.size():
		var bone := skin.get_bind_bone(bind)
		if not skin.get_bind_name(bind).is_empty():
			bone = skeleton.find_bone(skin.get_bind_name(bind))
		if bone >= 0 and bone < canonical.size():
			bind_roots[bind] = canonical[bone]
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		if arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null:
			continue
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for index in mini(indices.size(), weights.size()):
			var bind := indices[index]
			if weights[index] >= 0.34 and bind >= 0 and bind < bind_roots.size():
				var root := bind_roots[bind]
				if root >= 0:
					weighted[root] = 1
	return weighted


static func _prepare_cut(parent: Node3D, mesh: MeshInstance3D, skeleton: Skeleton3D, pelvis: StringName) -> Node3D:
	var component := ClassDB.instantiate(&"GoreComponent") as Node3D
	component.name = "NativeDismemberment"
	component.geometry_mode = 1
	component.limb_collision_layer = 0
	component.limb_collision_mask = 1
	component.limb_rigid_fallback_enabled = true
	component.limb_lifetime = LIMB_LIFETIME
	component.limb_mass = 0.85
	component.pelvis_bone_name = pelvis
	component.enable_blood_particles = false
	component.enable_blood_pool_decal = false
	component.enable_blood_skin_painting = false
	component.auto_apply_blood_material = false
	parent.add_child(component, true)
	component.skeleton_path = component.get_path_to(skeleton)
	component.set_skeletal_mesh_component_to_dismember(mesh)
	return component


static func _launch_batch(component: Node3D, world: Node3D, bones: Array[StringName], budget: int,
		velocity: Vector3, native_blood: bool, authored_overlay: Material = null) -> Array[StringName]:
	if not component.initialize():
		return []
	# The original Engore batch path stages all cuts on the same native
	# component. Its missing-bone map prevents moving already-severed geometry.
	var staged: Array[RigidBody3D] = []
	for bone in bones:
		var limb := component.stage_dismember_limb(bone) as RigidBody3D
		if limb == null:
			continue
		var pieces: Array[MeshInstance3D] = limb.get_meshes()
		if pieces.is_empty():
			limb.queue_free()
			continue
		for piece in pieces:
			piece.material_overlay = authored_overlay
		if limb.get_parent() != world:
			limb.reparent(world, true)
		staged.append(limb)
		if staged.size() >= budget:
			break
	var released: Array[StringName] = []
	component.enable_blood_particles = native_blood
	component.enable_blood_pool_decal = native_blood
	var mass_effect: PackedScene = component.blood_mass_sever_effect if staged.size() > 1 else null
	for limb in staged:
		var bone: StringName = limb.get_bone_name()
		var cut_point: Vector3 = limb.get_bone_transform().origin
		var separation := (cut_point - component.global_position).normalized() * 0.12
		var launch := velocity + separation + Vector3.UP * 0.12
		if component.release_staged_limb(limb, launch):
			released.append(bone)
			if native_blood:
				var effect := &"amputated_head" if String(bone).to_lower().contains("head") else &"amputated"
				var excluded: Array[RID] = [limb.get_rid()]
				component.emit_blood_effect_from_bone(effect, bone, launch.normalized(), 1, mass_effect, excluded)
				component.spawn_blood_droplets(cut_point, launch.normalized(), excluded)
	return released


static func _bind_rigid_meshes(part: Node3D, world_to_local: Transform3D) -> ArrayMesh:
	var combined := ArrayMesh.new()
	for visual: MeshInstance3D in part.find_children("*", "MeshInstance3D", true, false):
		if visual.mesh == null or visual.skin != null or not visual.is_visible_in_tree():
			continue
		var pose := world_to_local * visual.global_transform
		for surface in visual.mesh.get_surface_count():
			var arrays := visual.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			if vertices.size() < 3:
				continue
			arrays[Mesh.ARRAY_VERTEX] = pose * vertices
			_transform_shading(arrays, pose)
			var bones := PackedInt32Array()
			var weights := PackedFloat32Array()
			bones.resize(vertices.size() * 4)
			weights.resize(vertices.size() * 4)
			for vertex in vertices.size():
				bones[vertex * 4] = 1
				weights[vertex * 4] = 1.0
			arrays[Mesh.ARRAY_BONES] = bones
			arrays[Mesh.ARRAY_WEIGHTS] = weights
			combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			combined.surface_set_material(combined.get_surface_count() - 1, visual.get_active_material(surface))
	return combined


static func _transform_shading(arrays: Array, pose: Transform3D) -> void:
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var normal_basis := pose.basis.inverse().transposed()
	for index in normals.size():
		normals[index] = (normal_basis * normals[index]).normalized()
	if not normals.is_empty():
		arrays[Mesh.ARRAY_NORMAL] = normals
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	for index in range(0, tangents.size(), 4):
		var direction := (pose.basis * Vector3(tangents[index], tangents[index + 1], tangents[index + 2])).normalized()
		tangents[index] = direction.x
		tangents[index + 1] = direction.y
		tangents[index + 2] = direction.z
	if not tangents.is_empty():
		arrays[Mesh.ARRAY_TANGENT] = tangents
