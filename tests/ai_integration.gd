extends SceneTree
## Exercises the native AI through playable Hearth Below expeditions.

const Game = preload("res://main.tscn")
const Enemy = preload("res://combat/enemies/enemy.gd")
const Catalog = preload("res://combat/enemies/enemy_catalog.gd")
const Projectile = preload("res://combat/effects/enemy_projectile.gd")
const EXPEDITION_SEED := 7395045
const NATIVE_ATTACK := "telegraph_commit_recover"
const NATIVE_MOVE := "move_to_goal_with_recovery"
const NATIVE_PATROL := "patrol_route"

var _game: Node3D
var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_game = Game.instantiate()
	_game.save_enabled = false
	root.add_child(_game)
	_check(_game.title_screen.is_open(), "Project boots through the title screen")
	_game._create_character(0, "AI Tester")
	await _enter_depth(1)
	if _check(_game.in_dungeon and int(_game.run.get("level", 0)) == 1, "The altar enters Depth I"):
		_check_native_scene(1)
		await _check_patrol_and_portal()
		await _check_attack(false)
		await _check_attack(true)
		for floor_index in _game._dungeon_floor_count():
			for enemy: Node3D in _game._enemies.values():
				enemy.take_damage(100000.0, "physical", _game.player)
			if floor_index + 1 < _game._dungeon_floor_count():
				var geometry: Node3D = _game._dungeon_floors[floor_index + 1].geometry
				_game.player.place_at(geometry.to_global(geometry.spawn_position))
				_game._track_dungeon_floor()
				await _wait_for_navigation()
				_check_native_scene(1)
		_check(_game.unlocked == 2 and _game.run.cleared, "Defeating every floor's native roster unlocks Depth II")
		_game._enter_hub()
		_game.hud.leave_requested.emit()
		await _enter_depth(2)
		if _check(_game.in_dungeon and int(_game.run.get("level", 0)) == 2, "The altar enters the unlocked Depth II"):
			_check_native_scene(2)
	_game.free()
	await _ticks(2)
	print("Hearth Below native AI integration: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _enter_depth(depth: int) -> void:
	await _ticks(6)
	var altar: Vector3 = _game.hub.interaction_position("altar")
	_game.player.place_at(Vector3(altar.x, 0.08, altar.z))
	await _ticks(10)
	_check(_game.hud.is_menu_open(), "The altar opens the Depth %d selection" % depth)
	_game._rng.seed = EXPEDITION_SEED
	_game.hud.level_selected.emit(depth)
	await _wait_for_navigation()


func _check_native_scene(depth: int) -> void:
	var runner_count := 0
	var encounter_count := 0
	var seen_runners: Dictionary = {}
	var seen_trees: Dictionary = {}
	var packs: Dictionary = {}
	var distinct_encounters: Dictionary = {}
	for id: String in _game._enemies:
		var enemy: Node3D = _game._enemies[id]
		var runner := enemy.get_node_or_null("Brain") as AIBehaviorRunner
		if runner != null and not seen_runners.has(runner.get_instance_id()):
			seen_runners[runner.get_instance_id()] = true
			var tree: AIBehaviorTree = runner.tree
			if tree != null and tree.resource_path.begins_with("res://"):
				if not seen_trees.has(tree):
					seen_trees[tree] = tree.validate().is_empty()
				if seen_trees[tree]:
					runner_count += 1
		var pack := int(_game.dungeon.encounters[int(id)].get("pack", -1))
		var encounter := enemy._encounter as AIEncounter3D
		if encounter != null and encounter.get_parent() == _game._actors and encounter.use_navigation_mesh:
			distinct_encounters[encounter.get_instance_id()] = true
			if not packs.has(pack):
				packs[pack] = encounter
			if packs[pack] == encounter and encounter.is_target_valid(_game.player):
				encounter_count += 1
	var roster: int = _game._enemies.size()
	_check(roster > 0 and runner_count == roster,
		"Depth %d has %d/%d distinct native runners with validated on-disk trees" % [depth, runner_count, roster])
	_check(roster > 0 and packs.size() > 1 and distinct_encounters.size() == packs.size() and encounter_count == roster,
		"Depth %d has %d/%d actors assigned to native, navigation-backed pack encounters" % [depth, encounter_count, roster])
	var director := _director()
	_check(director != null and director.is_inside_tree(), "Depth %d has a live native horde director" % depth)
	var region := _game.dungeon.get_node_or_null("DungeonNavigation") as NavigationRegion3D
	var nav: RID = _game.dungeon.navigation_map()
	_check(region != null and nav.is_valid() and NavigationServer3D.map_get_regions(nav).has(region.get_rid()),
		"Depth %d publishes its NavigationServer3D region to the world map" % depth)
	if roster > 0 and nav.is_valid():
		var actor: Node3D = _game._enemies.values()[0]
		var path: PackedVector3Array = _game.dungeon.navigation_route(_game.dungeon.spawn_position, actor.global_position)
		_check(path.size() >= 2 and path[-1].distance_to(actor.global_position) < 1.4,
			"Depth %d native navigation reaches an enemy chamber from arrival" % depth)


func _check_patrol_and_portal() -> void:
	var patrol: Node3D
	for id: String in _game._enemies:
		var points: PackedVector3Array = _game.dungeon.encounters[int(id)].get("patrol_points", PackedVector3Array())
		if points.size() >= 2:
			patrol = _game._enemies[id]
			break
	if not _check(is_instance_valid(patrol), "The seeded expedition contains a corridor patrol"):
		return
	_enable_only(patrol)
	var watch := _stand(patrol, patrol._sight_radius + 1.2, false)
	if not _check(watch.is_finite(), "A walkable observation point lies outside the patrol's sight range"):
		return
	_aim(watch, patrol.aim_point())
	_check(await _watch_patrol(patrol), "The saved patrol block moves its actor without player contact")

	var dungeon: Node3D = _game.dungeon
	var arrival: Vector3 = dungeon.spawn_position
	_game.player.place_at(arrival, dungeon.spawn_yaw)
	await _ticks(6)
	await _tap(KEY_T)
	if not _check(is_instance_valid(_game._portal_prop), "T creates the expedition portal"):
		return
	var gate: Node3D = _game._portal_prop
	_aim(arrival, gate.global_position + gate.interaction_point)
	await _ticks(6)
	await _tap(KEY_E)
	if not _check(not _game.in_dungeon and not dungeon.is_inside_tree() and not dungeon.navigation_map().is_valid(),
			"Using the portal detaches the dungeon navigation and actors"):
		return
	var parked := patrol.position
	await _ticks(32)
	_check(patrol.position.is_equal_approx(parked), "The parked native patrol stays idle while the hub is active")
	var return_gate: Vector3 = _game.hub.interaction_position("altar")
	_aim(Vector3(return_gate.x, 0.06, return_gate.z + 2.0), return_gate)
	await _ticks(6)
	await _tap(KEY_E)
	await _wait_for_navigation()
	if not _check(_game.in_dungeon and _game.dungeon == dungeon and dungeon.navigation_map().is_valid(),
			"Using the hub portal republishes the original dungeon and navigation map"):
		return
	_aim(watch, patrol.aim_point())
	_check(await _watch_patrol(patrol), "The same actor's native patrol moves again after portal re-entry")


func _watch_patrol(enemy: Node3D) -> bool:
	var runner := enemy.get_node_or_null("Brain") as AIBehaviorRunner
	if runner == null:
		return false
	runner.debug_enabled = false
	runner.debug_enabled = true
	var before := enemy.position
	var saw_patrol := false
	for frame in range(138):
		await _ticks(1)
		saw_patrol = saw_patrol or _entered(runner, NATIVE_PATROL) or runner.get_active_node_ids().has(30)
		if saw_patrol and _horizontal_distance(before, enemy.position) > 0.32:
			break
	runner.debug_enabled = false
	return saw_patrol and not enemy._engaged and _horizontal_distance(before, enemy.position) > 0.32


func _check_attack(ranged: bool) -> void:
	if not _game.in_dungeon:
		return
	var actor: Node3D
	var stand := Vector3.INF
	for candidate: Node3D in _game._enemies.values():
		if candidate._ranged != ranged or candidate.rarity != "normal":
			continue
		if Catalog.ARCHETYPES[candidate.archetype_id].get("cobweb", false):
			continue
		stand = _stand(candidate, 6.15 if ranged else 4.15, true)
		if stand.is_finite():
			actor = candidate
			break
	var label := "Ranged" if ranged else "Melee"
	if not _check(is_instance_valid(actor), "The seeded depth offers an unobstructed %s engagement" % label.to_lower()):
		return
	_enable_only(actor)
	var runner := actor.get_node_or_null("Brain") as AIBehaviorRunner
	var encounter := actor._encounter as AIEncounter3D
	if runner == null or encounter == null:
		_check(false, "%s probe has no native runner or encounter context" % label)
		return
	var director := _director()
	var category := Enemy.RANGED_ATTACK_CATEGORY if ranged else Enemy.MELEE_ATTACK_CATEGORY
	runner.debug_enabled = true
	_game.player.restore_full()
	_aim(stand, actor.aim_point())
	var before: float = _game.player.life
	var saw_attack := false
	var saw_move := false
	var saw_admission := false
	var saw_projectile := false
	for frame in range(360):
		await _ticks(1)
		saw_attack = saw_attack or _entered(runner, NATIVE_ATTACK)
		saw_move = saw_move or _entered(runner, NATIVE_MOVE)
		saw_admission = saw_admission or encounter.get_attack_pressure(_game.player, category) > 0.0
		saw_projectile = saw_projectile or (ranged and _has_projectile(actor))
		if saw_attack and saw_admission and (saw_projectile if ranged else saw_move and _game.player.life < before):
			break
	runner.debug_enabled = false
	_check(saw_attack and saw_admission, "%s commits a native attack task and updates native admission pressure" % label)
	if ranged:
		_check(saw_projectile, "The native ranged attack launches an in-world projectile")
	else:
		_check(saw_move, "The native tactical movement task closes melee distance")
		_check(_game.player.life < before, "The native melee attack damages the real player")
		_check(director != null and director.get_target_pressure(_game.player) > 0.0,
			"Actual combat feeds player pressure into the native horde director")


func _stand(enemy: Node3D, distance: float, needs_sight: bool) -> Vector3:
	var nav: RID = _game.dungeon.navigation_map()
	if not nav.is_valid():
		return Vector3.INF
	var space: PhysicsDirectSpaceState3D = enemy.get_world_3d().direct_space_state
	for index in range(24):
		var angle := TAU * float(index) / 24.0
		var point := enemy.global_position + Vector3(cos(angle), 0.0, sin(angle)) * distance
		point.y = 0.0
		if NavigationServer3D.map_get_closest_point(nav, point).distance_to(point) > 0.28:
			continue
		if needs_sight:
			var sight := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 1.05, enemy.aim_point(), 1)
			if not space.intersect_ray(sight).is_empty():
				continue
		return point + Vector3.UP * 0.05
	return Vector3.INF


func _enable_only(selected: Node3D) -> void:
	# Freeze the rest of the generated roster to attribute life loss and projectiles to this actor.
	for candidate: Node3D in _game._enemies.values():
		candidate.set_physics_process(candidate == selected)


func _director() -> AIHordeDirector:
	return _game._expedition_pressure.get_node_or_null("HordeDirector") as AIHordeDirector


func _has_projectile(actor: Node3D) -> bool:
	for child: Node in _game._actors.get_children():
		if child.get_script() == Projectile and child._source != null and child._source.get_ref() == actor:
			return true
	return false


func _entered(runner: AIBehaviorRunner, block: String) -> bool:
	for event: Dictionary in runner.get_debug_snapshot().get("events", []):
		if event.get("kind") == "action_enter" and event.get("block") == block:
			return true
	return false


static func _horizontal_distance(first: Vector3, second: Vector3) -> float:
	return Vector2(first.x - second.x, first.z - second.z).length()


func _aim(point: Vector3, target: Vector3) -> void:
	var direction := (target - point - Vector3.UP * 1.56).normalized()
	_game.player.place_at(point, atan2(-direction.x, -direction.z), asin(direction.y))


func _tap(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await _ticks(3)
	event = InputEventKey.new()
	event.physical_keycode = key
	Input.parse_input_event(event)
	await _ticks(3)


func _wait_for_navigation() -> void:
	# Godot publishes its region asynchronously. Wait for the same readiness check the game uses.
	if not _game.in_dungeon:
		return
	for frame in range(180):
		if _game.dungeon.navigation_map().is_valid():
			return
		await _ticks(1)


func _ticks(count: int) -> void:
	for frame in range(count):
		await physics_frame
		await process_frame


func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if condition:
		print("PASS  " + description)
	else:
		_failures += 1
		push_error("FAIL  " + description)
	return condition
