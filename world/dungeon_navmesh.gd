extends RefCounted
## Builds a shared-edge navigation surface from the same cells as the dungeon shell.

const NAVIGATION_LAYER := 1
const EDGE_CLEARANCE := 0.82
const FIXTURE_CLEARANCE := 0.65
const FIXTURE_MARGIN := 1.47
const SUBDIVISIONS := 5
const CORNERS: Array[Vector2i] = [Vector2i.ZERO, Vector2i.DOWN, Vector2i.ONE, Vector2i.RIGHT]


static func build(
	dungeon: Node3D, tiles: Dictionary, cover: Dictionary, cell_size: float,
	blockers: Array[CollisionShape3D]
) -> NavigationRegion3D:
	var open_tiles := tiles.duplicate()
	for tile: Vector2i in cover:
		open_tiles.erase(tile)
	var obstructions := _index_obstructions(dungeon, blockers, cell_size)
	var half := cell_size * 0.5
	var cuts := PackedFloat32Array([0.0, EDGE_CLEARANCE, FIXTURE_MARGIN,
		cell_size - FIXTURE_MARGIN, cell_size - EDGE_CLEARANCE, cell_size])
	var vertex_ids := {}
	var points := PackedVector3Array()
	var polygons: Array[PackedInt32Array] = []
	for tile: Vector2i in open_tiles:
		var left := Vector2(tile) * cell_size - Vector2(half, half)
		var fixtures: Array = obstructions.get(tile, [])
		for row in range(SUBDIVISIONS):
			for column in range(SUBDIVISIONS):
				var toward_wall := Vector2i(_outer_edge(column), _outer_edge(row))
				if _hits_wall(open_tiles, tile, toward_wall):
					continue
				var patch := Rect2(left + Vector2(cuts[column], cuts[row]),
					Vector2(cuts[column + 1] - cuts[column], cuts[row + 1] - cuts[row]))
				if _hits_fixture(patch, fixtures):
					continue
				var key := tile * SUBDIVISIONS + Vector2i(column, row)
				var polygon := PackedInt32Array()
				for corner in CORNERS:
					var vertex := key + corner
					if not vertex_ids.has(vertex):
						vertex_ids[vertex] = points.size()
						points.append(Vector3(
							_axis(vertex.x, cell_size, cuts), 0.0, _axis(vertex.y, cell_size, cuts)))
					polygon.append(int(vertex_ids[vertex]))
				polygons.append(polygon)

	var mesh := NavigationMesh.new()
	mesh.vertices = points
	for polygon in polygons:
		mesh.add_polygon(polygon)
	var region := NavigationRegion3D.new()
	region.name = "DungeonNavigation"
	region.navigation_layers = NAVIGATION_LAYER
	region.use_edge_connections = false
	region.navigation_mesh = mesh
	return region


static func _axis(index: int, cell_size: float, cuts: PackedFloat32Array) -> float:
	var tile := floori(float(index) / float(SUBDIVISIONS))
	return (float(tile) - 0.5) * cell_size + cuts[posmod(index, SUBDIVISIONS)]


static func _outer_edge(subcell: int) -> int:
	if subcell == 0:
		return -1
	return 1 if subcell == SUBDIVISIONS - 1 else 0


static func _hits_wall(open_tiles: Dictionary, tile: Vector2i, toward: Vector2i) -> bool:
	if toward.x != 0 and not open_tiles.has(tile + Vector2i(toward.x, 0)):
		return true
	if toward.y != 0 and not open_tiles.has(tile + Vector2i(0, toward.y)):
		return true
	return toward.x != 0 and toward.y != 0 and not open_tiles.has(tile + toward)


static func _hits_fixture(patch: Rect2, fixtures: Array) -> bool:
	for footprint: Rect2 in fixtures:
		if footprint.intersects(patch):
			return true
	return false


static func _index_obstructions(
	dungeon: Node3D, blockers: Array[CollisionShape3D], cell_size: float
) -> Dictionary:
	var by_tile := {}
	for blocker in blockers:
		if blocker.disabled or not (blocker.shape is BoxShape3D):
			continue
		var bounds := _footprint(dungeon, blocker).grow(FIXTURE_CLEARANCE)
		var first := Vector2i((bounds.position / cell_size + Vector2(0.5, 0.5)).floor())
		var last := Vector2i((bounds.end / cell_size + Vector2(0.5, 0.5)).floor())
		for z in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var tile := Vector2i(x, z)
				if not by_tile.has(tile):
					by_tile[tile] = []
				by_tile[tile].append(bounds)
	return by_tile


static func _footprint(dungeon: Node3D, blocker: CollisionShape3D) -> Rect2:
	var pose := Transform3D.IDENTITY
	var node: Node3D = blocker
	while node != dungeon:
		pose = node.transform * pose
		node = node.get_parent_node_3d()
	var size: Vector3 = blocker.shape.size
	var bounds := AABB(-size * 0.5, size)
	bounds = pose * bounds
	return Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z))

