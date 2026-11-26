extends Node3D
## Keeps a group of summoned fighters on the player's side of the encounter.

const Skeleton := preload("res://combat/cards/allied_skeleton.tscn")
const PARTY_OFFSETS: Array[Vector3] = [Vector3(-1.12, 0.0, 0.72), Vector3(1.12, 0.0, 0.72), Vector3(0.0, 0.0, -1.52)]
const WORLD_LAYER := 1
const NAVIGATION_LAYER := 1
const SCAN_RADIUS := 10.0
const FORMATION_LEASH := 16.0
const SCAN_INTERVAL := 0.19

var _player: CharacterBody3D
var _arena: Node3D
var _members: Array[CharacterBody3D] = []
var _lifetime := 22.0
var _next_scan := 0.0
var _left_world := false


func raise_party(player: CharacterBody3D, arena: Node3D, lifetime: float) -> void:
	_player = player
	_arena = arena
	_lifetime = maxf(1.0, lifetime)
	var occupied := PackedVector3Array()
	for index in PARTY_OFFSETS.size():
		var offset := PARTY_OFFSETS[index]
		var actor := Skeleton.instantiate() as CharacterBody3D
		add_child(actor)
		actor.global_position = _spawn_seat(offset, occupied)
		actor.rotation.y = _player.global_rotation.y
		actor.bind_player(_player, self, index, offset)
		_members.append(actor)
		occupied.append(actor.global_position)


func is_active_for(player: CharacterBody3D) -> bool:
	return _player == player and _lifetime > 0.0 and not is_queued_for_deletion()


func dismiss() -> void:
	for actor in _members:
		if is_instance_valid(actor):
			actor.remove_from_group("friendly_skeletons")
	hide()
	process_mode = Node.PROCESS_MODE_DISABLED
	queue_free()


func _physics_process(delta: float) -> void:
	if _left_world or not is_instance_valid(_player) or not _player.combat_enabled:
		queue_free()
		return
	if not _player.gameplay_enabled:
		return
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
		return
	_next_scan -= delta
	if _next_scan <= 0.0:
		_next_scan = SCAN_INTERVAL
		_assign_targets()


func _exit_tree() -> void:
	# Leaving the active world or resetting the arena ends any remaining temporary allies.
	_left_world = true


func _assign_targets() -> void:
	var candidates: Array[CharacterBody3D] = []
	var player_position := _player.global_position
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as CharacterBody3D
		if enemy == null or not _arena.is_ancestor_of(enemy) or enemy.is_queued_for_deletion() or enemy.health <= 0.0:
			continue
		if absf(enemy.global_position.y - player_position.y) < 1.28 \
				and enemy.global_position.distance_squared_to(player_position) < SCAN_RADIUS * SCAN_RADIUS:
			candidates.append(enemy)
	var assignments := {}
	for actor: CharacterBody3D in _members:
		if not is_instance_valid(actor):
			continue
		if actor.global_position.distance_squared_to(player_position) > FORMATION_LEASH * FORMATION_LEASH:
			var occupied := PackedVector3Array()
			for other in _members:
				if is_instance_valid(other) and other != actor:
					occupied.append(other.global_position)
			actor.global_position = _spawn_seat(actor.formation_offset, occupied)
			actor.reset_physics_interpolation()
		var best: CharacterBody3D
		var best_score := INF
		for enemy in candidates:
			var distance := actor.global_position.distance_to(enemy.global_position)
			if distance > SCAN_RADIUS + 2.0:
				continue
			var has_sight := actor._sees_target(enemy) as bool
			var score := distance + float(assignments.get(enemy, 0)) * 2.05
			score += 0.0 if has_sight else 3.8
			if enemy == actor.target:
				score -= 1.10
			if score < best_score:
				best_score = score
				best = enemy
		actor.target = best
		if best != null:
			assignments[best] = int(assignments.get(best, 0)) + 1


func _spawn_seat(offset: Vector3, occupied: PackedVector3Array) -> Vector3:
	var origin := _player.global_position
	var travel := _player.global_basis * offset
	var space := get_world_3d().direct_space_state
	var radius := CapsuleShape3D.new()
	radius.radius = 0.23
	radius.height = 1.48
	var overlap := PhysicsShapeQueryParameters3D.new()
	overlap.shape = radius
	overlap.collision_mask = WORLD_LAYER
	for distance_factor: float in [1.0, 0.74, 0.51]:
		for angle in [0.0, 0.56, -0.56, 1.15, -1.15, PI]:
			var desired: Vector3 = origin + travel.rotated(Vector3.UP, angle) * distance_factor
			var probe := PhysicsRayQueryParameters3D.create(desired + Vector3.UP * 0.52, desired - Vector3.UP * 0.82, WORLD_LAYER)
			var hit := space.intersect_ray(probe)
			if hit.is_empty() or (hit.normal as Vector3).y < 0.68:
				continue
			var point: Vector3 = hit.position
			if absf(point.y - origin.y) > 0.72 or _occupied_seat(point, occupied):
				continue
			overlap.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.80)
			if not space.intersect_shape(overlap, 1).is_empty():
				continue
			var ray := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.68, point + Vector3.UP * 0.68, WORLD_LAYER)
			if space.intersect_ray(ray).is_empty():
				return point + Vector3.UP * 0.022
	# The owner's collision body already proves this point is clear in a tight stairwell.
	return origin + Vector3.UP * 0.022


static func _occupied_seat(point: Vector3, occupied: PackedVector3Array) -> bool:
	for present in occupied:
		if present.distance_squared_to(point) < 0.68 * 0.68:
			return true
	return false


func navigation_route(start: Vector3, target: Vector3) -> PackedVector3Array:
	var nav := get_world_3d().navigation_map
	if not nav.is_valid() or NavigationServer3D.map_get_iteration_id(nav) == 0:
		return PackedVector3Array()
	var destination := NavigationServer3D.map_get_closest_point(nav, target)
	if target.distance_squared_to(destination) > 2.56:
		return PackedVector3Array()
	var path := NavigationServer3D.map_get_path(nav, start, destination, true, NAVIGATION_LAYER)
	if path.is_empty() or path[-1].distance_squared_to(destination) > 0.16:
		return PackedVector3Array()
	return path


func separation_for(actor: CharacterBody3D) -> Vector3:
	var separation := Vector3.ZERO
	for other in _members:
		if not is_instance_valid(other) or other == actor:
			continue
		var push := actor.global_position - other.global_position
		push.y = 0.0
		var distance := push.length()
		if distance < 0.86 and distance > 0.01:
			separation += push.normalized() * ((0.86 - distance) * 3.0)
	return separation


func reserve_strike(actor: CharacterBody3D, enemy: CharacterBody3D) -> bool:
	var committed := 0
	for other in _members:
		if is_instance_valid(other) and other != actor and other.holds_strike(enemy):
			committed += 1
	return committed < 2
