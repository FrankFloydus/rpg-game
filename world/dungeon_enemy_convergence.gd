extends RefCounted
## Placement for active enemies drawn toward the player's current dungeon floor.

const Dungeon := preload("res://world/dungeon.gd")
const Enemy := preload("res://combat/enemies/enemy.gd")
const RANGE := 9.0
const PLAYER_CLEARANCE := 3.0
const ENEMY_CLEARANCE := 1.55
const FLOOR_OFFSET := 0.035
const FOOTING_MASK := Enemy.WORLD_LAYER | Enemy.PLAYER_LAYER | Enemy.ENEMY_LAYER
const CELL_OFFSETS := [Vector3.ZERO, Vector3(0.84, 0, 0), Vector3(-0.84, 0, 0),
	Vector3(0, 0, 0.84), Vector3(0, 0, -0.84)]


static func player_has_footing(dungeon: Dungeon, player: CharacterBody3D) -> bool:
	return player.is_on_floor() and absf(dungeon.to_local(player.global_position).y) < 0.30 \
		and dungeon.map_cells.has(dungeon.tile_at(player.global_position))


static func can_stay(dungeon: Dungeon, player: CharacterBody3D, enemy: Enemy) -> bool:
	return dungeon.floor_contains(enemy.global_position) \
		and player.global_position.distance_squared_to(enemy.global_position) <= RANGE * RANGE \
		and _has_sight(player.get_world_3d().direct_space_state, player.global_position, enemy.global_position)


static func candidate_points(dungeon: Dungeon, player: CharacterBody3D,
		concealed: Dictionary, reserved: Array[Vector3]) -> Array[Vector3]:
	var space := player.get_world_3d().direct_space_state
	var player_point := player.global_position
	var origin_tile := dungeon.tile_at(player_point)
	var current_room := int(dungeon.map_cells.get(origin_tile, -1))
	var forward := -player.global_basis.z
	var scored: Array[Dictionary] = []
	var reach := ceili(RANGE / Dungeon.CELL_SIZE)
	for x in range(-reach, reach + 1):
		for z in range(-reach, reach + 1):
			var tile := origin_tile + Vector2i(x, z)
			if not dungeon.map_cells.has(tile) or concealed.has(tile) or dungeon.stair_approach_tiles.has(tile):
				continue
			if not dungeon.challenge_chamber.is_empty() and tile == dungeon.challenge_chamber.tile:
				continue
			var same_room := int(dungeon.map_cells[tile]) == current_room
			var center := dungeon.tile_position(tile)
			for offset: Vector3 in CELL_OFFSETS:
				var local := center + offset
				if _near_lava(dungeon, local):
					continue
				var point := dungeon.to_global(local)
				var distance := point.distance_to(player_point)
				if distance < PLAYER_CLEARANCE or distance > RANGE or not dungeon.ground_is_open(point):
					continue
				if not _clear_of(point, reserved, ENEMY_CLEARANCE) or not _has_sight(space, player_point, point):
					continue
				var foot := _ground_point(space, point)
				if not foot.is_finite():
					continue
				var approach := forward.dot((point - player_point).normalized())
				var penalty := 0.0 if same_room else 10.0
				penalty += absf(distance - 4.8) + (1.0 - approach) * 1.75
				scored.append({"point": foot, "penalty": penalty})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.penalty < b.penalty)
	var points: Array[Vector3] = []
	for choice: Dictionary in scored:
		points.append(choice.point)
	return points


static func take_site(enemy: Enemy, points: Array[Vector3], placed: Array[Vector3]) -> Vector3:
	var collision := enemy.get_node("BodyCollision") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = FOOTING_MASK
	query.shape = collision.shape
	query.exclude = [enemy.get_rid()]
	var shape_transform := enemy.global_transform * collision.transform
	var offset := shape_transform.origin - enemy.global_position
	var space := enemy.get_world_3d().direct_space_state
	for point: Vector3 in points:
		if not _clear_of(point, placed, ENEMY_CLEARANCE):
			continue
		shape_transform.origin = point + offset
		query.transform = shape_transform
		if space.intersect_shape(query, 1).is_empty():
			placed.append(point)
			return point
	return Vector3.INF


static func _clear_of(point: Vector3, occupied: Array[Vector3], clearance: float) -> bool:
	for other: Vector3 in occupied:
		if other.distance_squared_to(point) < clearance * clearance:
			return false
	return true


static func _has_sight(space: PhysicsDirectSpaceState3D, start: Vector3, goal: Vector3) -> bool:
	var lift := Vector3.UP * 0.90
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(start + lift, goal + lift, Enemy.WORLD_LAYER)).is_empty()


static func _near_lava(dungeon: Dungeon, local: Vector3) -> bool:
	if dungeon.lava_floor.is_empty():
		return false
	var center: Vector3 = dungeon.lava_floor.position
	var extent: Vector2 = dungeon.lava_floor.extent
	return absf(local.x - center.x) < extent.x * 0.5 + 0.65 \
		and absf(local.z - center.z) < extent.y * 0.5 + 0.65


static func _ground_point(space: PhysicsDirectSpaceState3D, point: Vector3) -> Vector3:
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.19,
		point - Vector3.UP * 0.21, Enemy.WORLD_LAYER)
	var hit := space.intersect_ray(ray)
	if hit.is_empty() or (hit.normal as Vector3).y < 0.75:
		return Vector3.INF
	return (hit.position as Vector3) + Vector3.UP * FLOOR_OFFSET
