extends RefCounted
## Finds a lockable corridor whose key is reachable with the gate closed.

const STEPS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


static func choose(dungeon: Node3D, occupied: Dictionary, floor_index: int, seed_value: int) -> Dictionary:
	var cells: Dictionary = dungeon.map_cells
	var usable_cells := cells.duplicate()
	for tile: Vector2i in dungeon._cover_tiles:
		usable_cells.erase(tile)
	var start: Vector2i = dungeon.stair_tiles.get(-1, dungeon.tile_at(dungeon.spawn_position))
	var arrival: Dictionary = reachable(cells, start)
	var has_outgoing_stair: bool = dungeon.stair_tiles.has(1)
	var outgoing: Vector2i = dungeon.stair_tiles.get(1, start)
	var from_exit := reachable(cells, outgoing) if has_outgoing_stair else {}
	var candidates: Array[Dictionary] = []
	for tile: Vector2i in arrival:
		if int(cells[tile]) != -1 or occupied.has(tile) or int(arrival[tile]) < 12:
			continue
		var direction := _corridor_direction(cells, tile)
		if direction == Vector2i.ZERO:
			continue
		var score := float(posmod(hash([tile, seed_value, floor_index]), 1000)) / 1000.0
		if from_exit.has(tile):
			var path_length := int(arrival[tile]) + int(from_exit[tile])
			score += 16.0 - (path_length - int(arrival.get(outgoing, 0))) * 0.65
			# Favor the middle of a route, leaving reachable rooms in which to hide the key.
			score -= absf(float(arrival[tile]) / float(maxi(1, path_length)) - 0.55) * 13.0
		candidates.append({"tile": tile, "direction": direction, "score": score})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.score > b.score)
	var fallback := {}
	for candidate: Dictionary in candidates:
		var gate: Vector2i = candidate.tile
		var front := reachable(cells, start, gate)
		if front.size() + 10 >= arrival.size():
			continue
		var protects_exit := has_outgoing_stair and not front.has(outgoing)
		if not protects_exit and not fallback.is_empty():
			continue
		if not protects_exit and not _protects_room(dungeon.rooms, front, arrival):
			continue
		# Check bypasses even around partial cover, but give the key a guaranteed clear approach.
		var usable_front := reachable(usable_cells, start, gate)
		var key := _choose_key(usable_front, cells, occupied, gate, seed_value)
		if not usable_front.has(key):
			continue
		var direction: Vector2i = candidate.direction
		var result := {"id": "route_gate_%d" % floor_index, "gate_tile": gate, "key_tile": key,
			"position": dungeon.tile_position(gate), "yaw": atan2(-float(direction.x), -float(direction.y)),
			"key_position": dungeon.tile_position(key), "protects_exit": protects_exit,
			"key_name": "Obsidian Gate Key" if floor_index == 0 else "Bronze Gate Key"}
		if protects_exit or not has_outgoing_stair:
			return result
		fallback = result
	return fallback


static func reachable(cells: Dictionary, start: Vector2i, blocked := Vector2i(999999, 999999)) -> Dictionary:
	var distances := {start: 0}
	var queue: Array[Vector2i] = [start]
	var index := 0
	while index < queue.size():
		var tile: Vector2i = queue[index]
		index += 1
		for direction: Vector2i in STEPS:
			var next := tile + direction
			if next != blocked and cells.has(next) and not distances.has(next):
				distances[next] = int(distances[tile]) + 1
				queue.append(next)
	return distances


static func _corridor_direction(cells: Dictionary, tile: Vector2i) -> Vector2i:
	for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
		var across := Vector2i(direction.y, -direction.x)
		if int(cells.get(tile + direction, -2)) == -1 and int(cells.get(tile - direction, -2)) == -1 \
				and not cells.has(tile + across) and not cells.has(tile - across):
			return direction
	return Vector2i.ZERO


static func _protects_room(rooms: Array[Dictionary], front: Dictionary, all: Dictionary) -> bool:
	return rooms.any(func(room: Dictionary) -> bool:
		return room.role != &"quiet" and all.has(room.center) and not front.has(room.center))


static func _choose_key(front: Dictionary, cells: Dictionary, occupied: Dictionary, gate: Vector2i, seed_value: int) -> Vector2i:
	var result := Vector2i(999999, 999999)
	var best := -INF
	for tile: Vector2i in front:
		var room: int = cells.get(tile, -1)
		if room < 1 or occupied.has(tile) or tile.distance_squared_to(gate) < 25:
			continue
		var interior := 0
		for direction: Vector2i in STEPS:
			interior += int(int(cells.get(tile + direction, -1)) == room)
		if interior < 3:
			continue
		var score := float(mini(32, int(front[tile]))) * 0.2 + float(interior) * 1.4
		score += float(posmod(hash([tile, seed_value]), 1000)) / 500.0
		if score > best:
			best = score
			result = tile
	return result
