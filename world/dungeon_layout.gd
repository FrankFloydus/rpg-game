extends RefCounted
## Produces the seeded chamber graph and walkable tile map for expeditions.

const NORTH := Vector2i.UP
const CARDINALS: Array[Vector2i] = [NORTH, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const TOPOLOGIES: Array[StringName] = [&"braided", &"radial", &"processional"]
const SHAPES: Array[StringName] = [&"rectangle", &"cruciform", &"alcove", &"octagon", &"stagger", &"nave"]
const STRIDE := 12

var rng := RandomNumberGenerator.new()
var topology: StringName
var gate: Vector2i
var map_cells: Dictionary = {}
var rooms: Array[Dictionary] = []
var corridors: Array[Dictionary] = []

var _coarse: Array[Vector2i] = []
var _sectors: Array[int] = []
var _indices: Dictionary = {}
var _links: Array[Vector2i] = []
var _room_tracks: Array[Dictionary] = []
var _version := 2


func generate(depth: int, seed_value: int, max_rooms: int, version: int = 2) -> void:
	_version = version
	rng.seed = seed_value
	topology = TOPOLOGIES[rng.randi_range(0, TOPOLOGIES.size() - 1)]
	var room_count := mini(max_rooms, 6 + 2 * mini(8, depth - 1))
	var quarter_turns := rng.randi_range(0, 3)
	if _version >= 4:
		_exploration_graph(room_count)
	else:
		_graph(room_count)
	for index in range(_coarse.size()):
		_coarse[index] = _rotate(_coarse[index], quarter_turns)
	gate = _coarse[1] - _coarse[0]
	if _version >= 4:
		_room_tracks = [_make_track(Vector2i.RIGHT), _make_track(Vector2i.DOWN)]
	_carve_rooms(depth)
	for index in range(_links.size()):
		if _version >= 5:
			_route_weighted_gallery(_links[index], index)
		elif _version == 4:
			_route_gallery(_links[index], index)
		else:
			_carve_corridor(_links[index], index)
	if _version >= 4:
		_connect_galleries(depth)
	_survey_rooms()


func _graph(count: int) -> void:
	_insert(Vector2i.ZERO)
	_insert(NORTH, 0)
	var side := Vector2i(rng.randi_range(0, 1) * 2 - 1, 0)
	match topology:
		&"braided":
			_insert(NORTH + side, 1)
			_insert(NORTH * 2, 1)
			_insert(NORTH * 2 + side, 3)
			_links.append(Vector2i(2, 4))
		&"radial":
			_insert(NORTH + side, 1, 2)
			_insert(NORTH - side, 1, 3)
			_insert(NORTH * 2, 1, 4)
		&"processional":
			_insert(NORTH * 2, 1)
			_insert(NORTH * 3, 2)
			_insert(NORTH * 3 + side, 3)
	var lane := side
	for index in range(5, count):
		var parent := _best_frontier(index, lane)
		_insert(_coarse[parent.x] + CARDINALS[parent.y], parent.x, _sectors[parent.x])
		if topology == &"processional" and index % 4 == 0:
			lane = -lane
	_add_shortcuts(count)


func _exploration_graph(count: int) -> void:
	_insert(Vector2i.ZERO)
	_insert(NORTH, 0)
	for index in range(2, count):
		var best := -INF
		var next := Vector2i.ZERO
		var origin := 1
		for parent in range(1, index):
			var degree := _degree(parent)
			for direction in CARDINALS:
				var candidate := _coarse[parent] + direction
				if _indices.has(candidate):
					continue
				var travel := float(candidate.length())
				var score := rng.randf_range(-2.5, 2.5) - float(maxi(0, degree - 2)) * 3.0
				match topology:
					&"braided":
						score -= 0.80 * travel
					&"radial":
						score -= 0.42 * travel
						score += 0.75 if degree == 1 else 0.0
					&"processional":
						score += 1.35 if parent == index - 1 and index % 4 != 0 else 0.0
						score -= maxf(0.0, travel - 4.0) * 0.7
				if score > best:
					best = score
					next = candidate
					origin = parent
		_insert(next, origin)
	_add_shortcuts(count)


func _insert(tile: Vector2i, parent := -1, sector := 0) -> void:
	var index := _coarse.size()
	_coarse.append(tile)
	_sectors.append(sector)
	_indices[tile] = index
	if parent >= 0:
		_links.append(Vector2i(parent, index))


func _best_frontier(index: int, lane: Vector2i) -> Vector2i:
	var best := Vector2i.ZERO
	var best_score := -INF
	for parent in range(1, _coarse.size()):
		for direction in range(CARDINALS.size()):
			var step := CARDINALS[direction]
			var tile := _coarse[parent] + step
			if _indices.has(tile):
				continue
			var score := rng.randf_range(-1.50, 1.50)
			match topology:
				&"braided":
					var neighbors := 0
					for offset in CARDINALS:
						if _indices.has(tile + offset):
							neighbors += 1
					score += float(neighbors) * 1.8 - float(tile.length()) * 0.42
				&"radial":
					var sector := _sectors[parent]
					score += 6.0 if sector == 2 + ((index - 5) % 3) else 0.0
					var outward := _coarse[sector] - _coarse[1] if sector >= 2 else NORTH
					score += float(_dot(outward, step)) * 1.52
					var relative := tile - _coarse[1]
					score -= absf(float(outward.x * relative.y - outward.y * relative.x)) * 0.57
					score -= maxf(0.0, float((tile - _coarse[1]).length()) - 3.6) * 1.85
				&"processional":
					var age := index - parent
					score += 3.6 if age == 1 and index % 4 != 3 else 0.0
					score += 1.9 if age > 2 and index % 4 == 3 else 0.0
					score += 1.15 * float(_dot(lane, step))
					score += 1.15 if step == NORTH and tile.y > -6 else 0.0
					score -= maxf(0.0, -float(tile.y) - 4.0) * 1.35
			if score > best_score:
				best = Vector2i(parent, direction)
				best_score = score
	return best


func _add_shortcuts(count: int) -> void:
	var options: Array[Vector2i] = []
	for room in range(1, count):
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var neighbor := int(_indices.get(_coarse[room] + offset, -1))
			if neighbor <= 0:
				continue
			var edge := Vector2i(room, neighbor)
			if not _links.has(edge) and not _links.has(Vector2i(neighbor, room)):
				options.append(edge)
	var budget := maxi(1, floori(count / 3.0)) if topology == &"braided" else floori(count / 7.0)
	for ignored in range(mini(budget, options.size())):
		_links.append(options.pop_at(rng.randi_range(0, options.size() - 1)))


func _dot(first: Vector2i, second: Vector2i) -> int:
	return first.x * second.x + first.y * second.y


func _rotate(point: Vector2i, turns: int) -> Vector2i:
	match turns:
		1: return Vector2i(-point.y, point.x)
		2: return -point
		3: return Vector2i(point.y, -point.x)
	return point


func _make_track(axis: Vector2i) -> Dictionary:
	var lower := 0
	var upper := 0
	for point in _coarse:
		var coordinate := _dot(point, axis)
		lower = mini(lower, coordinate)
		upper = maxi(upper, coordinate)
	var result := {0: 0}
	for direction: int in [-1, 1]:
		var distance := 0
		var count := upper if direction > 0 else -lower
		for lane in range(1, count + 1):
			# Alternating tight and long gallery bays break up the old fixed spacing.
			distance += rng.randi_range(9, 13) if _version >= 5 else rng.randi_range(8, 11)
			result[lane * direction] = distance * direction
	return result


func _carve_rooms(depth: int) -> void:
	var vault_rooms := _vault_rooms(depth)
	var quiet_rooms: Array[int] = []
	if _version >= 4:
		var candidates: Array[int] = []
		for index in range(2, _coarse.size()):
			if index not in vault_rooms:
				candidates.append(index)
		for ignored in mini(candidates.size(), maxi(1, floori(_coarse.size() / 5.0))):
			quiet_rooms.append(candidates.pop_at(rng.randi_range(0, candidates.size() - 1)))
	for index in range(_coarse.size()):
		var center := _coarse[index] * STRIDE
		if _version >= 4:
			center = Vector2i(_room_tracks[0][_coarse[index].x], _room_tracks[1][_coarse[index].y])
			if _version >= 5 and index > 0:
				center += Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
		if index > 0 and _version < 4:
			center += Vector2i(rng.randi_range(-1, 1), rng.randi_range(-1, 1))
		var shape := SHAPES[(index + rng.randi_range(0, SHAPES.size() - 1)) % SHAPES.size()]
		var role := &"hunting"
		var radius := Vector2i(rng.randi_range(2, 3), rng.randi_range(2, 3))
		if index == 0:
			shape = &"rectangle"
			role = &"arrival"
			radius = Vector2i(2, 2)
		elif vault_rooms.has(index):
			shape = &"alcove" if posmod(index, 2) == 0 else &"octagon"
			role = &"vault"
			radius = Vector2i(3, rng.randi_range(2, 3))
		elif (topology == &"radial" and index == 1) or (index > 1 and _degree(index) >= 3):
			shape = &"octagon" if index == 1 else &"cruciform"
			role = &"arena"
			radius = Vector2i(4, rng.randi_range(3, 4))
		elif index == 1:
			shape = &"nave"
			role = &"guard"
			radius = Vector2i(2, 3)
		elif shape == &"nave":
			radius.y = 4
		elif depth >= 5 and rng.randf() < 0.43:
			radius.x = 4
		var rotation := rng.randi_range(0, 3)
		if _version >= 4:
			radius = Vector2i(1, rng.randi_range(1, 2))
			if role == &"arrival":
				radius = Vector2i(2, 1)
				rotation = 1 if gate.x != 0 else 0
			elif role == &"vault":
				radius = Vector2i(2, 1)
			elif index in quiet_rooms:
				role = &"quiet"
				radius = Vector2i.ONE
			elif role == &"arena":
				radius = Vector2i(2, 2)
				shape = &"octagon" if rng.randf() < 0.52 else &"cruciform"
		if _version >= 5 and index > 0:
			match role:
				&"vault":
					radius = Vector2i(2, rng.randi_range(1, 2))
				&"arena":
					radius = Vector2i(2, 3 if rng.randf() < 0.58 else 2)
				&"guard":
					radius = Vector2i(1, 2)
				&"hunting":
					radius = Vector2i(rng.randi_range(1, 2), rng.randi_range(1, 2))
					if rng.randf() < 0.20:
						radius.y = 3
		var bounds_radius := _rotate(radius, rotation).abs()
		var bounds := Rect2i(center - bounds_radius, bounds_radius * 2 + Vector2i.ONE)
		var tiles: Array[Vector2i] = []
		for z in range(bounds.position.y, bounds.end.y):
			for x in range(bounds.position.x, bounds.end.x):
				var tile := Vector2i(x, z)
				var relative := _rotate(tile - center, posmod(-rotation, 4))
				if _in_shape(relative, radius, shape):
					map_cells[tile] = index
					tiles.append(tile)
		rooms.append({
			"id": index, "center": center, "bounds": bounds, "shape": shape,
			"role": role, "tiles": tiles,
		})


func _in_shape(point: Vector2i, radius: Vector2i, shape: StringName) -> bool:
	var extent := point.abs()
	match shape:
		&"cruciform":
			return extent.x <= maxi(1, radius.x - 2) or extent.y <= maxi(1, radius.y - 2)
		&"alcove":
			if _version >= 4:
				return point.x < radius.x or point.y <= 0
			return point.x < 2 or point.y < 1
		&"octagon":
			return extent.x + extent.y < radius.x + radius.y
		&"stagger":
			return not ((point.x == radius.x and point.y < -1) or (point.x == -radius.x and point.y > 1))
		&"nave":
			if _version >= 4:
				return extent.x < radius.x or extent.y == 0 or extent.y == radius.y
			return extent.x < radius.x or extent.y % 2 == 1
		_:
			return true


func _degree(room: int) -> int:
	var count := 0
	for link in _links:
		if link.x == room or link.y == room:
			count += 1
	return count


func _vault_rooms(depth: int) -> Array[int]:
	var steps := {0: 0}
	var frontier: Array[int] = [0]
	while not frontier.is_empty():
		var room: int = frontier.pop_front()
		for link in _links:
			var neighbor := link.y if link.x == room else link.x if link.y == room else -1
			if neighbor < 0 or steps.has(neighbor):
				continue
			steps[neighbor] = int(steps[room]) + 1
			frontier.append(neighbor)
	var choices: Array[int] = []
	for room in range(2, _coarse.size()):
		choices.append(room)
	choices.sort_custom(func(first: int, second: int) -> bool:
		var first_score := int(steps[first]) * 10 - _degree(first)
		var second_score := int(steps[second]) * 10 - _degree(second)
		if _version >= 4:
			first_score += 30 if _degree(first) == 1 else 0
			second_score += 30 if _degree(second) == 1 else 0
		return first_score > second_score
	)
	return choices.slice(0, 2 if depth >= 4 else 1)


func _carve_corridor(edge: Vector2i, index: int) -> void:
	var forward := _coarse[edge.y] - _coarse[edge.x]
	var across := Vector2i(-forward.y, forward.x)
	var first: Vector2i = rooms[edge.x].center
	var last: Vector2i = rooms[edge.y].center
	var first_bounds: Rect2i = rooms[edge.x].bounds
	var last_bounds: Rect2i = rooms[edge.y].bounds
	var offset := 0 if edge.x == 0 else rng.randi_range(-1, 1)
	first += across * offset
	last += across * rng.randi_range(-1, 1)
	var begin := _edge_projection(first_bounds, forward, true)
	var end := _edge_projection(last_bounds, forward, false)
	var bend := rng.randi_range(begin + 1, end - 1)
	var junction := first + forward * (bend - _dot(first, forward))
	var turn := junction + across * _dot(last - first, across)
	var path: Array[Vector2i] = []
	_carve_segment(first, junction, path)
	_carve_segment(junction, turn, path)
	_carve_segment(turn, last, path)
	if edge.x != 0 and rng.randf() < (0.62 if topology == &"braided" else 0.43):
		_carve_passage_bay(path, across, forward)
	corridors.append({"id": index, "rooms": edge, "tiles": path})


func _route_gallery(edge: Vector2i, index: int) -> void:
	var forward := _coarse[edge.y] - _coarse[edge.x]
	var across := Vector2i(-forward.y, forward.x)
	var first := _room_port(edge.x, forward)
	var last := _room_port(edge.y, -forward)
	var begin := _edge_projection(rooms[edge.x].bounds, forward, true)
	var end := _edge_projection(rooms[edge.y].bounds, forward, false)
	var bend := rng.randi_range(begin + 2, end - 2)
	var junction := first + forward * (bend - _dot(first, forward))
	var turn := junction + across * _dot(last - first, across)
	var path: Array[Vector2i] = []
	_carve_segment(first, junction, path)
	_carve_segment(junction, turn, path)
	_carve_segment(turn, last, path)
	if edge.x != 0 and rng.randf() < (0.66 if topology == &"braided" else 0.47):
		_carve_passage_bay(path, across, forward)
	corridors.append({
		"id": index, "rooms": edge, "tiles": path,
		"ports": [Vector4i(first.x, first.y, forward.x, forward.y),
			Vector4i(last.x, last.y, -forward.x, -forward.y)],
	})


## Carve the shortest weighted legal route between wall sockets. Existing galleries can
## become junctions, while room walls and the opening gallery stay out of later routes.
func _route_weighted_gallery(edge: Vector2i, index: int) -> void:
	var forward := _coarse[edge.y] - _coarse[edge.x]
	var first := _room_port(edge.x, forward)
	var last := _room_port(edge.y, -forward)
	var entrance := first + forward
	var exit := last - forward
	var search_area := Rect2i(entrance.min(exit), (entrance - exit).abs() + Vector2i.ONE).grow(7)
	var path := _weighted_route(entrance, exit, search_area, true)
	if path.is_empty():
		for room in rooms:
			search_area = search_area.merge(room.bounds)
		path = _weighted_route(entrance, exit, search_area.grow(4), true)
	if path.is_empty():
		# The footprint spacing keeps sockets accessible. Around a bent corner, opening a
		# side wall is preferable to disconnecting a room.
		path = _weighted_route(entrance, exit, search_area.grow(4), false)
	if path.is_empty():
		push_error("No legal gallery connects chambers %d and %d" % [edge.x, edge.y])
		return
	for tile in path:
		map_cells[tile] = -1
	if edge.x != 0 and rng.randf() < 0.43:
		var across := Vector2i(-forward.y, forward.x)
		_carve_passage_bay(path, across, forward)
	corridors.append({"id": index, "rooms": edge, "tiles": path,
		"ports": [Vector4i(first.x, first.y, forward.x, forward.y),
			Vector4i(last.x, last.y, -forward.x, -forward.y)]})


func _weighted_route(start: Vector2i, finish: Vector2i, search_area: Rect2i,
		preserve_walls: bool) -> Array[Vector2i]:
	var router := AStarGrid2D.new()
	router.region = search_area
	router.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	router.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	router.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
	router.update()
	var reserved := {}
	if not corridors.is_empty():
		for tile: Vector2i in corridors[0].tiles:
			reserved[tile] = true
			for side in CARDINALS:
				reserved[tile + side] = true
	for y in range(search_area.position.y, search_area.end.y):
		for x in range(search_area.position.x, search_area.end.x):
			var tile := Vector2i(x, y)
			if tile == start or tile == finish:
				continue
			var room_tile := int(map_cells.get(tile, -2)) >= 0
			if room_tile or reserved.has(tile) or (preserve_walls and _touches_room(tile)):
				router.set_point_solid(tile)
				continue
			var variation := float(posmod(hash([rng.seed, tile]), 1024)) / 1024.0
			var base_cost := 1.0 if map_cells.has(tile) else 1.16
			router.set_point_weight_scale(tile, base_cost + variation * 0.72)
	return router.get_id_path(start, finish)


func _room_port(id: int, direction: Vector2i) -> Vector2i:
	var across := Vector2i(-direction.y, direction.x)
	var center: Vector2i = rooms[id].center
	var preferred := 0 if id == 0 else rng.randi_range(-1, 1)
	var best := center
	for offset: int in [0, preferred, -preferred]:
		var tile := center + across * offset
		while map_cells.get(tile + direction) == id:
			tile += direction
		if offset == 0:
			best = tile
		if map_cells.get(tile + across) != id or map_cells.get(tile - across) != id:
			continue
		if map_cells.get(tile + direction + across) == id or map_cells.get(tile + direction - across) == id:
			continue
		# Use the plain wall run nearest the preferred part of the room.
		best = tile
		if offset == preferred:
			break
	return best


func _connect_galleries(depth: int) -> void:
	var approaches: Dictionary = {}
	for corridor in corridors:
		if corridor.rooms.x == 0:
			continue
		for port: Vector4i in corridor.ports:
			var tile := Vector2i(port.x, port.y)
			var start := tile + Vector2i(port.z, port.w) * 2
			if map_cells.get(start) != -1 or _touches_room(start):
				continue
			var id: int = map_cells[tile]
			if not approaches.has(id):
				approaches[id] = []
			approaches[id].append(start)
	var count := 0
	for id: int in approaches:
		if rooms[id].role in [&"vault", &"quiet"]:
			continue
		var entries: Array = approaches[id]
		for first_index in range(entries.size()):
			for last_index in range(first_index + 1, entries.size()):
				var first: Vector2i = entries[first_index]
				var last: Vector2i = entries[last_index]
				var path := _gallery_bypass(first, last, Vector2i(first.x, last.y))
				if path.is_empty():
					path = _gallery_bypass(first, last, Vector2i(last.x, first.y))
				if path.is_empty():
					continue
				for tile in path:
					map_cells[tile] = -1
				corridors.append({"id": corridors.size(), "rooms": Vector2i(id, id),
					"tiles": path, "ports": []})
				count += 1
				if count >= 1 + mini(2, floori(depth / 4.0)):
					return


func _gallery_bypass(first: Vector2i, last: Vector2i, bend: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var tile := first
	for end in [bend, last]:
		var step := (Vector2i(end) - tile).sign()
		while tile != end:
			tile += step
			if tile == last:
				break
			if map_cells.has(tile) or _touches_room(tile):
				return []
			for direction in CARDINALS:
				var neighbor := tile + direction
				if neighbor != first and neighbor != last and map_cells.has(neighbor):
					return []
			path.append(tile)
	return path


func _edge_projection(bounds: Rect2i, direction: Vector2i, far_side: bool) -> int:
	var corner := bounds.end - Vector2i.ONE
	var step := direction if far_side else -direction
	if step.x < 0:
		corner.x = bounds.position.x
	if step.y < 0:
		corner.y = bounds.position.y
	return _dot(corner, direction)


func _carve_segment(first: Vector2i, last: Vector2i, path: Array[Vector2i]) -> void:
	var tile := first
	var step := (last - first).sign()
	while true:
		if not map_cells.has(tile):
			map_cells[tile] = -1
		if int(map_cells[tile]) < 0 and (path.is_empty() or path.back() != tile):
			path.append(tile)
		if tile == last:
			return
		tile += step


func _carve_passage_bay(path: Array[Vector2i], across: Vector2i, forward: Vector2i) -> void:
	if path.size() < 3:
		return
	var anchor: Vector2i = path[floori(path.size() * 0.5)]
	var side := across * (rng.randi_range(0, 1) * 2 - 1)
	for width in range(1, rng.randi_range(2, 3)):
		var center := anchor + side * width
		if _touches_room(center):
			break
		for tile: Vector2i in [center, center - forward, center + forward]:
			if not map_cells.has(tile) and not _touches_room(tile):
				map_cells[tile] = -1
				path.append(tile)


func _touches_room(tile: Vector2i) -> bool:
	if int(map_cells.get(tile, -1)) >= 0:
		return true
	for adjacent in CARDINALS:
		if int(map_cells.get(tile + adjacent, -1)) >= 0:
			return true
	return false


func _survey_rooms() -> void:
	for room in rooms:
		var id: int = room.id
		var doors: Array[Vector2i] = []
		var interior: Array[Vector2i] = []
		for tile: Vector2i in room.tiles:
			var connected := 0
			var door := false
			for step in CARDINALS:
				var neighbor := int(map_cells.get(tile + step, -2))
				if neighbor == id:
					connected += 1
				elif neighbor == -1:
					door = true
			if door:
				doors.append(tile)
			if connected == 4:
				interior.append(tile)
		room["interior"] = interior
		room["doors"] = doors
		room["cover"] = []

