extends RefCounted
## Finds floor points and keeps authored ground attacks inside solid geometry.

const Telegraph := preload("res://combat/effects/enemy_telegraph.gd")
const WORLD_COLLISION := 1


static func floor_point(caster: Node3D, point: Vector3, drop := 3.0) -> Vector3:
	var ray := PhysicsRayQueryParameters3D.create(
		point + Vector3.UP * 0.75, point - Vector3.UP * drop, WORLD_COLLISION)
	var hit := caster.get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.position if not hit.is_empty() and hit.normal.y >= 0.55 else Vector3.INF


static func open_length(caster: Node3D, origin: Vector3, direction: Vector3, reach: float,
		half_width: float, sample_height := 0.42) -> float:
	var space := caster.get_world_3d().direct_space_state
	var lateral := direction.cross(Vector3.UP) * half_width
	var length := reach
	for offset: Vector3 in [-lateral, Vector3.ZERO, lateral]:
		var start := origin + offset + Vector3.UP * sample_height
		var ray := PhysicsRayQueryParameters3D.create(start, start + direction * reach, WORLD_COLLISION)
		ray.hit_from_inside = true
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			length = minf(length, maxf(0.0, start.distance_to(hit.position) - 0.07))
	return length


static func target_in_footprint(caster: Node3D, target: Node3D, profile: Dictionary,
		origin: Vector3, direction := Vector3.FORWARD) -> bool:
	if not is_instance_valid(target):
		return false
	if not Telegraph.contains(profile, origin, direction, target.global_position):
		return false
	var target_floor := floor_point(caster, target.global_position)
	return target_floor.is_finite() and absf(target_floor.y - origin.y) <= 0.44 \
		and target.global_position.y - origin.y < 0.92
