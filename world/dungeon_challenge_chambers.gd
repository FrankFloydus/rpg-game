extends RefCounted
## Geometry and placement for optional rooms with a special route to their reward.

const PLATFORM := "platform"
const LAVA := "lava"
const SUBMERGED := "submerged"
const BATH_DEPTH := 2.28
const WATER_SURFACE := -0.16
const CAP_HEIGHT := 0.07
const STEPS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

const DungeonTilesets := preload("res://world/dungeon_tilesets.gd")


static func choose(dungeon: Node3D, kind: String, seed_value: int) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for room: Dictionary in dungeon.rooms:
		if room.id < 2 or room.role == &"vault" or room.doors.is_empty():
			continue
		var contains_stair := false
		for tile: Vector2i in dungeon.stair_approach_tiles:
			contains_stair = contains_stair or (tile in room.tiles)
		var fill := _central_square_fill(room, dungeon.map_cells)
		if contains_stair or not fill.valid:
			continue
		var center_tile: Vector2i = room.center
		var door: Vector2i = room.doors[0]
		var step := Vector2i.RIGHT
		for outward: Vector2i in STEPS:
			if int(dungeon.map_cells.get(door + outward, -2)) == -1:
				step = -outward
				break
		var inward := Vector3(step.x, 0.0, step.y)
		var point: Vector3 = dungeon.tile_position(center_tile)
		var yaw := atan2(-inward.x, -inward.z)
		var score := float(posmod(hash([seed_value, room.id, kind]), 2000)) / 1000.0
		score += 1.6 if room.doors.size() == 1 else 0.0
		if room.role == &"quiet":
			score += 2.0
		candidates.append({"kind": kind, "room": room.id, "tile": center_tile, "position": point,
			"direction": inward, "yaw": yaw, "score": score, "fill": fill.tiles})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return first.score > second.score)
	var result: Dictionary = candidates[0]
	var room: Dictionary = dungeon.rooms[result.room]
	for tile: Vector2i in result.fill:
		dungeon.map_cells[tile] = result.room
		room.tiles.append(tile)
	var center: Vector3 = result.position
	var forward: Vector3 = result.direction
	var across := Vector3(forward.z, 0.0, -forward.x)
	match kind:
		PLATFORM:
			result["platforms"] = _platforms(center, forward, across)
			result["reward"] = result.platforms[-1].top + forward * 0.40
		LAVA:
			result["lava_extent"] = Vector2.ONE * 4.70
			result["reward"] = center + forward * 3.59
		SUBMERGED:
			result["bath_rect"] = Rect2(Vector2(center.x, center.z) - Vector2.ONE * dungeon.CELL_SIZE * 0.5,
				Vector2.ONE * dungeon.CELL_SIZE)
			result["reward"] = center + across * 0.60 + forward * 0.62 - Vector3.UP * BATH_DEPTH
	return result


static func _central_square_fill(room: Dictionary, cells: Dictionary) -> Dictionary:
	var center: Vector2i = room.center
	var bounds: Rect2i = room.bounds
	var missing: Array[Vector2i] = []
	for x in range(-1, 2):
		for z in range(-1, 2):
			var tile := center + Vector2i(x, z)
			if int(cells.get(tile, -2)) == int(room.id):
				continue
			if not bounds.has_point(tile) or cells.has(tile):
				return {"valid": false}
			for offset: Vector2i in STEPS:
				if cells.has(tile + offset) and int(cells[tile + offset]) != int(room.id):
					return {"valid": false}
			missing.append(tile)
	return {"valid": true, "tiles": missing}


static func _platforms(center: Vector3, forward: Vector3, across: Vector3) -> Array[Dictionary]:
	return [
		{"top": center - forward * 2.85 - across * 0.58 + Vector3.UP * 0.45, "size": Vector2(1.58, 1.34)},
		{"top": center - forward * 1.12 - across * 0.23 + Vector3.UP * 0.91, "size": Vector2(1.48, 1.48)},
		{"top": center + forward * 0.69 + across * 0.27 + Vector3.UP * 1.39, "size": Vector2(1.56, 1.56)},
		{"top": center + forward * 2.76 + across * 0.10 + Vector3.UP * 1.88, "size": Vector2(2.74, 2.34)},
	]


static func room_floor_geometry(dungeon: Node3D, chamber: Dictionary) -> void:
	if chamber.is_empty():
		return
	var center: Vector3 = chamber.position
	var forward: Vector3 = chamber.direction
	var across := Vector3(forward.z, 0.0, -forward.x)
	for side: int in [-1, 1]:
		var pedestal := center + across * (side * 3.46) - forward * 2.65
		dungeon._brazier(dungeon.tile_at(pedestal), pedestal, chamber.kind == SUBMERGED)
	if chamber.kind == LAVA:
		return
	var room := Node3D.new()
	room.name = "RaisedCryptPlatforms" if chamber.kind == PLATFORM else "SunkenStoneBasin"
	dungeon.add_child(room)
	var stone := StandardMaterial3D.new()
	var cap := StandardMaterial3D.new()
	DungeonTilesets.apply_masonry(stone, dungeon.tileset_id, &"wall")
	DungeonTilesets.apply_masonry(cap, dungeon.tileset_id, &"floor")
	if chamber.kind == PLATFORM:
		var basis := Basis(Vector3.UP, chamber.yaw)
		for index: int in chamber.platforms.size():
			_build_platform(room, chamber.platforms[index], basis, stone, cap, index)
	else:
		_build_basin(room, chamber, stone, cap)


static func _build_platform(parent: Node3D, data: Dictionary, basis: Basis,
		stone: Material, cap: Material, index: int) -> void:
	var top: Vector3 = data.top
	var footprint: Vector2 = data.size
	var shaft := Vector3(footprint.x * 0.89, top.y - CAP_HEIGHT, footprint.y * 0.86)
	_solid(parent, "Plinth%d" % index, top - Vector3.UP * ((top.y + CAP_HEIGHT) * 0.5), shaft, basis, stone)
	_solid(parent, "StoneTread%d" % index, top - Vector3.UP * (CAP_HEIGHT * 0.5),
		Vector3(footprint.x, CAP_HEIGHT, footprint.y), basis, cap)


static func _build_basin(parent: Node3D, chamber: Dictionary, stone: Material, cap: Material) -> void:
	var center: Vector3 = chamber.position
	var size: Vector2 = chamber.bath_rect.size
	var forward: Vector3 = chamber.direction
	var across := Vector3(forward.z, 0.0, -forward.x)
	_solid(parent, "BasinFloor", center - Vector3.UP * (BATH_DEPTH + 0.10),
		Vector3(size.x, 0.20, size.y), Basis.IDENTITY, cap)
	for edge: Vector3 in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]:
		var tangent := Vector3(edge.z, 0.0, -edge.x)
		var wall_basis := Basis(tangent, Vector3.UP, edge)
		var lip := center + edge * (size.x * 0.5 + 0.048)
		var near_ramp := edge == -forward
		var rim_opening := 0.28 if near_ramp else 0.0
		var wall_center := lip - Vector3.UP * (BATH_DEPTH + rim_opening) * 0.5
		_solid(parent, "BasinWall", wall_center,
			Vector3(size.x + 0.12, BATH_DEPTH - rim_opening, 0.10), wall_basis, stone)
		if near_ramp:
			# Leave a shallow cut in the upper rim for walking out of the water on the ramp.
			var upper := lip + across * 0.64 - Vector3.UP * rim_opening * 0.5
			_solid(parent, "BasinRampLip", upper, Vector3(2.12, rim_opening, 0.10), wall_basis, stone)
	var start := center - forward * (size.x * 0.5 - 0.48) - across * 1.06
	var end := center + forward * (size.x * 0.5 - 0.10) - across * 1.06 - Vector3.UP * BATH_DEPTH
	var descent := (end - start).normalized()
	var basis := Basis(across, descent.cross(across), descent)
	_solid(parent, "BasinApproachRamp", (start + end) * 0.5 - basis.y * 0.065,
		Vector3(1.00, 0.13, end.distance_to(start)), basis, cap)
	_solid(parent, "BasinRampLanding", start - forward * 0.255 - Vector3.UP * 0.063,
		Vector3(1.00, 0.125, 0.52), Basis(across, Vector3.UP, forward), cap)


static func _solid(parent: Node3D, label: String, center: Vector3, size: Vector3, basis: Basis, material: Material) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.transform = Transform3D(basis, center)
	body.collision_layer = 1
	body.collision_mask = 0
	parent.add_child(body)
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
