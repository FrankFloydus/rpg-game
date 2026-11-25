extends RefCounted
## Keeps portable clutter and floor candles at wall edges, away from circulation.

const CRATE := preload("res://world/modules/breakable_crate.tscn")
const POTTERY := preload("res://world/modules/breakable_pottery.tscn")
const URN := preload("res://world/modules/breakable_urn.tscn")
const VOTIVES := preload("res://world/modules/floor_votive_cluster.tscn")
const CARDINALS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const STORAGE_THEMES := [&"armory", &"archive", &"forge", &"gaol"]
const POTTERY_GROUP_CUMULATIVE := [0.39, 0.65, 0.82, 0.92, 0.962, 0.988, 1.0]
const EXTRA_POTTERY_FLOOR_BUDGET := 30
const POTTERY_SPACING := 0.485


static func place_chamber(parent: Node3D, dungeon: Node3D, room: Dictionary,
		used_tiles: Array[Vector2i], blocked: Dictionary, seed_value: int, varied := false, clustered := false) -> void:
	if room.role == &"arrival":
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, room.id, "dressing"])
	var edges: Array[Vector4i] = []
	for tile: Vector2i in room.tiles:
		if tile in used_tiles or tile in room.cover or blocked.has(tile):
			continue
		var near_door := false
		for door: Vector2i in room.doors:
			if tile.distance_squared_to(door) < 2:
				near_door = true
				break
		if near_door:
			continue
		for side in CARDINALS:
			if not dungeon.map_cells.has(tile + side):
				edges.append(Vector4i(tile.x, tile.y, side.x, side.y))
	if edges.is_empty():
		return
	if clustered:
		_populate_wall_bays(parent, dungeon, room, used_tiles, edges, rng)
		return
	if room.role in [&"quiet", &"vault"] or rng.randf() < 0.68:
		_place_edge(parent, dungeon, VOTIVES, "Votives_%d" % room.id, edges, used_tiles, rng, 0.31)
	if edges.is_empty() or rng.randf() < 0.14:
		return
	var name := "Breakable_%d" % room.id
	if room.theme in STORAGE_THEMES:
		_place_edge(parent, dungeon, CRATE, name, edges, used_tiles, rng, 0.39)
		if not edges.is_empty() and _remaining_extra_pottery(parent) > 0 and rng.randf() < 0.29:
			_place_pottery_group(parent, dungeon, name + "_Pottery", edges, used_tiles, rng, true)
	else:
		_place_pottery_group(parent, dungeon, name, edges, used_tiles, rng, false)
	if not varied or edges.is_empty() or room.tiles.size() < 14 or rng.randf() > 0.72:
		return
	# Reserve a separate wall bay for a second group in larger chambers.
	if room.theme in STORAGE_THEMES and _remaining_extra_pottery(parent) > 0:
		_place_pottery_group(parent, dungeon, name + "_Stores", edges, used_tiles, rng, true)
	else:
		var extra := CRATE if rng.randf() < 0.42 else URN
		_place_edge(parent, dungeon, extra, name + "_Stores", edges, used_tiles, rng, 0.39)


static func _populate_wall_bays(parent: Node3D, dungeon: Node3D, room: Dictionary,
		used: Array[Vector2i], edges: Array[Vector4i], rng: RandomNumberGenerator) -> void:
	var name := "Breakable_%d" % room.id
	var storage: bool = room.theme in STORAGE_THEMES
	if room.role in [&"quiet", &"vault"] or rng.randf() < 0.76:
		_place_edge(parent, dungeon, VOTIVES, "Votives_%d" % room.id, edges, used, rng, 0.33)
	if edges.is_empty():
		return
	if storage:
		_place_edge(parent, dungeon, CRATE, name, edges, used, rng, 0.41)
	else:
		_place_cluster(parent, dungeon, name, edges, used, rng)
	if not edges.is_empty() and (storage or rng.randf() < 0.80):
		_place_cluster(parent, dungeon, name + "_Bay", edges, used, rng)
	if not edges.is_empty() and room.tiles.size() >= 15 and rng.randf() < 0.71:
		var extra := CRATE if storage and rng.randf() < 0.68 else VOTIVES
		_place_edge(parent, dungeon, extra, name + "_Stores", edges, used, rng, 0.39)


static func _place_cluster(parent: Node3D, dungeon: Node3D, node_name: String,
		edges: Array[Vector4i], used: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	var edge := edges[rng.randi_range(0, edges.size() - 1)]
	var corners: Array[Vector4i] = []
	for candidate: Vector4i in edges:
		var candidate_across := Vector2i(-candidate.w, candidate.z)
		var candidate_tile := Vector2i(candidate.x, candidate.y)
		if not dungeon.map_cells.has(candidate_tile + candidate_across) \
				or not dungeon.map_cells.has(candidate_tile - candidate_across):
			corners.append(candidate)
	if not corners.is_empty() and rng.randf() < 0.76:
		edge = corners[rng.randi_range(0, corners.size() - 1)]
	var tile := Vector2i(edge.x, edge.y)
	var across := Vector2i(-edge.w, edge.z)
	var corner_bias := 0.0
	if not dungeon.map_cells.has(tile + across):
		corner_bias = 0.73
	elif not dungeon.map_cells.has(tile - across):
		corner_bias = -0.73
	var anchor := Vector2(corner_bias + rng.randf_range(-0.17, 0.17), rng.randf_range(0.36, 0.52))
	var positions: Array[Vector2] = [anchor]
	var roll := rng.randf()
	var desired := 1
	while roll > POTTERY_GROUP_CUMULATIVE[desired - 1]:
		desired += 1
	var budget := maxi(1, 47 - int(parent.get_meta(&"extra_pottery", 0)))
	desired = mini(desired, budget)
	for _attempt in 80:
		if positions.size() >= desired:
			break
		var position := Vector2(anchor.x + rng.randf_range(-1.23, 1.23), rng.randf_range(0.34, 1.10))
		if absf(position.x) > 1.37 or positions.any(func(at: Vector2) -> bool: return at.distance_squared_to(position) < 0.50 * 0.50):
			continue
		positions.append(position)
	for index in positions.size():
		var point := positions[index]
		var piece := _place(parent, dungeon, _pottery_scene(rng), "%s_%d" % [node_name, index], edge, point.y, point.x)
		piece.rotation.y += rng.randf_range(-0.44, 0.44)
		piece.scale = Vector3.ONE * rng.randf_range(0.77, 0.98)
	parent.set_meta(&"extra_pottery", int(parent.get_meta(&"extra_pottery", 0)) + positions.size())
	_reserve_edge(edge, edges, used)


static func place_passages(parent: Node3D, dungeon: Node3D) -> void:
	for index in dungeon.side_passages.size():
		var passage: Dictionary = dungeon.side_passages[index]
		if passage.get("merchant", false) or passage.get("bonus_coffer", false) or (not passage.treasure and index % 2 == 0):
			continue
		var tile: Vector2i = passage.tip
		var previous: Vector2i = passage.cells[-2]
		var heading := tile - previous
		var side := Vector2i(-heading.y, heading.x)
		if index % 2 == 0:
			side = -side
		var along := Vector2i(-side.y, side.x)
		var lateral := 0.82 * float(along.x * heading.x + along.y * heading.y)
		_place(parent, dungeon, VOTIVES, "PassageVotives_%d" % index,
			Vector4i(tile.x, tile.y, side.x, side.y), 0.33, lateral)


static func place_secret_approach_pottery(parent: Node3D, dungeon: Node3D, occupied: Dictionary, seed_value: int) -> void:
	for secret: Dictionary in dungeon.secret_passages:
		var selection := posmod(hash([seed_value, secret.id, "passage pottery"]), 100)
		if selection >= 76:
			continue
		var path: Array[Vector2i] = dungeon.side_passages[secret.branch].cells
		var tile := path[int(secret.entry) - 1]
		if occupied.has(tile):
			continue
		var direction := path[int(secret.entry)] - tile
		var side := Vector2i(-direction.y, direction.x)
		if selection % 2 == 0:
			side = -side
		var scene := URN if selection % 3 == 0 else POTTERY
		for edge: Vector2i in [side, -side]:
			if not dungeon.map_cells.has(tile + edge):
				_place(parent, dungeon, scene, "PassagePottery_%s" % secret.id,
					Vector4i(tile.x, tile.y, edge.x, edge.y), 0.43, -0.27)
				occupied[tile] = true
				break


static func place_gallery_niches(parent: Node3D, dungeon: Node3D, blocked: Dictionary, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, "gallery niches"])
	var edges: Array[Vector4i] = []
	for tile: Vector2i in dungeon.map_cells:
		if dungeon.map_cells[tile] != -1 or blocked.has(tile) or tile.distance_squared_to(Vector2i.ZERO) < 64:
			continue
		var galleries := 0
		var beside_room := false
		for side in CARDINALS:
			var neighbor := int(dungeon.map_cells.get(tile + side, -2))
			galleries += int(neighbor == -1)
			beside_room = beside_room or neighbor >= 0
		if beside_room or galleries != 3:
			continue
		for side in CARDINALS:
			if not dungeon.map_cells.has(tile + side):
				edges.append(Vector4i(tile.x, tile.y, side.x, side.y))
	var used: Array[Vector2i] = []
	for index in mini(edges.size(), 2 + floori(float(dungeon.rooms.size()) / 4.0)):
		var scene := URN if rng.randf() < 0.54 else VOTIVES
		_place_edge(parent, dungeon, scene, "GalleryNiche_%d" % index, edges, used, rng, 0.33)


static func _place_edge(parent: Node3D, dungeon: Node3D, scene: PackedScene, node_name: String,
		edges: Array[Vector4i], used_tiles: Array[Vector2i], rng: RandomNumberGenerator,
		setback: float) -> void:
	var edge: Vector4i = edges[rng.randi_range(0, edges.size() - 1)]
	_place(parent, dungeon, scene, node_name, edge, setback, rng.randf_range(-0.65, 0.65))
	_reserve_edge(edge, edges, used_tiles)


static func _place_pottery_group(parent: Node3D, dungeon: Node3D, node_name: String,
		edges: Array[Vector4i], used_tiles: Array[Vector2i], rng: RandomNumberGenerator,
		extra_group: bool) -> void:
	# Preserve the original primary pot and its ID when regenerating an existing expedition.
	var vessel := _pottery_scene(rng)
	var edge: Vector4i = edges[rng.randi_range(0, edges.size() - 1)]
	var anchor := rng.randf_range(-0.65, 0.65)
	_place(parent, dungeon, vessel, node_name, edge, 0.39, anchor)
	_reserve_edge(edge, edges, used_tiles)
	var roll := rng.randf()
	var extra := 0
	while roll > POTTERY_GROUP_CUMULATIVE[extra]:
		extra += 1
	var budget := _remaining_extra_pottery(parent)
	var added := int(extra_group)
	var left_first := -1.0 if rng.randf() < 0.5 else 1.0
	# The most crowded groups use smaller vessels without moving the saved primary pot.
	var crowded := extra == POTTERY_GROUP_CUMULATIVE.size() - 1
	var first_gap := 0.44 if crowded else POTTERY_SPACING
	var next_gap := 0.413 if crowded else POTTERY_SPACING
	var lateral_limit: float = dungeon.CELL_SIZE * 0.5 - (0.22 if crowded else 0.25)
	var slots: Array[float] = []
	for step in range(1, POTTERY_GROUP_CUMULATIVE.size()):
		for side: float in [left_first, -left_first]:
			var lateral := anchor + side * (first_gap + float(step - 1) * next_gap) + rng.randf_range(-0.011, 0.011)
			if absf(lateral) <= lateral_limit:
				slots.append(lateral)
	var count := mini(extra, mini(slots.size(), budget - added))
	for index in count:
		var pot := _place(parent, dungeon, _pottery_scene(rng), "%s_%d" % [node_name, index + 1],
			edge, rng.randf_range(0.33, 0.445), slots[index])
		pot.rotation.y += rng.randf_range(-0.23, 0.23)
		pot.scale = Vector3.ONE * (rng.randf_range(0.79, 0.88) if crowded else rng.randf_range(0.86, 1.02))
	parent.set_meta(&"extra_pottery", EXTRA_POTTERY_FLOOR_BUDGET - budget + added + count)


static func _pottery_scene(rng: RandomNumberGenerator) -> PackedScene:
	return URN if rng.randf() < 0.45 else POTTERY


static func _remaining_extra_pottery(parent: Node3D) -> int:
	return EXTRA_POTTERY_FLOOR_BUDGET - int(parent.get_meta(&"extra_pottery", 0))


static func _reserve_edge(edge: Vector4i, edges: Array[Vector4i], used_tiles: Array[Vector2i]) -> void:
	used_tiles.append(Vector2i(edge.x, edge.y))
	for index in range(edges.size() - 1, -1, -1):
		if edges[index].x == edge.x and edges[index].y == edge.y:
			edges.remove_at(index)


static func _place(parent: Node3D, dungeon: Node3D, scene: PackedScene, node_name: String,
		edge: Vector4i, setback: float, lateral: float) -> Node3D:
	var prop := scene.instantiate() as Node3D
	prop.name = node_name
	var outward := Vector3(edge.z, 0.0, edge.w)
	var along := Vector3(-edge.w, 0.0, edge.z)
	var origin: Vector3 = dungeon.tile_position(Vector2i(edge.x, edge.y))
	prop.position = origin + outward * (dungeon.CELL_SIZE * 0.5 - setback) + along * lateral
	prop.rotation.y = atan2(-outward.x, -outward.z)
	parent.add_child(prop)
	return prop
