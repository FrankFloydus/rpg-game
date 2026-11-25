extends Node3D
## The arena, its navigation mesh, and spawn markers live in training_ground.tscn.

const NAVIGATION_LAYER := 1
const PILLAR_CENTERS := [-7.25, 7.25]
const PILLAR_RADIUS := 1.76

var spawn_position: Vector3:
	get:
		return $PlayerSpawn.position
var spawn_yaw: float:
	get:
		return $PlayerSpawn.rotation.y
var return_portal_position: Vector3:
	get:
		return $ReturnPortal.position
var water_volume: Node3D:
	get:
		return $SwimmingPool/Water
var enemy_spawn_points: PackedVector3Array:
	get:
		var points := PackedVector3Array()
		for spawn in $EnemySpawns.get_children():
			if spawn is Marker3D:
				points.append($EnemySpawns.transform * spawn.position)
		return points

var _nav_context := RID()
var _nav_iteration := 0
@onready var _nav: NavigationRegion3D = $TrainingNavigation


func navigation_map() -> RID:
	if not is_inside_tree() or not is_instance_valid(_nav):
		return RID()
	var map := _nav.get_navigation_map()
	if not map.is_valid():
		return RID()
	var iteration := NavigationServer3D.map_get_iteration_id(map)
	if iteration == 0:
		return RID()
	if map != _nav_context or iteration != _nav_iteration:
		if NavigationServer3D.map_get_closest_point_owner(map, to_global(spawn_position)) != _nav.get_rid():
			return RID()
		_nav_context = map
		_nav_iteration = iteration
	return map


func navigation_route(start: Vector3, target: Vector3) -> PackedVector3Array:
	var map := navigation_map()
	if not map.is_valid():
		return PackedVector3Array()
	var destination := NavigationServer3D.map_get_closest_point(map, target)
	if target.distance_to(destination) > 1.5:
		return PackedVector3Array()
	var path := NavigationServer3D.map_get_path(map, start, destination, true, NAVIGATION_LAYER)
	if path.is_empty() or path[-1].distance_to(destination) > 0.3:
		return PackedVector3Array()
	return path


func weapon_drop_point(origin: Vector3, forward: Vector3, props: Array[Node]) -> Vector3:
	var space := get_world_3d().direct_space_state
	var reach_height := Vector3.UP * 0.45
	for angle: float in [0.0, 0.42, -0.42, 0.91, -0.91, 1.57, -1.57, PI]:
		var direction := forward.rotated(Vector3.UP, angle)
		for distance: float in [1.65, 2.45, 3.25]:
			var candidate := origin + direction * distance
			var floor_ray := PhysicsRayQueryParameters3D.create(
				candidate + Vector3.UP * 0.6, candidate - Vector3.UP * 2.0, 1)
			var floor_hit := space.intersect_ray(floor_ray)
			if floor_hit.is_empty() or floor_hit.normal.y < 0.8:
				continue
			var point: Vector3 = floor_hit.position
			if water_volume.contains(point + Vector3.UP * 0.12):
				continue
			var approach := PhysicsRayQueryParameters3D.create(
				origin + reach_height, point + reach_height, 1)
			if not space.intersect_ray(approach).is_empty():
				continue
			var clear := true
			for prop: Node3D in props:
				if not prop.is_queued_for_deletion() and point.distance_squared_to(prop.global_position) < 0.64:
					clear = false
					break
			if clear:
				return point
	return Vector3.INF
