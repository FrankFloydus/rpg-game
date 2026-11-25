extends SceneTree

const Dungeon := preload("res://world/dungeon.gd")
const DungeonScene := preload("res://world/dungeon.tscn")
const Routes := preload("res://world/dungeon_route_gates.gd")
const Slab := preload("res://world/props/secret_passage.tscn")

var _checks := 0
var _errors := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var available := 0
	var example: Dictionary = {}
	for index in 96:
		var seed_value := 7395045 + index * 1760273
		var floor_index := index % 3
		var rise := 1 if index % 2 == 0 else -1
		var depth := 10 + index % 6
		var dungeon := _layout(depth, seed_value, floor_index, rise, Dungeon.FEATURE_SECRET_MERCHANT)
		if dungeon.secret_merchant_position.is_finite():
			available += 1
			_check_site(dungeon)
			if example.is_empty():
				example = {"depth": depth, "seed": seed_value, "floor": floor_index, "rise": rise}
		else:
			_check(dungeon.secret_merchant_passage.is_empty(), "Floors without a usable secret leave no merchant reference")
		var default := _layout(depth, seed_value, floor_index, rise, 0)
		_check(not default.secret_merchant_position.is_finite() and dungeon.map_cells == default.map_cells,
			"The merchant flag leaves the floor topology unchanged and old masks never get a merchant")
		dungeon.free()
		default.free()
	for depth in range(1, 10):
		var early := _layout(depth, 7395045, 0, 1, Dungeon.FEATURE_SECRET_MERCHANT)
		_check(not early.secret_merchant_position.is_finite() and early.secret_merchant_passage.is_empty(),
			"Depth %d cannot spawn a trader even with its special mask explicitly reserved" % depth)
		early.free()
	_check(available >= 84, "A requested secret merchant fits the ordinary generator in %d of 96 deterministic floors" % available)
	if not example.is_empty():
		await _check_actual_slab(example)
	print("Secret merchant sites: %d checks, %d failures; %d/96 requested sites valid" % [_checks, _errors, available])
	quit(0 if _errors == 0 else 1)


func _layout(depth: int, seed_value: int, floor_index: int, rise: int, features: int) -> Dungeon:
	var dungeon := DungeonScene.instantiate() as Dungeon
	dungeon._generation_version = Dungeon.EXPANDED_ROSTER_VERSION
	dungeon._feature_mask = features
	dungeon._room_limit = 7
	dungeon._population_scale = 0.70
	dungeon._rng.seed = seed_value
	dungeon._layout_expedition(depth, seed_value, floor_index, 3, rise)
	return dungeon


func _check_site(dungeon: Dungeon) -> void:
	var tile := dungeon.tile_at(dungeon.secret_merchant_position)
	var opening: Dictionary = dungeon.secret_passages.filter(func(candidate: Dictionary) -> bool:
		return candidate.id == dungeon.secret_merchant_passage)[0]
	var branch := dungeon.side_passages[opening.branch]
	var entry: Vector2i = opening.hidden_tiles[0]
	var arrival := dungeon.tile_at(dungeon.spawn_position)
	var open := Routes.reachable(dungeon.map_cells, arrival)
	var closed := Routes.reachable(dungeon.map_cells, arrival, entry)
	_check(tile == branch.tip and tile in opening.hidden_tiles and open.has(tile) and not closed.has(tile),
		"One live path reaches the trader and sealing the concealed entry cuts it off")
	var clear := not dungeon.stair_approach_tiles.has(tile)
	for chest: Dictionary in dungeon.chests:
		clear = clear and chest.position.distance_to(dungeon.secret_merchant_position) > 2.4
	for hazard: Dictionary in dungeon.hazard_points:
		clear = clear and dungeon.tile_at(hazard.position) not in opening.hidden_tiles
	for enemy: Dictionary in dungeon.encounters:
		clear = clear and dungeon.tile_at(enemy.position) not in opening.hidden_tiles
	var previous: Vector2i = branch.cells[-2]
	var approach := Vector3(previous.x - tile.x, 0.0, previous.y - tile.y)
	var forward := Basis(Vector3.UP, dungeon.secret_merchant_yaw).z
	_check(clear and forward.is_equal_approx(approach), "Trader faces the unoccupied passage and leaves clearance for other content")


func _check_actual_slab(example: Dictionary) -> void:
	var dungeon := DungeonScene.instantiate() as Dungeon
	dungeon.build(int(example.depth), int(example.seed), Dungeon.EXPANDED_ROSTER_VERSION, int(example.floor), 3, 7,
		int(example.rise), Dungeon.FEATURE_SECRET_MERCHANT)
	var opening: Dictionary = dungeon.secret_passages.filter(func(candidate: Dictionary) -> bool:
		return candidate.id == dungeon.secret_merchant_passage)[0]
	var slab := Slab.instantiate() as Node3D
	slab.position = opening.position
	slab.rotation.y = opening.yaw
	slab.configure(opening.id, false, opening.wall_tint)
	dungeon.add_child(slab)
	root.add_child(dungeon)
	await physics_frame
	await physics_frame
	var front := slab.global_basis.z
	var eye := slab.global_position + Vector3.UP * 1.25
	var line := PhysicsRayQueryParameters3D.create(eye + front, eye - front, 1)
	var space := dungeon.get_world_3d().direct_space_state
	var closed := space.intersect_ray(line)
	_check(closed.get("collider") == slab.get_node("Slab/WallBody"), "The actual closed secret slab blocks the physical passage")
	slab.open()
	for tick in 75:
		await physics_frame
	_check(space.intersect_ray(line).is_empty(), "Opening the slab removes the actual collision along the approach")
	dungeon.free()


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_errors += 1
		printerr("FAIL  ", description)
