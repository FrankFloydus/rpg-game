extends SceneTree
## Exercises the native AI through live Training Ground combat.

const Game = preload("res://main.tscn")
const Enemy = preload("res://combat/enemies/enemy.gd")
const Catalog = preload("res://combat/enemies/enemy_catalog.gd")
const Projectile = preload("res://combat/effects/enemy_projectile.gd")
const NATIVE_ATTACK := "telegraph_commit_recover"

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
	_game._enter_training_ground()
	if _check(is_instance_valid(_game.training_ground), "The campaign enters the live Training Ground"):
		await _wait_for_navigation()
		var arena: Node3D = _game.training_ground
		var map: RID = arena.navigation_map()
		var region := arena.get_node_or_null("TrainingNavigation") as NavigationRegion3D
		_check(region != null and map.is_valid() and NavigationServer3D.map_get_regions(map).has(region.get_rid()),
			"The Training Ground publishes its exposed NavigationServer3D region")
		await _check_attack(false)
		await _check_attack(true)
	_game.free()
	await _ticks(2)
	print("Hearth Below native AI integration: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_attack(ranged: bool) -> void:
	_game._reset_training_combat()
	var actor: Node3D = Catalog.instantiate(1 if ranged else 0)
	_game._prepare_training_enemy(actor, 1, "normal", [] as Array[String], Vector3(0.0, 0.08, 0.0))
	var label := "Ranged" if ranged else "Melee"
	await _ticks(3)
	var stand := _stand(actor, 6.15 if ranged else 5.75)
	if not _check(stand.is_finite(), "The arena offers an unobstructed %s engagement" % label.to_lower()):
		return
	var arena: Node3D = _game.training_ground
	var path: PackedVector3Array = arena.navigation_route(stand, actor.global_position)
	_check(path.size() >= 2 and path[-1].distance_to(actor.global_position) < 1.4,
		"%s native navigation can reach the engagement from the test point" % label)
	var runner := actor.get_node_or_null("Brain") as AIBehaviorRunner
	var encounter := actor._encounter as AIEncounter3D
	var director := _game._training_pressure.get_node_or_null("HordeDirector") as AIHordeDirector
	if not _check(runner != null and runner.tree != null and runner.tree.resource_path.begins_with("res://")
		and runner.tree.validate().is_empty() and encounter != null
		and encounter.is_target_valid(_game.player) and director != null,
		"%s actor uses a validated on-disk behavior tree, native encounter and horde director" % label):
		return
	var category := Enemy.RANGED_ATTACK_CATEGORY if ranged else Enemy.MELEE_ATTACK_CATEGORY
	runner.debug_enabled = true
	_game.player.restore_full()
	_aim(stand, actor.aim_point())
	var before: float = _game.player.life
	var saw_attack := false
	var start := Vector2(actor.global_position.x, actor.global_position.z)
	var saw_admission := false
	var saw_projectile := false
	var saw_pressure := false
	for frame in range(360):
		await _ticks(1)
		saw_attack = saw_attack or _entered(runner, NATIVE_ATTACK)
		saw_admission = saw_admission or encounter.get_attack_pressure(_game.player, category) > 0.0
		saw_projectile = saw_projectile or (ranged and _has_projectile(actor))
		saw_pressure = saw_pressure or director.get_target_pressure(_game.player) > 0.0
		if saw_attack and saw_admission and (saw_projectile if ranged else _game.player.life < before and saw_pressure):
			break
	runner.debug_enabled = false
	_check(saw_attack and saw_admission, "%s commits a native attack task and updates native admission pressure" % label)
	if ranged:
		_check(saw_projectile, "The native ranged attack launches an in-world projectile")
	else:
		var finish := Vector2(actor.global_position.x, actor.global_position.z)
		_check(start.distance_to(finish) > 0.5, "The native melee actor closes distance to the player")
		_check(_game.player.life < before, "The native melee attack damages the real player")
		_check(saw_pressure, "Actual combat records pressure in the native horde director")


func _stand(enemy: Node3D, distance: float) -> Vector3:
	var nav: RID = _game.training_ground.navigation_map()
	if not nav.is_valid():
		return Vector3.INF
	var space: PhysicsDirectSpaceState3D = enemy.get_world_3d().direct_space_state
	for index in range(24):
		var angle := TAU * float(index) / 24.0
		var point := enemy.global_position + Vector3(cos(angle), 0.0, sin(angle)) * distance
		point.y = 0.0
		if NavigationServer3D.map_get_closest_point(nav, point).distance_to(point) > 0.28:
			continue
		var sight := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 1.05, enemy.aim_point(), 1)
		if not space.intersect_ray(sight).is_empty():
			continue
		return point + Vector3.UP * 0.05
	return Vector3.INF


func _has_projectile(actor: Node3D) -> bool:
	for child: Node in _game._training_actors.get_children():
		if child.get_script() == Projectile and child._source != null and child._source.get_ref() == actor:
			return true
	return false


func _entered(runner: AIBehaviorRunner, block: String) -> bool:
	for event: Dictionary in runner.get_debug_snapshot().get("events", []):
		if event.get("kind") == "action_enter" and event.get("block") == block:
			return true
	return false


func _aim(point: Vector3, target: Vector3) -> void:
	var direction := (target - point - Vector3.UP * 1.56).normalized()
	_game.player.place_at(point, atan2(-direction.x, -direction.z), asin(direction.y))


func _wait_for_navigation() -> void:
	# Godot publishes its region asynchronously. Wait for the same readiness check the game uses.
	for frame in range(180):
		if _game.training_ground.navigation_map().is_valid():
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
