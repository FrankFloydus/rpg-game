extends RefCounted
## Finds a supported loot position clear of coffer footprints and nearby drops.

const WORLD_LAYER := 1
const FLOOR_OFFSET := 0.018
const ITEM_RADIUS := 0.52
const COFFER_HALF_WIDTH := 0.53
const COFFER_HALF_DEPTH := 0.36
const DROPS_APART := 0.48
const ANGULAR_STEP := 2.39996323
const RADII := [0.48, 0.76, 1.05, 1.40, 1.80, 2.25, 2.90, 3.70, 4.60]
const DIRECTIONS := [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]


## Uses world coordinates. A null space validates saved points against authored floor geometry.
static func find(dungeon: Node3D, space: PhysicsDirectSpaceState3D, base: Vector3, index: int,
		facing := Vector3.ZERO, nearby: Array = []) -> Vector3:
	if not base.is_finite():
		return Vector3.INF
	var coffers: Array[Transform3D] = []
	for entry: Dictionary in dungeon.chests:
		coffers.append(dungeon.coffer_pose(int(entry.id)).affine_inverse())
	var unobstructed := _fits(dungeon, base, coffers)
	if index == 0 and unobstructed and _away_from_loot(base, nearby):
		var floor_position := _floor_position(space, base)
		if floor_position.is_finite():
			return floor_position
	var angle := 1.78 + float(index) * ANGULAR_STEP
	var flat := Vector2(facing.x, facing.z)
	if not flat.is_zero_approx():
		angle = flat.angle() + float(ceili(index * 0.5)) * (0.74 if index % 2 == 0 else -0.74)
	var best_crowded := Vector3.INF
	for radius: float in RADII:
		for slot in range(8):
			var turn := float(ceili(slot * 0.5)) * (PI / 4.0) * (1.0 if slot % 2 == 0 else -1.0)
			var candidate := base + Vector3(cos(angle + turn), 0.0, sin(angle + turn)) * radius
			if not _fits(dungeon, candidate, coffers):
				continue
			if space != null:
				var height := Vector3.UP * 0.32
				var travel := PhysicsRayQueryParameters3D.create(base + height, candidate + height, WORLD_LAYER)
				if not space.intersect_ray(travel).is_empty():
					continue
			var floor_position := _floor_position(space, candidate)
			if not floor_position.is_finite():
				continue
			if _away_from_loot(floor_position, nearby):
				return floor_position
			if not best_crowded.is_finite():
				best_crowded = floor_position
	return best_crowded


static func _fits(dungeon: Node3D, point: Vector3, coffers: Array[Transform3D]) -> bool:
	var local := dungeon.to_local(point) if dungeon.is_inside_tree() else dungeon.transform.affine_inverse() * point
	var ground_point := point if dungeon.is_inside_tree() else local
	if not dungeon.ground_is_open(ground_point):
		return false
	for direction: Vector3 in DIRECTIONS:
		if not dungeon.ground_is_open(ground_point + direction * ITEM_RADIUS):
			return false
	for inverse: Transform3D in coffers:
		var from_coffer := inverse * local
		if absf(from_coffer.x) < COFFER_HALF_WIDTH + ITEM_RADIUS \
				and absf(from_coffer.z) < COFFER_HALF_DEPTH + ITEM_RADIUS:
			return false
	return true


static func _floor_position(space: PhysicsDirectSpaceState3D, point: Vector3) -> Vector3:
	if space == null:
		return point
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.28,
		point - Vector3.UP * 0.65, WORLD_LAYER)
	var floor_hit := space.intersect_ray(query)
	if floor_hit.is_empty() or (floor_hit.normal as Vector3).y < 0.65:
		return Vector3.INF
	var floor_point: Vector3 = floor_hit.position
	if absf(floor_point.y - point.y) > 0.38:
		return Vector3.INF
	return floor_point + Vector3.UP * FLOOR_OFFSET


static func _away_from_loot(point: Vector3, nearby: Array) -> bool:
	for prop: Node3D in nearby:
		if is_instance_valid(prop) and not prop.is_queued_for_deletion() \
				and prop.global_position.distance_squared_to(point) < DROPS_APART * DROPS_APART:
			return false
	return true
