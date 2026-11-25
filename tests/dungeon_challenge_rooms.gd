extends SceneTree
## Checks the special rooms against real collision and starter movement.

const Dungeon := preload("res://world/dungeon.gd")
const DungeonScene := preload("res://world/dungeon.tscn")
const PlayerScene := preload("res://player/player.tscn")
const Rooms := preload("res://world/dungeon_challenge_chambers.gd")
const Catalog := preload("res://combat/enemies/enemy_catalog.gd")
const Water := preload("res://world/modules/basin_water.tscn")

var _checks := 0
var _errors := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for action in [&"left", &"right", &"forward", &"back", &"jump", &"sprint"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	for feature in [Dungeon.FEATURE_PLATFORM_CHAMBER, Dungeon.FEATURE_LAVA_CHAMBER, Dungeon.FEATURE_SUBMERGED_CHAMBER]:
		var floor := _build_floor(feature)
		if not _check(is_instance_valid(floor), "Seeded floors offer a compatible reserved room for flag %d" % feature):
			continue
		root.add_child(floor)
		await _ticks(3)
		var chamber := floor.challenge_chamber
		var rewards := floor.chests.filter(func(chest: Dictionary) -> bool: return chest.get("challenge_type") == chamber.kind)
		_check(rewards.size() == 1 and not floor.encounters.any(func(entry: Dictionary) -> bool: return entry.room == chamber.room),
			"The optional chamber has one reward and contributes no required fights")
		if rewards.is_empty():
			floor.free()
			continue
		var coffer := floor.coffer_pose(int(rewards[0].id)).origin
		_check(coffer.is_equal_approx(chamber.reward), "The actual coffer uses the authored terrain height")
		match chamber.kind:
			Rooms.PLATFORM: await _check_raised_room(floor, chamber, coffer)
			Rooms.LAVA: _check_lava_room(floor, chamber, coffer)
			Rooms.SUBMERGED: await _check_basin(floor, chamber, coffer)
		floor.free()
		await _ticks(1)
	_check_swarm_roster()
	print("Dungeon challenge rooms: %d checks, %d failures" % [_checks, _errors])
	quit(0 if _errors == 0 else 1)


func _build_floor(feature: int) -> Dungeon:
	for seed_value in [95545, 31911, 63728, 94]:
		var floor := DungeonScene.instantiate() as Dungeon
		floor.build(8, seed_value, Dungeon.GENERATION_VERSION, 0, 3, 7, 1, feature)
		if not floor.challenge_chamber.is_empty():
			return floor
		floor.free()
	return null


func _check_raised_room(floor: Dungeon, chamber: Dictionary, coffer: Vector3) -> void:
	var forward: Vector3 = chamber.direction
	var platforms: Array = chamber.platforms
	var first: Vector3 = platforms[0].top
	var player := PlayerScene.instantiate() as CharacterBody3D
	root.add_child(player)
	player.gameplay_enabled = true
	var previous := first - forward * 1.28
	previous.y = 0.0
	for tread: Dictionary in platforms:
		var destination: Vector3 = tread.top
		var direction := destination - previous
		direction.y = 0.0
		direction = direction.normalized()
		var heading := atan2(-direction.x, -direction.z)
		player.place_at(previous + Vector3.UP * 0.10, heading)
		await _ticks(12)
		Input.action_press("forward")
		await _ticks(3)
		Input.action_press("jump")
		await _ticks(1)
		Input.action_release("jump")
		var reached := false
		for frame in 66:
			await _ticks(1)
			var travel := player.position - previous
			if travel.dot(direction) >= (destination - previous).dot(direction) - 0.27:
				Input.action_release("forward")
			if player.is_on_floor() and absf(player.position.y - destination.y) < 0.08:
				reached = true
				break
		Input.action_release("forward")
		_check(reached, "The starter character jumps onto the %.2fm tread" % destination.y)
		previous = destination
	_check(coffer.y > 1.8 and floor.floor_contains(coffer + Vector3.UP * 1.65),
		"Reward shelf gives the player enough headroom to interact")
	var across := Vector3(forward.z, 0.0, -forward.x)
	player.place_at(coffer + Vector3.UP * 0.08, atan2(-across.x, -across.z))
	await _ticks(8)
	Input.action_press("forward")
	await _ticks(65)
	Input.action_release("forward")
	_check(player.is_on_floor() and absf(player.position.y) < 0.05,
		"The player can return to the dry room floor from the reward shelf (reached %s from %s)" % [player.position, coffer])
	player.free()


func _check_lava_room(floor: Dungeon, chamber: Dictionary, coffer: Vector3) -> void:
	var lava := floor.lava_floor
	var center: Vector3 = lava.position
	var extent: Vector2 = lava.extent
	var bounds := Rect2(Vector2(center.x, center.z) - extent * 0.5, extent)
	var forward: Vector3 = chamber.direction
	var side := Vector3(forward.z, 0.0, -forward.x)
	var rim := center + side * (extent.x * 0.5 + 0.82)
	_check(not bounds.has_point(Vector2(coffer.x, coffer.z)) and floor.ground_is_open(rim),
		"The lava footprint leaves both the coffer and a connected dry perimeter clear")
	_check(absf(_floor_height(floor, center)) < 0.04 and absf(_floor_height(floor, rim)) < 0.04,
		"Lava state controls the hazard over actual collision flooring")


func _check_basin(floor: Dungeon, chamber: Dictionary, coffer: Vector3) -> void:
	var basin := floor.submerged_basin
	var surface: Vector3 = basin.position
	var forward: Vector3 = chamber.direction
	var side := Vector3(forward.z, 0.0, -forward.x)
	var dry := surface + side * 2.55
	_check(surface.y > coffer.y + 1.7 and absf(_floor_height(floor, coffer) - coffer.y) < 0.04,
		"The reward is on a real floor below the water surface and former ground plane")
	_check(absf(_floor_height(floor, dry)) < 0.04 and floor.floor_contains(coffer),
		"A dry perimeter remains and the submerged shelf belongs to the active floor")
	var ramp := center_xz(surface) - side * 1.06
	var start := _floor_height(floor, ramp - forward * 1.11)
	var end := _floor_height(floor, ramp + forward * 1.28)
	_check(start > end + 1.25 and start < 0.0 and end > coffer.y,
		"A solid shallow-ended ramp joins the ledge to the basin bottom")
	var player := PlayerScene.instantiate() as CharacterBody3D
	root.add_child(player)
	player.gameplay_enabled = true
	var water := Water.instantiate()
	water.position = surface
	water.configure(basin.extent)
	floor.add_child(water)
	player.set_water_volume(water)
	var climb := -forward
	var start_point := ramp + forward * 1.33
	start_point.y = _floor_height(floor, start_point) + 0.10
	player.place_at(start_point, atan2(-climb.x, -climb.z))
	await _ticks(10)
	_check(water.contains(player.global_position + Vector3.UP * 0.76) and player._water_tint.visible,
		"The deep basin activates swim movement and an underwater-only camera pass")
	var depth: float = player.position.y
	Input.action_press("jump")
	await _ticks(10)
	Input.action_release("jump")
	_check(player.position.y > depth + 0.12, "Space swims upward in the actual volume")
	Input.action_press("forward")
	await _ticks(120)
	Input.action_release("forward")
	_check(player.is_on_floor() and absf(player.position.y) < 0.05,
		"A starter player can walk from the bottom to dry ground through the ramp's open lip (reached %s from %s)" % [
			player.position, start_point])
	_check(not player._water_tint.visible, "The underwater pass fades out after leaving the water")
	var movement_events: Array[String] = []
	player.feedback.connect(func(_message: String, id: String) -> void: movement_events.append(id))
	Input.action_press("jump")
	await _ticks(3)
	Input.action_release("jump")
	await _ticks(62)
	_check(movement_events.count("jump") == 1 and movement_events.count("land") == 1,
		"A dry-ground jump emits one launch and one real contact sound")
	player.free()


func _floor_height(floor: Dungeon, point: Vector3) -> float:
	var hit := floor.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(
		floor.to_global(center_xz(point) + Vector3.UP * 3.0), floor.to_global(center_xz(point) - Vector3.UP * 3.0), 1))
	return floor.to_local(hit.position).y if not hit.is_empty() else INF


func _check_swarm_roster() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var only_ordinary := true
	var capped := true
	for sample in 250:
		only_ordinary = only_ordinary and Catalog.pick_archetype(25, rng) != Dungeon.CRYPT_SCURRER_ARCHETYPE
		capped = capped and Catalog.pick_archetype(25, rng, 20) < 20
	_check(only_ordinary and capped, "Ordinary picks skip Crypt Scurrers and old runs keep their original species cap")
	var swarm_found := false
	for seed_value in [95545, 31911, 63728, 94, 19467, 10677]:
		var floor := Dungeon.new()
		floor.build(3, seed_value, Dungeon.GENERATION_VERSION, 0, 2, 8)
		var swarm := floor.encounters.filter(func(entry: Dictionary) -> bool: return entry.get("swarm", false))
		if swarm.is_empty():
			floor.free()
			continue
		swarm_found = true
		var room: int = swarm[0].room
		var pack := floor.encounters.filter(func(entry: Dictionary) -> bool: return entry.room == room)
		_check(pack == swarm and pack.size() in [4, 5, 6] and room >= 2,
			"A Depth III swarm replaces one entire ordinary pack in a later room")
		_check(swarm.all(func(entry: Dictionary) -> bool:
			return (entry.archetype == Dungeon.CRYPT_SCURRER_ARCHETYPE and not entry.has("spawn_trigger")
				and not floor.stair_approach_tiles.has(floor.tile_at(entry.position)))),
			"Swarm members avoid gate transitions, awake triggers, and mixed archetypes")
		floor.free()
		break
	_check(swarm_found, "The v9 room sample includes a dedicated spawn selection for Crypt Scurrers")


func center_xz(point: Vector3) -> Vector3:
	return Vector3(point.x, 0.0, point.z)


func _ticks(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if not condition:
		_errors += 1
		push_error(description)
	return condition
