extends RefCounted
## Records terrain inside a player-centered radius, with walls and sealed passages blocking sight.

const REVEAL_RADIUS := 3.5
const HALF_CELL := Vector2(0.5, 0.5)


static func survey(cells: Dictionary, concealed: Dictionary, position: Vector2) -> Dictionary[Vector2i, bool]:
	var visible: Dictionary[Vector2i, bool] = {}
	if not _open(cells, concealed, tile_at(position)):
		return visible
	var extent := Vector2.ONE * REVEAL_RADIUS
	var first := Vector2i((position - extent).ceil())
	var last := Vector2i((position + extent).floor())
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var tile := Vector2i(x, y)
			if position.distance_squared_to(Vector2(tile)) > REVEAL_RADIUS * REVEAL_RADIUS:
				continue
			if _open(cells, concealed, tile) and clear_ray(cells, concealed, position, Vector2(tile)):
				visible[tile] = true
	return visible


static func tile_at(position: Vector2) -> Vector2i:
	return Vector2i((position + HALF_CELL).floor())


static func clear_ray(cells: Dictionary, concealed: Dictionary, origin: Vector2, point: Vector2) -> bool:
	var tile := tile_at(origin)
	var target := tile_at(point)
	var direction := point - origin
	var step := Vector2i(direction.sign())
	var x_stride := INF if step.x == 0 else absf(1.0 / direction.x)
	var y_stride := INF if step.y == 0 else absf(1.0 / direction.y)
	var next_x := INF if step.x == 0 else (float(tile.x) + 0.5 * step.x - origin.x) / direction.x
	var next_y := INF if step.y == 0 else (float(tile.y) + 0.5 * step.y - origin.y) / direction.y
	while tile != target:
		if absf(next_x - next_y) <= 0.00001:
			# A ray touching a diagonal corner cannot see between closed wall edges.
			if not _open(cells, concealed, tile + Vector2i(step.x, 0)):
				return false
			if not _open(cells, concealed, tile + Vector2i(0, step.y)):
				return false
			tile += step
			next_x += x_stride
			next_y += y_stride
		elif next_x < next_y:
			tile.x += step.x
			next_x += x_stride
		else:
			tile.y += step.y
			next_y += y_stride
		if not _open(cells, concealed, tile):
			return false
	return true


static func _open(cells: Dictionary, concealed: Dictionary, tile: Vector2i) -> bool:
	return cells.has(tile) and not concealed.has(tile)
