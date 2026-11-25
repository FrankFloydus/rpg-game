extends SceneTree
## Reproduces a player keeping pace with an Archer across an open navigation region.

const Catalog = preload("res://combat/enemies/enemy_catalog.gd")
const Enemy = preload("res://combat/enemies/enemy.gd")
const Projectile = preload("res://combat/effects/enemy_projectile.gd")
const OSSUARY_ARCHER := 1
const PURSUIT_GAP := 2.5

var _checks := 0
var _failures := 0
var _cast_starts := 0
var _projectiles := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var arena := Node3D.new()
	root.add_child(arena)
	var navigation := _build_arena(arena)
	var map := navigation.get_navigation_map()
	for frame in range(120):
		if NavigationServer3D.map_get_iteration_id(map) > 0:
			break
		await _tick()
	if _check(NavigationServer3D.map_get_iteration_id(map) > 0, "The open arena has a working navigation mesh"):
		await _check_pursuit(arena, map)
	arena.free()
	print("Hearth Below ranged retreat: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _build_arena(arena: Node3D) -> NavigationRegion3D:
	_add_obstacle(arena, Vector3(0.0, -0.5, 0.0), Vector3(80.0, 1.0, 80.0))
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([
		Vector3(-39.0, 0.0, -39.0), Vector3(-39.0, 0.0, 39.0),
		Vector3(39.0, 0.0, 39.0), Vector3(39.0, 0.0, -39.0),
	])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	var navigation := NavigationRegion3D.new()
	navigation.navigation_mesh = mesh
	arena.add_child(navigation)
	return navigation


func _check_pursuit(arena: Node3D, map: RID) -> void:
	var pursuer := Node3D.new()
	pursuer.position = Vector3(0.0, 0.05, PURSUIT_GAP)
	arena.add_child(pursuer)
	var encounter := Enemy.create_ai_encounter(1, pursuer)
	arena.add_child(encounter)
	arena.child_entered_tree.connect(_on_arena_child_added)
	var archer := Catalog.instantiate(OSSUARY_ARCHER)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3801
	var route := func(start: Vector3, end: Vector3) -> PackedVector3Array:
		return NavigationServer3D.map_get_path(map, start, end, true)
	archer.setup(pursuer, 1, "normal", rng, route)
	archer.configure_ai(encounter)
	archer.position.y = 0.05
	archer.combat_event.connect(_on_combat_event)
	arena.add_child(archer)

	var tick_rate := float(Engine.physics_ticks_per_second)
	var away := Vector3.FORWARD
	var first_cast_tick := -1
	var first_cast_range := INF
	var saw_admission := false
	var saw_move_task := false
	var distance_traveled := 0.0
	var first_cast_visible := false
	for frame in range(ceili(5.0 * tick_rate)):
		var before := archer.global_position
		_place_pursuer(pursuer, archer, away, PURSUIT_GAP)
		await _tick()
		var step := archer.global_position - before
		step.y = 0.0
		if step.length_squared() > 0.000004:
			away = step.normalized()
		distance_traveled += step.length()
		saw_admission = saw_admission or encounter.get_attack_pressure(pursuer, Enemy.RANGED_ATTACK_CATEGORY) > 0.0
		saw_move_task = saw_move_task or archer._brain.get_active_node_ids().has(20)
		if first_cast_tick == -1 and _cast_starts > 0:
			first_cast_tick = frame + 1
			first_cast_range = archer.global_position.distance_to(pursuer.global_position)
			first_cast_visible = archer._sight

	_check(saw_move_task and distance_traveled > 0.2, "The Archer first repositions through the native movement task")
	_check(first_cast_tick >= 0 and float(first_cast_tick) / tick_rate < 2.0 and first_cast_range < 3.0,
		"The Archer commits a close-range shot during continuous pursuit (first cast %.2f s at %.2f m)"
		% [float(first_cast_tick) / tick_rate if first_cast_tick >= 0 else INF, first_cast_range])
	_check(first_cast_visible and saw_admission and _projectiles >= 2,
		"The Archer sees the target and uses admitted attacks to launch repeated projectiles")
	_check(distance_traveled < 4.0, "Continuous pursuit cannot keep the Archer retreating (%.2f m traveled)" % distance_traveled)

	await _check_cover(arena, archer, pursuer, away)
	await _check_rearm(archer, pursuer, away)


func _check_cover(arena: Node3D, archer: CharacterBody3D, pursuer: Node3D, away: Vector3) -> void:
	_place_pursuer(pursuer, archer, away, PURSUIT_GAP)
	var midpoint := archer.global_position.lerp(pursuer.global_position, 0.5)
	var wall := _add_obstacle(arena, midpoint + Vector3.UP * 1.5, Vector3(60.0, 3.0, 0.15))
	wall.rotation.y = atan2(away.x, away.z)
	var before := _projectiles
	for frame in range(ceili(1.2 * Engine.physics_ticks_per_second)):
		await _tick()
	_check(not archer._sight and _projectiles == before, "An expired retreat allows no shot through cover")
	wall.free()


func _check_rearm(archer: CharacterBody3D, pursuer: Node3D, away: Vector3) -> void:
	for frame in range(ceili(2.0 * Engine.physics_ticks_per_second)):
		_place_pursuer(pursuer, archer, away, 7.0)
		await _tick()
	var origin := archer.global_position
	var repositioned := false
	for frame in range(ceili(2.5 * Engine.physics_ticks_per_second)):
		_place_pursuer(pursuer, archer, away, PURSUIT_GAP)
		await _tick()
		var offset := archer.global_position - origin
		offset.y = 0.0
		if archer._brain.get_active_node_ids().has(20) and offset.length() > 0.25:
			repositioned = true
			break
	_check(repositioned, "Opening a gap before pressing close gives the Archer another short reposition")


func _place_pursuer(pursuer: Node3D, archer: CharacterBody3D, away: Vector3, distance: float) -> void:
	var from := archer.global_position
	pursuer.global_position = Vector3(from.x, 0.05, from.z) - away * distance


func _add_obstacle(arena: Node3D, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	arena.add_child(body)
	return body


func _on_combat_event(event: Dictionary) -> void:
	if event.get("kind") == &"cast_start":
		_cast_starts += 1


func _on_arena_child_added(child: Node) -> void:
	if child.get_script() == Projectile:
		_projectiles += 1


func _tick() -> void:
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
