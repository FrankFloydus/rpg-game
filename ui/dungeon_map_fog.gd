extends RefCounted
## Persists the stretches of each physical wall the player has seen on the current floor.

const Discovery := preload("res://ui/dungeon_map_visibility.gd")
const WALL_SAMPLES := 16
const WALL_FULL := (1 << WALL_SAMPLES) - 1
const CARDINALS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const CORNERS: Array[Vector2] = [
	Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5),
]
const EDGE_INSET := 0.002
const OBSERVATION_STEP := 0.5 / WALL_SAMPLES
const RADIUS_SQUARED := Discovery.REVEAL_RADIUS * Discovery.REVEAL_RADIUS

var coverage: Dictionary[Vector3i, int] = {}
var revision := 0
var landmarks: Array[Dictionary] = []

var _last_position := Vector2.INF
var _concealment_hash := 0
var _needs_topology_check := true
var _known_landmarks: Dictionary[String, bool] = {}


func observe(cells: Dictionary, concealed: Dictionary, position: Vector2) -> void:
	var changed := false
	var concealment_hash := concealed.hash()
	if _needs_topology_check or _concealment_hash != concealment_hash:
		changed = _forget_open_edges(cells, concealed)
		_concealment_hash = concealment_hash
		_needs_topology_check = false
		_last_position = Vector2.INF
	if (not _is_open(cells, concealed, Discovery.tile_at(position))
			or position.distance_squared_to(_last_position) < OBSERVATION_STEP * OBSERVATION_STEP):
		if changed:
			revision += 1
		return
	_last_position = position
	var extent := Vector2.ONE * (Discovery.REVEAL_RADIUS + 0.5)
	var first := Vector2i((position - extent).ceil())
	var last := Vector2i((position + extent).floor())
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var tile := Vector2i(x, y)
			if not _is_open(cells, concealed, tile):
				continue
			for side in CARDINALS.size():
				if not _is_open(cells, concealed, tile + CARDINALS[side]):
					changed = _observe_wall(cells, concealed, position, Vector3i(x, y, side)) or changed
	if changed:
		revision += 1


func snapshot() -> Array:
	var saved := []
	for key: Vector3i in coverage:
		saved.append([key.x, key.y, key.z, coverage[key]])
	return saved


func restore(saved: Variant) -> void:
	coverage.clear()
	restore_landmarks([])
	_last_position = Vector2.INF
	_needs_topology_check = true
	revision += 1
	if not saved is Array:
		return
	for row: Variant in saved:
		if not row is Array or row.size() != 4:
			continue
		if not row.all(func(value: Variant) -> bool: return value is int or value is float):
			continue
		var side := int(row[2])
		var mask := int(row[3])
		if side >= 0 and side < CARDINALS.size() and mask > 0 and mask <= WALL_FULL:
			coverage[Vector3i(int(row[0]), int(row[1]), side)] = mask


## Keeps eligible landmarks after their first unobstructed sighting on this floor.
func observe_landmarks(candidates: Array[Dictionary], cells: Dictionary, concealed: Dictionary,
		position: Vector2) -> void:
	landmarks.clear()
	var blocked := concealed.duplicate()
	for point in candidates:
		if point.kind == "route_gate":
			blocked[Discovery.tile_at(point.at)] = true
	var retained: Dictionary[String, bool] = {}
	var origin_tile := Discovery.tile_at(position)
	for point in candidates:
		var at: Vector2 = point.at
		var tile := Discovery.tile_at(at)
		if not _is_open(cells, concealed, tile):
			continue
		var id: String = point.id
		if not _known_landmarks.has(id):
			if position.distance_squared_to(at) > RADIUS_SQUARED:
				continue
			# A nearby portcullis is visible from either open corridor leading to it.
			var gate: bool = point.kind == "route_gate"
			if gate:
				blocked.erase(tile)
			var visible := _is_open(cells, blocked, origin_tile) and Discovery.clear_ray(cells, blocked, position, at)
			if gate:
				blocked[tile] = true
			if not visible:
				continue
		retained[id] = true
		landmarks.append(point)
	_known_landmarks = retained


func landmark_snapshot() -> Array[String]:
	return _known_landmarks.keys()


func restore_landmarks(saved: Variant) -> void:
	landmarks.clear()
	_known_landmarks.clear()
	if saved is Array:
		for id: Variant in saved:
			if id is String and not id.is_empty():
				_known_landmarks[id] = true


static func wall_start(wall: Vector3i) -> Vector2:
	return Vector2(wall.x, wall.y) + CORNERS[wall.z]


static func wall_direction(wall: Vector3i) -> Vector2:
	return CORNERS[(wall.z + 1) % CORNERS.size()] - CORNERS[wall.z]


func _observe_wall(cells: Dictionary, concealed: Dictionary, origin: Vector2, wall: Vector3i) -> bool:
	var previous: int = coverage.get(wall, 0)
	if previous == WALL_FULL:
		return false
	var first := wall_start(wall)
	var direction := wall_direction(wall)
	if origin.distance_squared_to(Geometry2D.get_closest_point_to_segment(origin, first, first + direction)) > RADIUS_SQUARED:
		return false
	var inset := Vector2(CARDINALS[wall.z]) * EDGE_INSET
	var mask := previous
	for sample in WALL_SAMPLES:
		var bit := 1 << sample
		if mask & bit:
			continue
		var point := first + direction * ((float(sample) + 0.5) / WALL_SAMPLES)
		if (origin.distance_squared_to(point) <= RADIUS_SQUARED
				and Discovery.clear_ray(cells, concealed, origin, point - inset)):
			mask |= bit
	if mask == previous:
		return false
	coverage[wall] = mask
	return true


func _forget_open_edges(cells: Dictionary, concealed: Dictionary) -> bool:
	var changed := false
	for key: Vector3i in coverage.keys():
		var tile := Vector2i(key.x, key.y)
		if not _is_open(cells, concealed, tile) or _is_open(cells, concealed, tile + CARDINALS[key.z]):
			coverage.erase(key)
			changed = true
	return changed


static func _is_open(cells: Dictionary, concealed: Dictionary, tile: Vector2i) -> bool:
	return cells.has(tile) and not concealed.has(tile)
