extends SceneTree
## Checks terrain contact and the timed lifetime of actual enemy corpses.

const Catalog := preload("res://combat/enemies/enemy_catalog.gd")

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var ground := Node3D.new()
	root.add_child(ground)
	var floor_body := StaticBody3D.new()
	floor_body.position.y = -0.15
	ground.add_child(floor_body)
	var floor_collision := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(40.0, 0.3, 40.0)
	floor_collision.shape = floor_box
	floor_body.add_child(floor_collision)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31415
	var actors: Array[CharacterBody3D] = []
	var selected_affixes: Array[String] = ["volatile"]
	for index in Catalog.ARCHETYPES.size():
		var actor := Catalog.instantiate(index)
		if index == 0:
			actor.setup(null, 4, "rare", rng, Callable(), Callable(), selected_affixes)
		actor.position = Vector3(float(index % 5) * 5.0 - 10.0, 0.0, floorf(float(index) / 5.0) * 5.0 - 7.5)
		ground.add_child(actor)
		actor.set_physics_process(false)
		actors.append(actor)
	await _ticks(3)

	var volatile_events: Array[StringName] = []
	actors[0].combat_event.connect(func(event: Dictionary):
		if event["ability"] == "Volatile":
			volatile_events.append(event["kind"])
	)
	for actor in actors:
		actor.take_damage(actor.max_health * 20.0)
		if actor.is_cocoon():
			_check(actor.is_in_group("enemies") and actor.get_node_or_null("CorpseLifetime") == null,
				"A cocoon stays alive until its own Life is exhausted")
			actor.take_damage(actor.max_health * 20.0)
	await _ticks(180)

	for actor in actors:
		_check_corpse(actor)
	_check(volatile_events == [&"cast_start", &"cast_end"],
		"Volatile still completes its explosion before the corpse expires")
	for index in range(1, actors.size()):
		if index != 9:
			actors[index].queue_free()
	await _check_lifetime(actors[0], actors[9])
	ground.queue_free()
	await process_frame
	print("Hearth Below enemy ragdolls: %d archetypes, %d failures" % [actors.size(), _failures])
	quit(0 if _failures == 0 else 1)


func _check_corpse(actor: CharacterBody3D) -> void:
	var label: String = actor.display_name
	_check(actor.collision_layer == 0 and actor.collision_mask == 0 and not actor.is_in_group("enemies"),
		label + " leaves combat and player collision immediately")
	var body := actor.find_child("DeathRagdoll", true, false)
	if actor.archetype_id == 9:
		_check(body is RigidBody3D and body.global_position.y > 0.0 and body.global_position.y < 1.1,
			label + " leaves a physically grounded cocoon")
		return
	if not _check(body is PhysicalBoneSimulator3D and body.is_simulating_physics(),
			label + " is driven by its own skeleton and physics"):
		return
	_check(body.get_child_count() >= 4, label + " has articulated bone bodies")
	for bone: PhysicalBone3D in body.get_children():
		_check(bone.get_bone_id() >= 0 and bone.collision_layer == 0 and bone.collision_mask == 1,
			label + " " + String(bone.name) + " collides only with level geometry")
		_check(bone.global_position.y > -0.18 and bone.global_position.is_finite(),
			label + " " + String(bone.name) + " stays at the floor")
	match actor.archetype_id:
		2: _check_grounded_skin(actor, body, 0.41, 0.70)
		3, 7: _check_grounded_skin(actor, body, 0.29, 0.60)
		15: _check_grounded_skin(actor, body, 0.50, 0.95)


func _check_grounded_skin(actor: CharacterBody3D, simulator: PhysicalBoneSimulator3D,
		max_trunk_height: float, max_skin_height: float) -> void:
	var trunk := simulator.get_node("Body_Pelvis") as PhysicalBone3D
	var skeleton := simulator.get_parent() as Skeleton3D
	var minimum := INF
	var maximum := -INF
	for mesh: MeshInstance3D in actor.find_children("*", "MeshInstance3D", true, false):
		if not mesh.is_visible_in_tree() or mesh.skin == null or mesh.mesh == null:
			continue
		var transforms: Array[Transform3D] = []
		for bind in mesh.skin.get_bind_count():
			var bone := mesh.skin.get_bind_bone(bind)
			var bind_name := mesh.skin.get_bind_name(bind)
			if not bind_name.is_empty():
				bone = skeleton.find_bone(bind_name)
			transforms.append(_bone_world(skeleton, simulator, bone) * mesh.skin.get_bind_pose(bind))
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var joints: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var stride := floori(float(joints.size()) / maxi(1, vertices.size()))
			for index in vertices.size():
				var height := 0.0
				for influence in stride:
					var slot := index * stride + influence
					var weight := weights[slot]
					if weight > 0.0:
						height += (transforms[joints[slot]] * vertices[index]).y * weight
				minimum = minf(height, minimum)
				maximum = maxf(height, maximum)
	_check(trunk.global_position.y < max_trunk_height
		and minimum > -0.075 and minimum < 0.08 and maximum < max_skin_height,
		"%s must settle against the terrain: skin %.3f to %.3f m, trunk %.3f m" %
		[actor.display_name, minimum, maximum, trunk.global_position.y])


func _bone_world(skeleton: Skeleton3D, simulator: PhysicalBoneSimulator3D, bone: int) -> Transform3D:
	var physics_bone := simulator.get_node_or_null("Body_" + String(skeleton.get_bone_name(bone))) as PhysicalBone3D
	if physics_bone != null:
		return physics_bone.global_transform * physics_bone.body_offset.affine_inverse()
	var parent := skeleton.get_bone_parent(bone)
	if parent < 0:
		return skeleton.global_transform * skeleton.get_bone_pose(bone)
	return _bone_world(skeleton, simulator, parent) * skeleton.get_bone_pose(bone)


func _check_lifetime(volatile_corpse: CharacterBody3D, broken_cocoon: CharacterBody3D) -> void:
	var timer := volatile_corpse.get_node("CorpseLifetime") as Timer
	var cocoon_timer := broken_cocoon.get_node("CorpseLifetime") as Timer
	_check(timer.wait_time >= 120.0 and is_equal_approx(cocoon_timer.wait_time, timer.wait_time),
		"Enemy corpses and broken cocoons both have a lifetime of at least two minutes")
	var unpaused_time := timer.time_left
	paused = true
	await _ticks(60)
	_check(is_equal_approx(timer.time_left, unpaused_time), "Corpse lifetime advances only during gameplay")
	paused = false
	var threshold := floori((unpaused_time - 0.20) * Engine.physics_ticks_per_second)
	await _ticks(threshold)
	_check(is_instance_valid(volatile_corpse) and is_instance_valid(broken_cocoon),
		"Volatile corpse and broken cocoon both persist until almost the full corpse lifetime")
	await _ticks(25)
	_check(not is_instance_valid(volatile_corpse) and not is_instance_valid(broken_cocoon),
		"Both corpses expire after the configured gameplay lifetime")


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_failures += 1
		push_error(message)
	return condition


func _ticks(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame
