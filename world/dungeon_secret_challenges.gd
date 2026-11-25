extends RefCounted
## Fits an authored secret route behind an existing slab without opening a second entrance.

const Catalogue := preload("res://world/secret_challenges/secret_challenge_catalog.gd")
const Route := preload("res://world/secret_challenges/secret_challenge_route.gd")
const Socket := preload("res://world/secret_challenges/secret_challenge_socket.gd")
const STEPS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]


static func try_place(dungeon: Node3D, depth: int, seed_value: int, limits: Rect2i) -> void:
	var sites: Array[Dictionary] = []
	for secret: Dictionary in dungeon.secret_passages:
		var branch: Dictionary = dungeon.side_passages[secret.branch]
		if not branch.get("merchant", false):
			sites.append(secret)
	if sites.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, &"authored secret challenge"])
	var available: Array[Route] = []
	var weights := PackedFloat32Array()
	for route: Route in Catalogue.ROUTES:
		if route.min_depth <= depth and route.weight > 0.0:
			available.append(route)
			weights.append(route.weight)
	while not available.is_empty():
		var index := rng.rand_weighted(weights)
		var route: Route = available.pop_at(index)
		weights.remove_at(index)
		var first_site := rng.randi_range(0, sites.size() - 1)
		for offset in sites.size():
			var site := sites[(first_site + offset) % sites.size()]
			var prefer_alt: bool = not route.alternate_rows.is_empty() and rng.randf() < 0.40
			var turn := 1 if rng.randf() < 0.5 else -1
			for alternate: bool in [prefer_alt, not prefer_alt]:
				if alternate and route.alternate_rows.is_empty():
					continue
				for side: int in [turn, -turn]:
					var stamped := _try_fit(dungeon, route, alternate, side, site, limits)
					if not stamped.is_empty():
						_commit(dungeon, route, stamped, site, rng)
						return


static func _try_fit(dungeon: Node3D, route: Route, alternate: bool, side: int,
		secret: Dictionary, limits: Rect2i) -> Dictionary:
	var branch: Dictionary = dungeon.side_passages[secret.branch]
	var entry := int(secret.entry)
	var approach: Vector2i = branch.cells[entry - 1]
	var first: Vector2i = branch.cells[entry]
	var forward := first - approach
	var across := Vector2i(-forward.y, forward.x) * side
	var orig: Vector2i = route.ingress(alternate)
	var marked := {}
	for tile: Vector2i in route.floor_cells(alternate):
		var translated := _transform_tile(tile - orig, first, forward, across)
		marked[translated] = true
	var legacy := {}
	for tile: Vector2i in secret.hidden_tiles:
		legacy[tile] = true
	var map: Dictionary = dungeon.map_cells
	for tile: Vector2i in marked:
		if (limits.has_area() and not limits.has_point(tile)) or dungeon.stair_approach_tiles.has(tile) \
				or (map.has(tile) and not legacy.has(tile)):
			return {}
		for step: Vector2i in STEPS:
			var other := tile + step
			if (tile == first and other == approach) or marked.has(other) or legacy.has(other):
				continue
			if map.has(other):
				return {}
	var reward := _transform_tile(route.reward(alternate) - orig, first, forward, across)
	var critical_path := _walk_route(marked, first, reward)
	if critical_path.size() < 3:
		return {}
	return {"tiles": marked, "first": first, "forward": forward, "across": across, "local_origin": orig,
		"reward": reward, "path": critical_path, "alternate": alternate}


static func _commit(dungeon: Node3D, route: Route, stamped: Dictionary,
		secret: Dictionary, rng: RandomNumberGenerator) -> void:
	var branch: Dictionary = dungeon.side_passages[secret.branch]
	secret["legacy_hazard_sites"] = branch.cells.size() - int(secret.entry) - 1
	branch["replaced_annex"] = branch.has("annex")
	for tile: Vector2i in secret.hidden_tiles:
		dungeon.map_cells.erase(tile)
	var hidden: Array[Vector2i] = []
	for tile: Vector2i in stamped.tiles:
		dungeon.map_cells[tile] = -1
		hidden.append(tile)
	var path: Array[Vector2i] = branch.cells.slice(0, int(secret.entry))
	path.append_array(stamped.path)
	branch.cells = path
	branch.tip = stamped.reward
	branch.erase("annex")
	branch["bonus_coffer"] = stamped.path.size() >= 11 \
		and posmod(hash([rng.seed, route.id, secret.id, &"bonus coffer"]), 100) < 25
	secret.hidden_tiles = hidden
	secret["challenge_id"] = route.id
	secret["challenge_name"] = route.display_name
	secret["challenge_variant"] = stamped.alternate
	var hazard_points: Array[Dictionary] = []
	var sockets: Dictionary = route.sockets(stamped.alternate)
	for socket_at: Vector2i in sockets:
		var socket: Socket = sockets[socket_at]
		if socket.optional and rng.randf() < 0.33:
			continue
		var tile := _transform_tile(socket_at - stamped.local_origin, stamped.first, stamped.forward, stamped.across)
		var heading: Vector2i = stamped.forward * socket.facing.x + stamped.across * socket.facing.y
		var kind := socket.kind
		if socket.alternate_kind not in ["", "none"] and rng.randf() < 0.28:
			kind = socket.alternate_kind
		var phase := clampf(float(socket.phase) * 1.40 + rng.randf_range(-0.11, 0.11), 0.0, 1.40)
		hazard_points.append({"position": dungeon.tile_position(tile), "tile": tile, "room": -1, "kind": kind,
			"secret": true, "challenge": true, "secret_id": String(secret.id), "heading": heading,
			"phase": phase, "reach": float(socket.reach), "optional": bool(socket.optional)})
	secret["challenge_hazards"] = hazard_points


static func _transform_tile(tile: Vector2i, origin: Vector2i, forward: Vector2i, across: Vector2i) -> Vector2i:
	return origin + forward * tile.x + across * tile.y


static func _walk_route(cells: Dictionary, start: Vector2i, finish: Vector2i) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [start]
	var previous := {start: start}
	var cursor := 0
	while cursor < queue.size() and not previous.has(finish):
		var at := queue[cursor]
		cursor += 1
		for step: Vector2i in STEPS:
			var next := at + step
			if cells.has(next) and not previous.has(next):
				previous[next] = at
				queue.append(next)
	var path: Array[Vector2i] = []
	if previous.has(finish):
		var at := finish
		while at != start:
			path.push_front(at)
			at = previous[at]
		path.push_front(start)
	return path
