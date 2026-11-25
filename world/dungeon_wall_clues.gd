extends RefCounted
## Finds a still-concealed wall by the route to its exposed face.

const Dungeon := preload("res://world/dungeon.gd")
const SecretPassage := preload("res://world/props/secret_passage.gd")
const Rules := preload("res://data/legendary_exploration_rules.tres")
const WORLD_LAYER := 1
const WALKING_RAY_HEIGHT := Vector3.UP * 0.83


static func nearest(dungeon: Dungeon, props: Node3D, at: Vector3, prior_clues: Dictionary) -> SecretPassage:
	if not dungeon.floor_contains(at):
		return null
	var nearest_wall: SecretPassage
	var best := Rules.mason_range * Rules.mason_range
	var space := dungeon.get_world_3d().direct_space_state
	for child: Node in props.get_children():
		var wall := child as SecretPassage
		if wall == null or not wall.pick_available() or prior_clues.has(wall.payload.id):
			continue
		var distance := at.distance_squared_to(wall.global_position)
		if distance <= best and wall.to_local(at).z > 0.08 and _has_approach(dungeon, space, at, wall.clue_approach()):
			nearest_wall = wall
			best = distance
	return nearest_wall


static func _has_approach(dungeon: Dungeon, space: PhysicsDirectSpaceState3D, start: Vector3, end: Vector3) -> bool:
	if not dungeon.ground_is_open(end):
		return false
	var route := dungeon.route(start, end)
	if route.is_empty():
		return false
	var previous := start
	for point: Vector3 in route:
		if point.distance_squared_to(previous) > 0.0025:
			var ray := PhysicsRayQueryParameters3D.create(previous + WALKING_RAY_HEIGHT, point + WALKING_RAY_HEIGHT, WORLD_LAYER)
			if not space.intersect_ray(ray).is_empty():
				return false
		previous = point
	return true
