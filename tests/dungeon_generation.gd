extends SceneTree
## Run with Godot 4.7: --headless --path <project> --script res://tests/dungeon_generation.gd

const Dungeon = preload("res://world/dungeon.gd")
const DungeonScene = preload("res://world/dungeon.tscn")
const RouteGates = preload("res://world/dungeon_route_gates.gd")

const DEPTHS := [1, 2, 4, 8, 12]
const SEEDS := [94, 31911, 63728, 95545]
# Version, depth, seed and fingerprint captured before changing each generator.
const SAVED_RUN_FIXTURES := [
	[1, 1, 0, "a36469c37ce65cb2202c3c7de2fc2dc52057f81d9a878fee65f0fa16b8423b1d"],
	[1, 5, 4294967295, "f9686e367269b8f0a36e5d05b917fa2541facc2eda3b5ab52c062a0c037d8a26"],
	[2, 1, 94, "5f44a02bb3df4826cbeebd212e21e453e40f063cfecbd3ea7c71c731b249b2cb"],
	[2, 1, 95545, "0a156d684a194793a7e4b6e3c2ec313852a7f6d6b05e04d8b651a97dc5851f06"],
	[3, 1, 0, "0be411642c0a90f236e41a51287fe1867a8f994c6f2d0cefbf022c9f9f2717ff"],
	[3, 7, 95545, "1f749670ab5a25c04e68b0d66e34eae6272e5f43ea4f1159d19435a41b3ec190"],
]
const STEPS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var styles := {}
	var shapes := {}
	var chamber_sizes := {}
	var themes := {}
	var moving_patrols := 0
	var annex_count := 0
	var trap_section_count := 0
	var observed_triggers := {}
	var trial_coffers := 0
	for depth: int in DEPTHS:
		var population: Array[int] = []
		var guards: Array[int] = []
		for seed_value: int in SEEDS:
			var dungeon := Dungeon.new()
			dungeon.build(depth, seed_value)
			var context := "depth %d, seed %d" % [depth, seed_value]
			styles[dungeon.topology] = true
			themes[dungeon.depth_theme] = true
			for room: Dictionary in dungeon.rooms:
				shapes[room.shape] = true
				chamber_sizes[room.bounds.size] = true
			annex_count += dungeon.side_passages.filter(func(passage: Dictionary) -> bool: return passage.has("annex")).size()
			trap_section_count += int(dungeon.hazard_points.any(func(hazard: Dictionary) -> bool: return hazard.has("gallery")))
			_check(dungeon.rooms.size() == mini(19, 6 + 2 * (depth - 1)), "Depth growth and cap", context)
			_verify_passage_frames(dungeon, context)
			_verify_exploration(dungeon, context)
			_verify_connected(dungeon, context)
			_count_spawn_triggers(dungeon, observed_triggers, context)
			trial_coffers += _verify_trial_coffers(dungeon, depth, context)
			var distribution := _verify_content(dungeon, depth, context)
			if depth == 1:
				var first_room := dungeon.encounters.filter(func(entry: Dictionary) -> bool: return entry.room == 1)
				_check(first_room.size() in [1, 2] and not first_room[0].has("spawn_trigger") and distribution.x <= 1,
					"A Depth I approach has one or two live foes and at most one corridor scout", context)
			guards.append(distribution.x)
			moving_patrols += distribution.y
			population.append(dungeon.encounters.size())
			dungeon.free()
		print("Depth %d: %dâ€“%d foes, %dâ€“%d in corridors" % [
			depth, population.min(), population.max(), guards.min(), guards.max(),
		])
	_check(styles.size() == 3, "All topology families")
	_check(shapes.size() == 6, "All chamber shapes")
	_check(chamber_sizes.size() >= 6, "Natural variation in chamber width and length")
	_check(annex_count >= 6 and annex_count < 30, "Different concealed branches offer different numbers of caches")
	_check(trap_section_count >= 10, "Trapped gallery sections exist throughout the deeper seed sample")
	_check(themes.size() == 4, "All depth regions")
	_check(moving_patrols > 0, "Corridor patrol waypoints are generated")
	_check(observed_triggers.get("threshold", 0) > 0 and observed_triggers.get("coffer", 0) > 0,
		"Seed sample offers room-entry and coffer ambushes")
	_check(trial_coffers > 0, "Deeper floors can contain multi-wave reliquaries")
	_verify_determinism()
	_verify_saved_run_fixtures()
	_verify_previous_opening_pair()
	_verify_disabled_features()
	await _verify_collision()
	await _verify_continuous_stairs(-1)
	await _verify_continuous_stairs(1)
	print("Dungeon generation: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


func _count_spawn_triggers(dungeon: Dungeon, counts: Dictionary, context: String) -> void:
	var seen := {}
	for entry: Dictionary in dungeon.encounters:
		var trigger := String(entry.get("spawn_trigger", ""))
		if trigger.is_empty():
			continue
		var room_id: int = entry.room
		_check(room_id >= 2 and entry.ambush and trigger in ["threshold", "coffer"],
			"Dormant waves start in later accessible chambers", context)
		if seen.has(room_id):
			_check(seen[room_id] == trigger, "Every member of the wave has one shared trigger", context)
			continue
		seen[room_id] = trigger
		counts[trigger] = int(counts.get(trigger, 0)) + 1
		if trigger == "coffer":
			_check(dungeon.chests.any(func(chest: Dictionary) -> bool:
				return chest.room == room_id and chest.get("spawn_trigger") == "coffer" and not chest.locked),
				"Coffer waves have an accessible marked coffer", context)


func _verify_trial_coffers(dungeon: Dungeon, depth: int, context: String) -> int:
	var trial_count := 0
	for coffer: Dictionary in dungeon.chests:
		if not coffer.has("trial_waves"):
			continue
		trial_count += 1
		_check(depth >= 4 and coffer.guarded and not coffer.locked and coffer.spawn_trigger == "coffer",
			"Trial coffers are marked and ramp in after Depth III", context)
		var counts := {}
		for entry: Dictionary in dungeon.encounters:
			if entry.room == coffer.room and entry.has("wave"):
				var wave: int = entry.wave
				counts[wave] = int(counts.get(wave, 0)) + 1
		_check(counts.size() == int(coffer.trial_waves) and counts.size() in [2, 3], "Coffer waves match their declared count", context)
		for index in counts.size():
			_check(int(counts.get(index, 0)) in [3, 4, 5], "Trial waves start at zero with three to five foes each", context)
	_check(trial_count <= 1, "At most one coffer per floor is a multi-wave trial", context)
	return trial_count


func _verify_connected(dungeon: Node3D, context: String) -> void:
	# A partial cover collider reserves a whole cell for enemy routing. Verify that
	# every other cell stays connected, including small recesses in the shaped rooms.
	var start: Vector2i = dungeon.tile_at(dungeon.spawn_position)
	var reached := {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var tile: Vector2i = frontier.pop_back()
		for step in STEPS:
			var neighbor := tile + step
			if not reached.has(neighbor) and dungeon.ground_is_open(dungeon.tile_position(neighbor)):
				reached[neighbor] = true
				frontier.append(neighbor)
	var reservable := 0
	for room: Dictionary in dungeon.rooms:
		reservable += room.cover.size()
		_check(not room.doors.is_empty(), "Chamber has an entrance", context)
	_check(reached.size() == dungeon.map_cells.size() - reservable, "Every open cell is reachable around cover", context)


func _verify_passage_frames(dungeon: Node3D, context: String) -> void:
	var occupied: Array[Rect2] = []
	var bodies := 0
	for center: Vector2i in dungeon._passage_frames:
		var footprint: Rect2 = dungeon._passage_frames[center]
		_check(not occupied.any(func(other: Rect2) -> bool: return other.intersects(footprint)),
			"Frames have separate footprints", context)
		occupied.append(footprint)
		for direction in STEPS:
			var delta := center - direction
			if delta.x % 2 != 0 or delta.y % 2 != 0:
				continue
			var tile := delta / 2
			var corridor := tile + direction
			if dungeon.map_cells.get(tile, -1) < 0 or dungeon.map_cells.get(corridor) != -1:
				continue
			var across := Vector2i(-direction.y, direction.x)
			_check(not dungeon.map_cells.has(corridor + across) and not dungeon.map_cells.has(corridor - across),
				"Each frame serves a single passage backed by masonry", context)
			if dungeon.map_cells[tile] == 0:
				bodies += 1
	_check(bodies == 1, "Arrival has a single stone portal and sentinel pair", context)


func _verify_exploration(dungeon: Node3D, context: String) -> void:
	var quiet_count := 0
	for room: Dictionary in dungeon.rooms:
		_check(room.bounds.size.x <= 7 and room.bounds.size.y <= 7 and room.tiles.size() <= 35,
			"Bigger chambers stay within the bounded room budget", context)
		if room.role == &"quiet":
			quiet_count += 1
			_check(not dungeon.encounters.any(func(foe: Dictionary) -> bool: return foe.room == room.id),
				"Quiet chambers do not have mandatory encounters", context)
	_check(quiet_count > 0, "The layout has breathing space between fights", context)
	var caches := 0
	for passage: Dictionary in dungeon.side_passages:
		var tip: Vector2i = passage.tip
		var neighbors := 0
		for direction in STEPS:
			if dungeon.map_cells.has(tip + direction):
				neighbors += 1
		_check(neighbors == 1, "Side passages end blindly", context)
		if passage.treasure:
			caches += 1
			_check(dungeon.chests.any(func(chest: Dictionary) -> bool:
				return bool(chest.get("side_cache", false)) and dungeon.tile_at(chest.position) == tip
			), "Exploration reward is at the blind end", context)
	_check(caches >= 2, "Several dead ends reward exploration", context)
	_check(not dungeon.secret_passages.is_empty(), "The floor has a concealed side passage", context)
	for secret: Dictionary in dungeon.secret_passages:
		_check(not dungeon.encounters.any(func(foe: Dictionary) -> bool:
			return dungeon.tile_at(foe.position) in secret.hidden_tiles
		), "Secrets contain no foe needed for the floor clear", context)
		_check(dungeon.chests.any(func(chest: Dictionary) -> bool:
			return bool(chest.get("side_cache", false)) and dungeon.tile_at(chest.position) in secret.hidden_tiles
		), "Concealed passage leads to a blind-end cache", context)
		if dungeon.side_passages[secret.branch].has("annex"):
			var rewards: Array = dungeon.chests.filter(func(chest: Dictionary) -> bool:
				return chest.get("secret_cache", false) and dungeon.tile_at(chest.position) in secret.hidden_tiles
			)
			_check(rewards.size() >= 2, "Concealed annex offers multiple accessible caches", context)
			if dungeon._generation_version < Dungeon.AUTHORED_SECRET_VERSION:
				_check(dungeon.hazard_points.any(func(hazard: Dictionary) -> bool:
					return hazard.get("secret", false) and dungeon.tile_at(hazard.position) in secret.hidden_tiles
				), "The legacy annex has its saved trap arrangement", context)

	var dressing := dungeon.get_node("ChamberSetpieces/EdgeDressing")
	for prop: Node3D in dressing.get_children():
		var tile: Vector2i = dungeon.tile_at(prop.position)
		var offset: Vector3 = prop.position - dungeon.tile_position(tile)
		var wall_distance := INF
		for edge: Vector2i in STEPS:
			if not dungeon.map_cells.has(tile + edge):
				wall_distance = minf(wall_distance, dungeon.CELL_SIZE * 0.5 - offset.dot(Vector3(edge.x, 0.0, edge.y)))
		_check(dungeon.map_cells.has(tile) and wall_distance > 0.15 and wall_distance <= 1.12,
			"Breakables and votives are tucked against solid walls", context)


func _verify_content(dungeon: Node3D, depth: int, context: String) -> Vector2i:
	var used := {}
	var rooms_with_guards := {}
	var corridor_count := 0
	var moving_patrols := 0
	for point: Dictionary in dungeon.chests + dungeon.hazard_points + dungeon.encounters:
		var tile: Vector2i = dungeon.tile_at(point.position)
		var pair_separated := false
		if used.has(tile) and point.get("paired_cache", false) and used[tile].get("secret_cache", false):
			var first: Transform3D = dungeon.coffer_pose(int(used[tile].id))
			var second: Transform3D = dungeon.coffer_pose(int(point.id))
			pair_separated = first.origin.distance_to(second.origin) >= 1.46
		_check(not used.has(tile) or pair_separated, "Encounters, coffers and hazards have distinct physical placements", context)
		_check(dungeon.ground_is_open(point.position), "Content placed on open floor", context)
		_check(not dungeon.route(dungeon.spawn_position, point.position).is_empty(), "Content has an actor navigation route", context)
		_check(int(dungeon.map_cells.get(tile, -2)) == point.room and point.room != 0, "Ownership and safe arrival", context)
		used[tile] = point

	for entry: Dictionary in dungeon.encounters:
		if entry.location == "room":
			rooms_with_guards[entry.room] = true
			continue
		corridor_count += 1
		_check(entry.room == -1, "Patrol starts in a corridor", context)
		if entry.has("patrol_points"):
			_verify_patrol(dungeon, entry, context)
			moving_patrols += 1
	_check(corridor_count > 0 and corridor_count * 4 <= dungeon.encounters.size(), "Corridor encounters are a minority", context)
	var locked := false
	var unlocked := false
	var warded := false
	for chest: Dictionary in dungeon.chests:
		var pose: Transform3D = dungeon.coffer_pose(int(chest.id))
		var tile: Vector2i = dungeon.tile_at(pose.origin)
		var outward := Vector2i(-roundi(pose.basis.z.x), -roundi(pose.basis.z.z))
		var approach := pose.origin + pose.basis.z * 1.1
		_check(outward.length_squared() == 1 and not dungeon.map_cells.has(tile + outward)
			and not dungeon._thresholds.has(tile) and not dungeon.stair_approach_tiles.has(tile)
			and not dungeon.route(dungeon.spawn_position, approach).is_empty(),
			"The actual coffer faces an accessible aisle from a solid wall clear of stairs and doorways", context)
		var expected_tile: Vector2i = dungeon.tile_at(chest.position) if chest.get("side_cache", false) else tile
		_check(tile == expected_tile and int(dungeon.map_cells[tile]) == int(chest.room),
			"Coffers keep their chamber identity or original terminal cache", context)
		if chest.guarded:
			warded = true
			_check(rooms_with_guards.has(chest.room), "Warded coffer has a room guard", context)
			_check(depth >= 9 or not chest.locked, "Early wards depend on guard clear only", context)
		else:
			locked = locked or chest.locked
			unlocked = unlocked or not chest.locked
	_check(locked and unlocked and warded, "Key, open and warded coffers are represented", context)
	var ordinary_hazards: Array = dungeon.hazard_points.filter(func(hazard: Dictionary) -> bool: return not hazard.has("secret"))
	_check((depth == 1) == ordinary_hazards.is_empty(), "Ordinary traps begin at depth 2", context)
	return Vector2i(corridor_count, moving_patrols)


func _verify_patrol(dungeon: Node3D, entry: Dictionary, context: String) -> void:
	var points: PackedVector3Array = entry.patrol_points
	_check(points.size() in [2, 3] and not entry.ambush, "Short mobile patrol rather than a stationary ambush", context)
	_check(dungeon.tile_at(points[0]) == dungeon.tile_at(entry.position), "Patrol begins at the spawn tile", context)
	for index in range(1, points.size()):
		var tile: Vector2i = dungeon.tile_at(points[index])
		var previous: Vector2i = dungeon.tile_at(points[index - 1])
		_check(tile.distance_squared_to(previous) == 1 and int(dungeon.map_cells.get(tile, -2)) == -1,
			"Patrol walks consecutive corridor tiles", context)


func _verify_opening_pack(dungeon: Node3D, context: String) -> void:
	var room: Dictionary = dungeon.rooms[1]
	var arrival: Vector2i = dungeon.rooms[0].center
	var doors: Array[Vector2i] = room.doors.duplicate()
	doors.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(arrival) < b.distance_squared_to(arrival)
	)
	var entrance: Vector3 = dungeon.tile_position(doors.front())
	var opening: Array[Dictionary] = []
	for entry: Dictionary in dungeon.encounters:
		if entry.room == 1:
			opening.append(entry)
	opening.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return entrance.distance_squared_to(a.position) < entrance.distance_squared_to(b.position)
	)
	if opening.size() < 2:
		_check(false, "An opening pack has at least two enemies", context)
		return
	var front: Dictionary = opening.front()
	var back: Dictionary = opening.back()
	_check(front.archetype == 0 and back.archetype == 1 and front.pack == back.pack
			and entrance.distance_squared_to(front.position) < entrance.distance_squared_to(back.position),
		"Grave Thrall screens an Ossuary Archer in the opening pack", context)


func _verify_previous_opening_pair() -> void:
	for seed_value: int in SEEDS:
		var older := Dungeon.new()
		var newer := Dungeon.new()
		older.build(1, seed_value, 2)
		newer.build(1, seed_value, 3)
		_verify_opening_pack(newer, str(seed_value))
		var changes := 0
		var expected: Array[Dictionary] = newer.encounters.duplicate(true)
		if expected.size() == older.encounters.size():
			for index in expected.size():
				var entry := expected[index]
				if entry.room == 1 and entry.archetype != older.encounters[index].archetype:
					changes += 1
					entry["archetype"] = older.encounters[index].archetype
		_check(older.map_cells == newer.map_cells and older.chests == newer.chests
				and older.encounters == expected and changes <= 2,
			"Only the opening pair changes between saved versions 2 and 3", str(seed_value))
		older.free()
		newer.free()


func _verify_determinism() -> void:
	for version in range(1, Dungeon.GENERATION_VERSION + 1):
		var first := Dungeon.new()
		var second := Dungeon.new()
		first.build(4, 94, version)
		second.build(4, 94, version)
		_check(first.map_cells.keys() == second.map_cells.keys() and first.map_cells == second.map_cells,
			"Saved seed reproduces both map contents and iteration order", "version %d" % version)
		_check(first.encounters == second.encounters and first.chests == second.chests,
			"Saved seed reproduces encounter and chest identities", "version %d" % version)
		_check(first.chests.all(func(entry: Dictionary) -> bool:
			return first.coffer_pose(int(entry.id)).is_equal_approx(second.coffer_pose(int(entry.id)))),
			"Saved seed reproduces actual coffer poses", "version %d" % version)
		first.free()
		second.free()


func _verify_saved_run_fixtures() -> void:
	for fixture: Array in SAVED_RUN_FIXTURES:
		var dungeon := Dungeon.new()
		dungeon.build(fixture[1], fixture[2], fixture[0])
		var tiles := []
		var keys: Array = dungeon.map_cells.keys()
		keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.x < b.x if a.x != b.x else a.y < b.y
		)
		for tile: Vector2i in keys:
			tiles.append([tile.x, tile.y, dungeon.map_cells[tile]])
		var bounds := []
		for room: Rect2i in dungeon.room_bounds:
			bounds.append([room.position.x, room.position.y, room.size.x, room.size.y])
		var enemies := []
		for entry: Dictionary in dungeon.encounters:
			enemies.append([_coordinates(entry.position), entry.archetype, entry.pack, entry.room, entry.ambush, entry.alert_radius])
		var coffers := []
		for chest: Dictionary in dungeon.chests:
			coffers.append([chest.id, _coordinates(chest.position), chest.room, chest.locked])
		var arrival := [_coordinates(dungeon.spawn_position), dungeon.spawn_yaw]
		var fingerprint := JSON.stringify([tiles, bounds, arrival, enemies, coffers], "", true, true).sha256_text()
		_check(fingerprint == fixture[3], "Older saves retain their original encounter identities and layout",
			"version %d, depth %d, seed %d" % [fixture[0], fixture[1], fixture[2]])
		dungeon.free()


func _coordinates(point: Vector3) -> Array:
	return [point.x, point.y, point.z]


func _verify_collision() -> void:
	var dungeon := DungeonScene.instantiate() as Dungeon
	var floor_material: Material = dungeon.get_node("CellTemplate/Floor/Flagstones").material_override
	var ceiling_material := dungeon.get_node("CellTemplate/Ceiling/VaultedStone").material_override as StandardMaterial3D
	dungeon.build(12, 95545)
	_check(_verify_shell_surface(dungeon, _geometry_texture(floor_material), Vector3.UP),
		"Generated flagstones cover the dungeon and face into the room")
	_check(_verify_shell_surface(dungeon, ceiling_material.albedo_texture, Vector3.DOWN),
		"Generated ceiling covers the dungeon and faces into the room")
	_check(not dungeon.navigation_map().is_valid(), "Off-tree dungeon has no live navigation context")
	root.add_child(dungeon)
	await _wait_for_navigation(dungeon)
	_check(dungeon.navigation_map().is_valid(), "Native region becomes usable after synchronization")
	var distant: Vector3 = dungeon.encounters.back().position
	var before: PackedVector3Array = dungeon.navigation_route(dungeon.spawn_position, distant)
	_check(not before.is_empty(), "Distant room has a complete native route")
	root.remove_child(dungeon)
	_check(not dungeon.navigation_map().is_valid(), "Portal exit withdraws the live navigation context")
	await physics_frame
	root.add_child(dungeon)
	await _wait_for_navigation(dungeon)
	_check(dungeon.navigation_route(dungeon.spawn_position, distant) == before, "Native route is preserved after portal return")
	await physics_frame
	var space := dungeon.get_world_3d().direct_space_state
	for point: Dictionary in dungeon.chests + dungeon.hazard_points + dungeon.encounters:
		var position: Vector3 = point.position
		var query := PhysicsRayQueryParameters3D.create(position + Vector3.UP, position + Vector3.DOWN, 1)
		var floor_hit := space.intersect_ray(query)
		_check(not floor_hit.is_empty() and absf(floor_hit.position.y) <= 0.025, "Floor and spawn clearance after re-entry")
	for room: Dictionary in dungeon.rooms:
		for tile: Vector2i in room.cover:
			var center := dungeon.tile_position(tile)
			var query := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 4.0, center, 1)
			var cover_hit := space.intersect_ray(query)
			_check(not cover_hit.is_empty() and cover_hit.position.y > 1.0, "Cover collision after re-entry")
			_check(dungeon.navigation_route(dungeon.spawn_position, center).is_empty(), "Cover is outside the native navigation surface")
	_verify_native_routes(dungeon, space)
	dungeon.free()


func _verify_shell_surface(dungeon: Dungeon, texture: Texture2D, interior: Vector3) -> bool:
	var triangles := 0
	var meshes := dungeon.get_children()
	var floor := dungeon.get_node_or_null("DungeonFloor/Flagstones")
	if floor != null:
		meshes.append(floor)
	for chunk in meshes:
		if not chunk is MeshInstance3D:
			continue
		for surface in chunk.mesh.get_surface_count():
			var material: Material = chunk.mesh.surface_get_material(surface)
			if texture == null or _geometry_texture(material) != texture:
				continue
			var arrays: Array = chunk.mesh.surface_get_arrays(surface)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for vertex in range(0, positions.size(), 3):
				var edge_a := positions[vertex + 1] - positions[vertex]
				var edge_b := positions[vertex + 2] - positions[vertex]
				# Godot treats clockwise triangles as front-facing.
				if edge_a.cross(edge_b).dot(interior) >= 0.0 or normals[vertex].dot(interior) < 0.99:
					return false
				triangles += 1
	return triangles == dungeon.map_cells.size() * 2


func _verify_continuous_stairs(rise: int) -> void:
	var stack := Node3D.new()
	var floors: Array[Dungeon] = []
	for index in 3:
		var dungeon := DungeonScene.instantiate() as Dungeon
		var features := Dungeon.FEATURE_ROUTE_GATE if index < 2 else Dungeon.FEATURE_BLOOD_ALTAR
		dungeon.build(8, 31911 + index * 9043, Dungeon.GENERATION_VERSION, index, 3, 7, rise, features)
		if not floors.is_empty():
			Dungeon.join_floors(floors[-1], dungeon)
		stack.add_child(dungeon)
		floors.append(dungeon)
	root.add_child(stack)
	await _wait_for_navigation(floors[0])
	_check(stack.find_children("*", "WorldEnvironment", true, false).size() == 1,
		"The continuous dungeon shares one world environment", str(rise))
	_check(floors[0].route_gates.size() == 1 and floors[1].route_gates.size() == 1
		and floors[0].route_gates[0].id != floors[1].route_gates[0].id,
		"Two gated floors carry distinct keys in traversable order", str(rise))
	var chamber := floors[2]
	_check(chamber.blood_altar_position.is_finite()
		and int(chamber.map_cells.get(chamber.tile_at(chamber.to_global(chamber.blood_altar_position)), -1)) >= 2
		and chamber.route_gates.is_empty(), "The selected blood altar sits in a clear later room", str(rise))
	for index in floors.size() - 1:
		var previous := floors[index]
		var following := floors[index + 1]
		var exit: Node3D = previous.stairs[1]
		var entrance: Node3D = following.stairs[-1]
		var context := "floor %d to %d, rise %d" % [index, index + 1, rise]
		_check(exit.get_node_or_null("Landing/Threshold") == null and entrance.get_node_or_null("Landing/Blocker") == null,
			"Joined stairs have no door or transition trigger", context)
		_check(previous.to_global(exit.landing_endpoint()).is_equal_approx(following.to_global(entrance.landing_endpoint())),
			"The two landings meet without a gap", context)
		_check(previous.ground_is_open(exit.to_global(Vector3(0.0, float(rise), -3.2))),
			"The physical flight is eligible ground for player and inventory drops", context)
		_check(signf(following.global_position.y - previous.global_position.y) == float(rise),
			"The expedition can climb or descend", context)
		var start := exit.global_position + exit.global_basis.z * 1.05
		var finish := entrance.global_position + entrance.global_basis.z * 1.05
		_check(await _walk_stair(start, finish), "A real physics body walks the entire stair without teleporting", context)
		_check(await _walk_stair(finish, start), "The same stair works in the reverse direction", context)
		_check(previous.floor_contains(start) and following.floor_contains(finish) and not following.floor_contains(start),
			"The map can identify the current floor from world position", context)
		var route := previous.navigation_route(start, finish)
		_check(not route.is_empty(), "Native enemy navigation crosses the same stair", context)
		_verify_gate_placement(previous, context)
	stack.free()


func _verify_disabled_features() -> void:
	var dungeon := Dungeon.new()
	dungeon.build(8, 95545, Dungeon.GENERATION_VERSION, 0, 3, 7, 1, 0)
	_check(dungeon.route_gates.is_empty() and not dungeon.blood_altar_position.is_finite()
		and not dungeon.encounters.any(func(entry: Dictionary) -> bool: return entry.has("spawn_trigger"))
		and not dungeon.chests.any(func(entry: Dictionary) -> bool: return entry.has("trial_waves")),
		"A floor with an empty feature plan reserves no optional interactions")
	dungeon.free()


func _verify_gate_placement(dungeon: Dungeon, context: String) -> void:
	for gate: Dictionary in dungeon.route_gates:
		var usable_cells := dungeon.map_cells.duplicate()
		for tile: Vector2i in dungeon._cover_tiles:
			usable_cells.erase(tile)
		var start: Vector2i = dungeon.stair_tiles.get(-1, dungeon.tile_at(dungeon.to_global(dungeon.spawn_position)))
		var open := RouteGates.reachable(dungeon.map_cells, start)
		var closed := RouteGates.reachable(dungeon.map_cells, start, gate.gate_tile)
		var key_path := RouteGates.reachable(usable_cells, start, gate.gate_tile)
		_check(key_path.has(gate.key_tile) and closed.size() + 10 < open.size() and not dungeon.coffer_tiles.has(gate.key_tile),
			"The key lies on the reachable side of a gate with no open bypass", context)
		if gate.protects_exit:
			var exit_tile: Vector2i = dungeon.stair_tiles[1]
			_check(open.has(exit_tile) and not closed.has(exit_tile), "The gate controls the connecting stair", context)


func _walk_stair(start: Vector3, finish: Vector3) -> bool:
	var body := CharacterBody3D.new()
	body.floor_snap_length = 0.28
	body.collision_mask = 1
	body.collision_layer = 0
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.74
	collision.shape = capsule
	collision.position.y = 0.87
	body.add_child(collision)
	root.add_child(body)
	body.position = start + Vector3.UP * 0.08
	var reached := false
	for frame in 335:
		await physics_frame
		var remaining := finish - body.position
		remaining.y = 0.0
		if remaining.length() < 0.24:
			reached = absf(body.position.y - finish.y) < 0.12 and body.is_on_floor()
			break
		var vertical := 0.0 if body.is_on_floor() else body.velocity.y - 9.8 / 60.0
		body.velocity = remaining.normalized() * 3.6 + Vector3.UP * vertical
		body.move_and_slide()
	if not reached:
		print("Stair walk ended at %s, wanted %s" % [body.position, finish])
	body.free()
	return reached


func _geometry_texture(material: Material) -> Texture2D:
	if material is BaseMaterial3D:
		return material.albedo_texture
	if material is ShaderMaterial:
		return material.get_shader_parameter("stone_albedo") as Texture2D
	return null


func _wait_for_navigation(dungeon: Node3D) -> void:
	for frame in range(120):
		await physics_frame
		if dungeon.navigation_map().is_valid():
			return


func _verify_native_routes(dungeon: Node3D, space: PhysicsDirectSpaceState3D) -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.60
	capsule.height = 1.55
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	for index in range(dungeon.encounters.size()):
		var target: Vector3 = dungeon.encounters[index].position
		var path: PackedVector3Array = dungeon.navigation_route(dungeon.spawn_position, target)
		_check(not path.is_empty(), "Every generated enemy has a complete native route", str(index))
		if index % 8 != 0:
			continue
		var clear := true
		for step in range(1, path.size()):
			var from := path[step - 1]
			var to := path[step]
			var samples := maxi(1, ceili(from.distance_to(to) / 0.24))
			for sample in range(samples + 1):
				var point := from.lerp(to, float(sample) / float(samples))
				query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.80)
				if not space.intersect_shape(query, 1).is_empty():
					clear = false
					break
			if not clear:
				break
		_check(clear, "Native path has body clearance through walls and cover", str(index))


func _check(condition: bool, requirement: String, context := "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(requirement if context.is_empty() else "%s (%s)" % [requirement, context])

