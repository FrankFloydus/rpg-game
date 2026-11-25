extends RefCounted
## Fits existing coffer records to usable floor space after doors and stairs are known.

const CARDINALS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const WALL_SETBACK := 0.57
const CACHE_SIDE_OFFSET := 0.68


static func solve(dungeon: Node3D, thresholds: Dictionary, covers: Dictionary, seed_value: int) -> Dictionary:
	var room_tiles := {}
	var room_doors := {}
	for tile: Vector2i in dungeon.map_cells:
		var room := int(dungeon.map_cells[tile])
		if room < 0:
			continue
		if not room_tiles.has(room):
			room_tiles[room] = []
		room_tiles[room].append(tile)
		if thresholds.has(tile):
			if not room_doors.has(room):
				room_doors[room] = []
			room_doors[room].append(tile)
	var blocked := covers.duplicate()
	blocked.merge(thresholds)
	blocked.merge(dungeon.stair_approach_tiles)
	for hazard: Dictionary in dungeon.hazard_points:
		blocked[dungeon.tile_at(hazard.position)] = true
	var pockets := {}
	for index in dungeon.side_passages.size():
		var passage: Dictionary = dungeon.side_passages[index]
		if passage.treasure:
			pockets[passage.tip] = index
	var poses: Dictionary[int, Transform3D] = {}
	for coffer: Dictionary in dungeon.chests:
		var id := int(coffer.id)
		var origin: Vector2i = dungeon.tile_at(coffer.position)
		var room := int(coffer.room)
		if coffer.has("fixed_yaw"):
			poses[id] = Transform3D(Basis(Vector3.UP, float(coffer.fixed_yaw)), coffer.position)
			blocked[origin] = true
			continue
		if coffer.has("wall_edge"):
			poses[id] = _wall_pose(dungeon, origin, coffer.wall_edge)
			continue
		if pockets.has(origin):
			poses[id] = _blind_end_pose(dungeon, int(pockets[origin]), bool(coffer.get("paired_cache", false)))
			continue
		var wall := _room_wall(dungeon, room_tiles.get(room, []), room_doors.get(room, []),
			blocked, coffer, origin, seed_value)
		if wall == Vector4i.ZERO:
			push_error("Coffer %d in room %d has no solid wall with a clear approach" % [id, room])
			poses[id] = Transform3D(Basis.IDENTITY, coffer.position)
			continue
		var tile := Vector2i(wall.x, wall.y)
		poses[id] = _wall_pose(dungeon, tile, Vector2i(wall.z, wall.w))
		blocked[tile] = true
	return poses


static func _room_wall(dungeon: Node3D, tiles: Array, doors: Array, blocked: Dictionary,
		coffer: Dictionary, origin: Vector2i, seed_value: int) -> Vector4i:
	var best := Vector4i.ZERO
	var best_score := -INF
	var half_cell: float = dungeon.CELL_SIZE * 0.5
	var room := int(coffer.room)
	for tile: Vector2i in tiles:
		if blocked.has(tile):
			continue
		var door_distance := INF
		for door: Vector2i in doors:
			door_distance = minf(door_distance, tile.distance_squared_to(door))
		for outward in CARDINALS:
			if dungeon.map_cells.has(tile + outward):
				continue
			var inward_neighbor := int(dungeon.map_cells.get(tile - outward, -2))
			if inward_neighbor != room and inward_neighbor != -2:
				continue
			var position: Vector3 = dungeon.tile_position(tile) + Vector3(outward.x, 0, outward.y) * (half_cell - WALL_SETBACK)
			var mob_distance := _nearest_spawn(dungeon, position, room)
			var tangent := Vector2i(-outward.y, outward.x)
			var side_walls := int(not dungeon.map_cells.has(tile + tangent)) + int(not dungeon.map_cells.has(tile - tangent))
			var score := minf(door_distance, 16.0) * 0.6 + float(side_walls) * 1.25
			score += (1.4 if inward_neighbor == room else 0.0) + minf(mob_distance, 4.0) * 0.25
			score -= 9.0 if door_distance <= 2.0 else 0.0
			score -= 5.0 if mob_distance < 0.97 else 0.0
			score -= minf(origin.distance_squared_to(tile), 9.0) * 0.24
			score += float(posmod(hash([seed_value, coffer.id, tile, outward]), 97)) * 0.001
			if score > best_score:
				best = Vector4i(tile.x, tile.y, outward.x, outward.y)
				best_score = score
	return best


static func _nearest_spawn(dungeon: Node3D, point: Vector3, room: int) -> float:
	var distance := INF
	for entry: Dictionary in dungeon.encounters:
		if entry.room == room:
			distance = minf(distance, point.distance_squared_to(entry.position))
	return sqrt(distance)


static func _blind_end_pose(dungeon: Node3D, index: int, paired_cache: bool) -> Transform3D:
	var branch: Dictionary = dungeon.side_passages[index]
	var tip: Vector2i = branch.tip
	var outward: Vector2i = tip - branch.cells[-2]
	var pose := _wall_pose(dungeon, tip, outward)
	# Put the cache on the other side of the terminal cell from its votive cluster.
	var tangent := Vector3(-outward.y, 0, outward.x)
	var side := 1.0 if index % 2 == 0 else -1.0
	pose.origin += tangent * side * (-0.83 if paired_cache else CACHE_SIDE_OFFSET)
	return pose


static func _wall_pose(dungeon: Node3D, tile: Vector2i, outward: Vector2i) -> Transform3D:
	var facing := Vector3(outward.x, 0, outward.y)
	var pose := Basis(Vector3.UP, atan2(-facing.x, -facing.z))
	var point: Vector3 = dungeon.tile_position(tile) + facing * (dungeon.CELL_SIZE * 0.5 - WALL_SETBACK)
	return Transform3D(pose, point)
