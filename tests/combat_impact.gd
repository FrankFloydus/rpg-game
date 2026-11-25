extends SceneTree
## Exercises the camera and native impact effects in the playable Training Ground.

const Game := preload("res://main.tscn")
const Enemies := preload("res://combat/enemies/enemy_catalog.gd")
const Items := preload("res://systems/items.gd")
const Impact := preload("res://combat/effects/combat_impact.gd")
const Dismemberment := preload("res://combat/effects/impact_dismemberment.gd")
const WeaponRoles := preload("res://combat/weapons/weapon_roles.gd")
const CombatFloaters := preload("res://combat/effects/combat_floaters.gd")
const Bleed := preload("res://combat/effects/bleed.tres")
const MeleeSweep := preload("res://player/melee_sweep.gd")

var _game: Node3D
var _checks := 0
var _failures := 0
var _capture_directory := ""


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			_capture_directory = argument.trim_prefix("--capture-dir=")
	_run.call_deferred()


func _run() -> void:
	_game = Game.instantiate()
	_game.save_enabled = false
	_game.save_directory = "user://test_runs/combat_impact_%d" % OS.get_process_id()
	_game.preferences_path = _game.save_directory.path_join("settings.cfg")
	root.add_child(_game)
	current_scene = _game
	_game._create_character(0, "Impact Fixture")
	_game._enter_training_ground()
	await _physics_ticks(3)
	_check(ClassDB.class_exists(&"BloodDecalLibrary")
		and ClassDB.class_has_method(&"GoreComponent", &"spawn_blood_droplets"),
		"Engore registers the textured decals and native droplet solver")
	await _test_camera()
	await _test_impacts()
	await _test_weapon_deaths()
	await _test_overkill_feedback()
	await _test_floaters()
	var ground := _game.training_ground as Node3D
	_game._leave_training_ground()
	await _physics_ticks(2)
	_check(not is_instance_valid(ground) and _game.find_children("*", "DismemberedLimb", true, false).is_empty(),
		"Leaving the arena removes its blood, impact effects and detached limbs")
	var departed := Node3D.new()
	_game.add_child(departed)
	Impact.contact(departed, Vector3.ZERO, Vector3.UP, &"stone")
	departed.free()
	await _physics_ticks(1)
	_check(_game.find_children("StoneImpact*", "Node3D", true, false).is_empty(),
		"A deferred strike cannot leave a transient effect after its world has been released")
	_game.free()
	await process_frame
	print("Hearth Below combat impact: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_camera() -> void:
	var player := _game.player as CharacterBody3D
	var effects := player.get_node("CameraFeedback")
	var marker := effects.get_node("DamageIndicator")
	var lens := effects.get_node("LensBlood")
	var vignette := effects.get_node("DamageVignette")
	var source := _make_thrall(player.global_position + Vector3(3.3, 0.0, -2.4))
	player.stats["dodge_chance"] = 0.0
	player.stats["armor"] = 0.0
	player.ward = 0.0
	var hit: bool = player.receive_enemy_hit(player.life * 0.8, "physical", "", source)
	_check(hit and marker._markers.size() == 1 and not lens._marks.is_empty(),
		"A real physical hit displays directional feedback and blood on the lens")
	_check(vignette.is_processing() and vignette._health_fraction < 0.25,
		"Low life enables the Crimson Carnage warning")
	await _physics_ticks(19)
	await _capture("camera_hit_low_life")
	player.restore_full()
	_check(marker._markers.is_empty() and lens._marks.is_empty() and not vignette.is_processing(),
		"Full recovery clears the warning, indicator and lens blood")
	var forward := -player.global_basis.z
	var distant := _make_thrall(player.global_position + forward * 3.40)
	distant.died.connect(_game._training_enemy_died)
	distant.take_damage(distant.max_health + 5.0)
	_check(lens._marks.is_empty(), "An enemy death outside three meters leaves the lens clear")
	var nearby := _make_thrall(player.global_position + forward * 2.15)
	nearby.died.connect(_game._training_enemy_died)
	nearby.take_damage(1.0)
	_check(lens._marks.is_empty(), "A nonlethal enemy hit does not trigger death splatter")
	nearby.take_damage(nearby.max_health + 5.0)
	_check(lens._marks.size() == 9 and marker._markers.is_empty() and not vignette.is_processing(),
		"A close flesh death plays Crimson's first drop batch without an incoming damage prompt")
	await _physics_ticks(16)
	_check(lens._marks.size() == 21, "The 0.05 s and 0.15 s Crimson drop bursts follow a close death")
	await _capture("camera_close_flesh_death")
	player.restore_full()
	distant.queue_free()
	nearby.queue_free()
	source.queue_free()
	await _physics_ticks(2)


func _test_impacts() -> void:
	var player := _game.player as CharacterBody3D
	var arena := _game.training_ground as Node3D
	var actors := _game._training_actors as Node3D
	var start: Vector3 = arena.enemy_spawn_points[0]
	var thrall := _make_thrall(start)
	var skin := thrall.find_child("EnemySkin", true, false) as MeshInstance3D
	var skeleton := skin.get_node_or_null(skin.skeleton) as Skeleton3D if skin != null else null
	var original_mesh := skin.mesh if skin != null else null
	var head := thrall.get_node_or_null("Model/Rig/Head") as Node3D
	var joint := skeleton.find_bone(&"Head") if skeleton != null else -1
	if not _check(joint >= 0 or (head != null and head.is_visible_in_tree()),
			"The playable Thrall has a hittable head on its active rig"):
		return
	var aim := skeleton.to_global(skeleton.get_bone_global_pose(joint).origin) if joint >= 0 else head.global_position
	if skeleton != null:
		_test_bend_target(skin, skeleton)
	var offset := Vector3(0.8, 0.0, 2.7)
	var toward := -offset.normalized()
	player.place_at(start + offset, atan2(-toward.x, -toward.z), 0.10)
	var travel: Vector3 = (aim - player.camera.global_position).normalized()
	thrall.take_damage(1.0, "physical", player, aim, travel)
	await _physics_ticks(34)
	var gore := actors.get_node_or_null("ContactGore")
	var library: Array = gore.blood_decal_libraries if gore != null else []
	_check(not library.is_empty() and library[0].resource_path.ends_with("/blood_deposits/deposits.tres")
		and is_equal_approx(gore.blood_pool_scale, 1.0),
		"Ordinary flesh hits use the realistic demo decal library at its authored scale")
	var floor := arena.get_node("Courtyard/StaticBody3D1")
	var pool := _floor_decal(floor)
	_check(pool != null and is_equal_approx(pool.max_lifetime, 60.0),
		"The native droplet solver attaches a realistic deposit to the arena floor")
	if DisplayServer.get_name() != "headless":
		var receiver := arena.get_node("Courtyard/BloodProjection")
		_check(receiver._has_bound_material() and not receiver._projections.is_empty(),
			"Forward+ draws wet blood through the demo's Surface Finish receiver")
	var attached: bool = skin.mesh == original_mesh if joint >= 0 else head.is_visible_in_tree()
	_check(attached and actors.find_children("*", "DismemberedLimb", true, false).is_empty(),
		"An ordinary nonlethal blade hit leaves the limb attached")
	var blade := WeaponRoles.contact("sword_1h", "oath_blade", true, {"direction": travel})
	thrall.take_damage(0.1, "physical", player, aim, travel, blade)
	thrall.take_damage(thrall.max_health, "cold", player, aim, travel, blade)
	var cut_flash := skin.material_overlay if skin != null else null
	await _physics_ticks(2)
	var limbs := actors.find_children("*", "DismemberedLimb", true, false)
	var has_geometry: bool = not limbs.is_empty() and not limbs[0].get_meshes().is_empty()
	attached = skin.mesh == original_mesh if joint >= 0 else head.is_visible_in_tree()
	_check(has_geometry and not attached,
		"A blade's lethal typed damage severs even after a same-frame primary hit")
	if not has_geometry:
		return
	var limb := limbs[0] as RigidBody3D
	var detached_flash := false
	for piece: MeshInstance3D in limb.get_meshes():
		detached_flash = detached_flash or (cut_flash != null and piece.material_overlay == cut_flash)
	_check(cut_flash != null and not detached_flash,
		"The native cut keeps the detached mesh's authored material without copying its temporary hit flash")
	var cut_position := limb.global_position
	_check(limb.get_parent() == actors and not limb.freeze
		and not limb.find_children("*", "CollisionShape3D", true, false).is_empty(),
		"Detached head is a world-owned, unfrozen rigid body with its own collider")
	await _physics_ticks(8)
	await _capture("engore_fatal_hit")
	thrall.global_position += Vector3.RIGHT * 35.0
	await _physics_ticks(32)
	_check(is_instance_valid(limb) and limb.global_position.distance_to(cut_position) > 0.14
		and limb.global_position.distance_to(cut_position) < 8.0 and limb.global_position.y > start.y - 0.15,
		"Detached limb continues moving independently after the parent moves away and expires")
	if is_instance_valid(limb):
		var settled := limb.global_position
		player.place_at(Vector3(settled.x, start.y, settled.z + 1.8), 0.0, -0.72)
	await _capture("engore_detached_limb_landed")

	var point := start + Vector3(0.0, 0.0, 1.1)
	player.place_at(point + Vector3(0.0, 0.0, 2.3), 0.0, -0.6)
	Impact.world(player, point, Vector3.UP)
	await _physics_ticks(5)
	var stone := arena.get_node_or_null("StoneImpact")
	_check(stone != null and stone.get_node_or_null("Chips") is GPUParticles3D
		and stone.get_node_or_null("Dust") is GPUParticles3D
		and stone.global_position.is_equal_approx(point + Vector3.UP * 0.025),
		"World impacts emit GPU chips and dust at the supplied contact")
	await _capture("stone_contact")
	await _physics_ticks(49)
	_check(not is_instance_valid(stone), "A one-shot world impact cleans itself up")


func _test_weapon_deaths() -> void:
	var player := _game.player as CharacterBody3D
	var arena := _game.training_ground as Node3D
	var actors := _game._training_actors as Node3D
	var start: Vector3 = arena.enemy_spawn_points[0]
	var one_handed := _make_thrall(start + Vector3.BACK * 2.0)
	var two_handed := _make_thrall(start + Vector3.FORWARD * 2.0)
	var thrust_target := _make_thrall(start + Vector3.LEFT * 2.0)
	var ordinary_target := _make_thrall(start)
	var travel := Vector3.RIGHT
	var thrust := WeaponRoles.contact("sword_1h", "funeral_rapier", false,
		{"direction": travel, "blade_axis": travel})
	var rapier_cut := WeaponRoles.contact("sword_1h", "funeral_rapier", false,
		{"direction": travel, "blade_axis": Vector3.FORWARD})
	_check(not WeaponRoles.can_sever(thrust) and WeaponRoles.can_sever(rapier_cut),
		"An axial rapier thrust and a lateral cut have distinct contact profiles")

	var previous_limbs := actors.find_children("*", "DismemberedLimb", true, false).size()
	var victims: Dictionary[CharacterBody3D, Dictionary] = {
		one_handed: WeaponRoles.contact("mace_1h", "pilgrim_cudgel", false, {}),
		two_handed: WeaponRoles.contact("mace_2h", "quarry_maul", false, {}),
		thrust_target: thrust,
		ordinary_target: {},
	}
	for victim: CharacterBody3D in victims:
		var point: Vector3 = victim.aim_point()
		var skin := victim.find_child("EnemySkin", true, false) as MeshInstance3D
		var skeleton := skin.get_node_or_null(skin.skeleton) as Skeleton3D if skin != null else null
		var bone := skeleton.find_bone(&"Head") if skeleton != null else -1
		if bone >= 0:
			point = skeleton.to_global(skeleton.get_bone_global_pose(bone).origin)
		victim.take_damage(victim.max_health * 2.0, "physical", player, point, travel, victims[victim])
	await _physics_ticks(2)
	var one_body := one_handed.find_child("Body_Pelvis", true, false) as PhysicalBone3D
	var two_body := two_handed.find_child("Body_Pelvis", true, false) as PhysicalBone3D
	if _check(one_body != null and two_body != null, "Both blunt kills start articulated ragdolls"):
		var one_speed := one_body.linear_velocity.dot(travel)
		var two_speed := two_body.linear_velocity.dot(travel)
		_check(one_speed > 1.3 and two_speed > one_speed * 1.25,
			"Blunt fatal impacts direct the corpse along the strike, with greater two-handed momentum")
	_check(actors.find_children("*", "DismemberedLimb", true, false).size() == previous_limbs,
		"Blunt, thrust, and non-weapon kills leave body parts attached")


func _test_overkill_feedback() -> void:
	var player := _game.player as CharacterBody3D
	var arena := _game.training_ground as Node3D
	var origin: Vector3 = arena.enemy_spawn_points[0] + Vector3(-2.5, 0.0, 5.0)
	var axe := WeaponRoles.contact("axe_1h", "grave_hatchet", false, {"direction": Vector3.RIGHT})
	var cuts: Array[int] = []
	for index in range(3):
		var enemy := _make_thrall(origin + Vector3.RIGHT * index * 2.5)
		enemy.set_physics_process(false)
		var model := enemy.get_node("Model") as Node3D
		if index == 2:
			_enlarge_body(enemy, model)
		var skeleton := enemy.find_child("Skeleton3D", true, false) as Skeleton3D
		if skeleton == null:
			_check(false, "The overkill fixture uses a skinned native rig")
			return
		var left := -1
		var right := -1
		for bone in skeleton.get_bone_count():
			var label := String(skeleton.get_bone_name(bone)).to_lower()
			if not label.contains("arm") or not label.ends_with("bend"):
				continue
			var parent := skeleton.get_bone_parent(bone)
			if label.contains("left"):
				left = parent
			elif label.contains("right"):
				right = parent
		if not _check(left >= 0 and right >= 0, "An edged cut has two separate shoulder branches"):
			return
		var first := skeleton.to_global(skeleton.get_bone_global_pose(left).origin)
		var second := skeleton.to_global(skeleton.get_bone_global_pose(right).origin)
		var travel := first.direction_to(second)
		var point := first if index == 0 else first.lerp(second, 0.5)
		if index == 1 and not _capture_directory.is_empty():
			player.place_at(enemy.global_position + Vector3.BACK * 3.7, 0.0, -0.19)
			var capture_light := OmniLight3D.new()
			capture_light.light_color = Color(0.90, 0.79, 0.65)
			capture_light.light_energy = 1.2
			capture_light.omni_range = 6.0
			enemy.get_parent().add_child(capture_light)
			capture_light.global_position = enemy.global_position + Vector3(-0.7, 2.0, 2.0)
		enemy.health = 8.0
		enemy.take_damage(8.0 if index == 0 else 32.0, "physical", player, point, travel, axe)
		await _physics_ticks(2)
		var component := model.get_node_or_null("NativeDismemberment")
		var bones: Array = model.get_meta(&"engore_severed_bones", [])
		var detached: Array = component.get_all_dismembered_limbs() if component != null else []
		cuts.append(bones.size())
		var tracked := not detached.is_empty()
		for limb in detached:
			tracked = tracked and limb.get_parent() == _game._training_actors \
				and not limb.freeze and not limb.get_meshes().is_empty()
		_check(tracked and detached.size() == bones.size(), "A lethal staged batch launches each selected limb")
		for bone: StringName in bones:
			_check(enemy.find_child("Body_" + String(bone), true, false) == null,
				"The source ragdoll excludes detached " + String(bone))
		if index == 1 and not _capture_directory.is_empty():
			await _physics_ticks(4)
			await _capture("engore_overkill_impact")
			await _physics_ticks(60)
			await _capture("engore_overkill_settled")
	_check(cuts[0] == 1 and cuts[1] > 1 and cuts[2] < cuts[1],
		"An exact kill cuts one limb, overkill cuts several, and a larger body resists the extra cuts")

	var blunt := WeaponRoles.contact("mace_1h", "pilgrim_cudgel", false, {})
	var speeds: Array[float] = []
	for index in range(3):
		var enemy := _make_thrall(origin + Vector3.FORWARD * 3.0 + Vector3.RIGHT * index * 2.5)
		enemy.set_physics_process(false)
		if index == 2:
			_enlarge_body(enemy, enemy.get_node("Model"))
		enemy.health = 8.0
		enemy.take_damage(8.0 if index == 0 else 32.0, "physical", player, enemy.aim_point(), Vector3.RIGHT, blunt)
		await _physics_ticks(2)
		var pelvis := enemy.find_child("Body_Pelvis", true, false) as PhysicalBone3D
		speeds.append(pelvis.linear_velocity.dot(Vector3.RIGHT) if pelvis != null else 0.0)
	_check(speeds[0] > 0.0 and speeds[1] > speeds[0] * 1.35 and speeds[2] < speeds[1] * 0.8,
		"Excess resolved damage launches a small corpse faster and body volume reduces that push")
	var charged := WeaponRoles.contact("mace_1h", "pilgrim_cudgel", true, {})
	_check(WeaponRoles.blunt_death_momentum(blunt, Vector3.RIGHT, 15.0)
		.is_equal_approx(WeaponRoles.blunt_death_momentum(charged, Vector3.RIGHT, 15.0)),
		"The same resolved overkill launches equally for light and charged attacks of one weapon")


func _enlarge_body(enemy: CharacterBody3D, model: Node3D) -> void:
	var shape := enemy.get_node("BodyCollision").shape as CapsuleShape3D
	shape.radius *= 1.7
	shape.height *= 1.7
	model.scale *= 1.7


func _floor_decal(floor: Node3D) -> Node:
	for pool in floor.find_children("*", "BloodPool", true, false):
		if pool.global_basis.y.y > 0.9 and pool.decal_size.x > 0.0:
			return pool
	return null


func _test_bend_target(mesh: MeshInstance3D, skeleton: Skeleton3D) -> void:
	for joint in skeleton.get_bone_count():
		var name_key := String(skeleton.get_bone_name(joint)).to_lower()
		if not name_key.contains("arm") or not name_key.ends_with("bend"):
			continue
		var position := skeleton.to_global(skeleton.get_bone_global_pose(joint).origin)
		var canonical := skeleton.get_bone_name(skeleton.get_bone_parent(joint))
		_check(Dismemberment._closest_weighted_limb(mesh, skeleton, position) == canonical,
			"A hit near the weighted bend selects its parent arm")
		return
	_check(false, "The Thrall includes a weighted arm bend joint")


func _test_floaters() -> void:
	_game._reset_training_combat()
	var player: CharacterBody3D = _game.player
	player.place_at(Vector3(0, 0.08, 5))
	player.restore_full()
	player.stats.merge({"damage_min": 2.0, "damage_max": 2.0, "fire_damage": 1.0,
		"crit_chance": 0.0, "dodge_chance": 0.0}, true)
	var normal_target := _make_thrall(Vector3(-0.76, 0.08, 2.1))
	var crit_target := _make_thrall(Vector3(0.80, 0.08, 2.08))
	normal_target.max_health = 50.0
	normal_target.health = 50.0
	await _physics_ticks(2)
	var normal_point: Vector3 = normal_target.aim_point() + Vector3.UP * 0.18
	var normal_contacts: Array[Dictionary] = [{"target": normal_target, "point": normal_point,
		"direction": Vector3.FORWARD}]
	player._resolve_attack(false, {}, null, normal_contacts, {"count": 0})
	var labels := get_nodes_in_group(CombatFloaters.FLOAT_GROUP)
	if not _check(labels.size() == 1, "Mixed physical and fire damage show as one floating number"):
		return
	var normal := labels[0] as Label3D
	_check(normal.text == "3" and normal.modulate == Color.WHITE
		and normal.global_position.distance_to(normal_point) < 0.36,
		"The white number starts at the actual world impact")
	var rng := RandomNumberGenerator.new()
	var critical_seed := 0
	for trial_seed in range(100):
		rng.seed = trial_seed
		if rng.randf() < 0.75:
			critical_seed = trial_seed
			break
	player._rng.seed = critical_seed
	player.stats.crit_chance = 75.0
	crit_target.health = 1.0
	var critical_contacts: Array[Dictionary] = [{"target": crit_target,
		"point": crit_target.aim_point() + Vector3.UP * 0.18, "direction": Vector3.FORWARD}]
	player._resolve_attack(false, {}, null, critical_contacts, {"count": 0})
	labels = get_nodes_in_group(CombatFloaters.FLOAT_GROUP)
	if not _check(labels.size() == 2, "A critical hit adds one separate floater"):
		return
	var critical := labels[1] as Label3D
	_check(crit_target.health == 0.0 and critical.text == "6" and critical.font_size == normal.font_size
		and critical.modulate.b < normal.modulate.b,
		"A lethal mixed crit shows its full damage, even when the target only had one Life")
	var critical_event: Dictionary = _game._combat_events.back()
	_check(is_equal_approx(float(critical_event.amount), 6.0)
		and String(critical_event.detail).contains("1 Life lost"),
		"The log reports the full mitigated hit and records the smaller Life loss")
	var starting_critical_position := critical.global_position
	normal_target.receive_combat_effect(Bleed, 5.0, 1.0, player, {})
	normal_target._update_statuses(0.2)
	normal_target._update_statuses(0.2)
	_check(get_nodes_in_group(CombatFloaters.FLOAT_GROUP).size() == 3,
		"Sub-point ticks accumulate without showing fractional damage")
	_check(normal_target.health == 47.0, "Sub-point ticks carry forward before changing enemy Life")
	normal_target._update_statuses(0.2)
	labels = get_nodes_in_group(CombatFloaters.FLOAT_GROUP)
	_check(labels.size() == 4 and labels[2].text == "Bleeding" and labels[3].text == "1"
		and labels[3].font_size < normal.font_size and normal_target.health == 46.0,
		"The first whole Bleed tick applies one damage and floats in smaller text")
	player.receive_enemy_hit(1.0, "physical", "", normal_target)
	_check(get_nodes_in_group(CombatFloaters.FLOAT_GROUP).size() == labels.size(),
		"Enemy hits never produce damage numbers")
	player._present_melee_terrain(false, MeleeSweep.new("sword_1h", false, player.get_rid(),
		player.get_aim_transform()), Vector3.INF)
	_check(get_nodes_in_group(CombatFloaters.FLOAT_GROUP).size() == labels.size(),
		"An empty melee swing creates no combat text")
	_check(critical.scale == Vector3.ONE * 3.0 and critical.modulate.a == 1.0,
		"The critical number appears instantly at three times regular size and full opacity")
	await _capture("crit_impact")
	await _physics_ticks(7)
	_check(is_instance_valid(critical) and critical.scale.x > 1.15 and critical.scale.x < 2.9
		and is_equal_approx(critical.scale.x, critical.scale.y) and critical.modulate.a == 1.0
		and critical.global_position.is_equal_approx(starting_critical_position),
		"The critical number shrinks immediately after the impact snap while staying anchored")
	await _physics_ticks(22)
	_check(critical.global_position.is_equal_approx(starting_critical_position) and critical.modulate.a == 1.0
		and is_equal_approx(critical.scale.x, 1.0), "The critical number settles and stays readable at impact")
	await _capture("crit_hold")
	await _physics_ticks(27)
	_check(is_instance_valid(critical) and critical.global_position.is_equal_approx(starting_critical_position)
		and is_equal_approx(critical.scale.x, 1.0) and critical.modulate.a > 0.0 and critical.modulate.a < 0.8,
		"The critical number fades at the same position and size after its hold")
	await _capture("crit_release")
	await _physics_ticks(25)
	_check(get_nodes_in_group(CombatFloaters.FLOAT_GROUP).is_empty(),
		"Numbers and combat outcomes disappear after their animation")
	player.stats.merge({"damage_min": 1.0, "damage_max": 1.0, "fire_damage": 0.0}, true)
	player._rng.seed = critical_seed
	var before_low_crit: float = normal_target.health
	player._resolve_attack(false, {}, null, normal_contacts, {"count": 0})
	labels = get_nodes_in_group(CombatFloaters.FLOAT_GROUP)
	_check(labels.size() == 1 and labels[0].text == "2" and before_low_crit - normal_target.health == 2.0,
		"A one-damage roll crits for two against an unarmoured peer")
	var before_glancing: float = normal_target.health
	var glancing: Dictionary = normal_target.take_hit({"physical": 0.04}, player)
	player.report_enemy_hit(normal_target, normal_point, glancing, {"name": "Test hit", "description": ""})
	labels = get_nodes_in_group(CombatFloaters.FLOAT_GROUP)
	_check(labels.size() == 2 and labels[1].text == "Glancing" and normal_target.health == before_glancing,
		"Actual enemy contact below the rounding threshold shows Glancing and deals zero damage")
	var mixed: Dictionary = normal_target.take_hit({"physical": 0.4, "fire": 0.4}, player)
	_check(mixed.amount == 1 and mixed.dealt == 1.0 and normal_target.health == before_glancing - 1.0,
		"Two damage types are summed before rounding once and deducting Life")
	var equipped := {"main_hand": {"type": "sword_1h", "stats": {"crit_multiplier": 20.0}}}
	var totals := Items.player_stats(equipped)
	player.stats.merge({"damage_min": 3.0, "damage_max": 3.0, "crit_multiplier": totals.crit_multiplier}, true)
	player._rng.seed = critical_seed
	var before_bonus_crit: float = normal_target.health
	player._resolve_attack(false, {}, null, normal_contacts, {"count": 0})
	_check(totals.crit_multiplier == 220.0 and before_bonus_crit - normal_target.health == 7.0,
		"A +20% Critical Damage affix adds 20 points to the multiplier and rounds 6.6 damage to seven")


func _make_thrall(point: Vector3) -> CharacterBody3D:
	var thrall := Enemies.instantiate(0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 10235
	thrall.setup(_game.player, 1, "normal", rng)
	thrall.position = point
	_game._training_actors.add_child(thrall)
	thrall.set_physics_process(false)
	return thrall


func _physics_ticks(ticks: int) -> void:
	for _tick in ticks:
		await physics_frame


func _capture(filename: String) -> void:
	if _capture_directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path := _capture_directory.path_join(filename + ".png")
	_check(root.get_texture().get_image().save_png(path) == OK, "Captured " + filename)


func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: ", description)
	return condition
