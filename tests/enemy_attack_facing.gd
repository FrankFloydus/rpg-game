extends SceneTree
## Verifies that rotating a dungeon floor does not rotate actors away from their attacks.

const Catalog := preload("res://combat/enemies/enemy_catalog.gd")
const Enemy := preload("res://combat/enemies/enemy.gd")
const Projectile := preload("res://combat/effects/enemy_projectile.gd")
const TICK := 1.0 / 60.0
const BODY_YAWS := [0.0, 47.0, 90.0, 178.0, -177.0, -90.0]
const FLOOR_YAWS := [0.0, 90.0, 180.0, -90.0]

class Target extends Node3D:
	var hits := 0

	func receive_enemy_hit(_amount: float, _type: String, _status: String,
			_source: Node3D, _ability: Dictionary) -> bool:
		hits += 1
		return true

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_catalogue_headings()
	await physics_frame
	for floor_yaw: float in FLOOR_YAWS:
		await _check_cast(0, "graveknife_cut", "arc", 1.20, floor_yaw, 47.0)
		await _check_cast(6, "sentinel_sweep", "arc", 1.85, floor_yaw, -177.0)
		await _check_cast(2, "ember_pounce", "lane", 2.80, floor_yaw, 178.0)
		await _check_cast(1, "ossuary_shot", "ray", 4.50, floor_yaw, -90.0)
	print("enemy_attack_facing: %d/%d groups passed" % [_checks - _failures, _checks])
	quit(1 if _failures else 0)


func _floor(degrees: float) -> Node3D:
	var floor := Node3D.new()
	floor.rotation.y = deg_to_rad(degrees)
	floor.position = Vector3(4.5, 3.1, -8.2)
	root.add_child(floor)
	return floor


func _check_catalogue_headings() -> void:
	var worst := 0.0
	var sample_count := 0
	var floor := _floor(0.0)
	for id in Catalog.ARCHETYPES.size():
		var enemy := Catalog.instantiate(id) as Enemy
		floor.add_child(enemy)
		enemy.set_physics_process(false)
		for floor_yaw: float in FLOOR_YAWS:
			floor.rotation.y = deg_to_rad(floor_yaw)
			for yaw: float in BODY_YAWS:
				var direction := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(yaw))
				enemy._turn(direction, 1.0)
				var model_forward := -enemy._model.global_basis.z.normalized()
				worst = maxf(worst, rad_to_deg(model_forward.angle_to(direction)))
				sample_count += 1
		enemy.free()
	floor.free()
	_check(worst < 0.01, "%d poses, all %d models at six bearings and four floor yaws. Max error %.2f°" %
		[sample_count, Catalog.ARCHETYPES.size(), worst])


func _check_cast(id: int, move: String, shape: String, distance: float, floor_yaw: float,
		target_yaw: float) -> void:
	var floor := _floor(floor_yaw)
	var target := Target.new()
	root.add_child(target)
	var random := RandomNumberGenerator.new()
	random.seed = 1234
	var enemy := Catalog.instantiate(id) as Enemy
	enemy.setup(target, 8, "normal", random)
	enemy.position = Vector3(-1.4, 0.05, 3.2)
	floor.add_child(enemy)
	enemy.set_physics_process(false)
	var direction := Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(target_yaw))
	target.global_position = enemy.global_position + direction * distance
	enemy.global_rotation.y = deg_to_rad(target_yaw + 20.0)
	enemy._target = target
	enemy._move_id = move
	enemy._profile = enemy._attack_profiles[move]
	var traces: Array[Dictionary] = []
	enemy.set_ability_trace(func(trace: Dictionary) -> void: traces.append(trace))
	await physics_frame
	enemy._begin_attack(direction)
	for tick in ceili(enemy._windup_total / TICK) + 1:
		var fraction := enemy._advance_windup(TICK, target.global_position - enemy.global_position)
		enemy._model.animate(TICK, 0.0, fraction, -1.0)
		if enemy._attack_remaining == 0.0:
			break
	var released := enemy._release_attack()
	enemy._model.animate(TICK, 0.0, 0.0, 0.42)
	var forward := -enemy._model.global_basis.z.normalized()
	var launch_heading := Vector3.ZERO
	var contact := false
	if shape == "ray":
		for child in floor.get_children():
			if child is Projectile and child.in_flight():
				var shot_heading: Vector3 = child._direction
				launch_heading = Vector3(shot_heading.x, 0.0, shot_heading.z).normalized()
				contact = true
				break
	elif shape == "lane":
		for tick in 60:
			if enemy._advance_dash(TICK):
				break
	else:
		for tick in 30:
			if not traces.is_empty() or enemy._trace_markers == null:
				break
			enemy._strike_time += TICK
			enemy._advance_area_trace()
	if not traces.is_empty():
		launch_heading = traces[0].direction
		contact = traces[0].hit and target.hits == 1
	var error := rad_to_deg(forward.angle_to(direction))
	_check(released and contact and launch_heading.dot(direction) > 0.999
			and forward.dot(direction) > 0.997,
		"%s at floor %+.0f°, target %+.0f°. Pose error %.2f°, contact %s" %
		[enemy.display_name, floor_yaw, target_yaw, error, contact])
	target.free()
	floor.free()


func _check(condition: bool, detail: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
	print("%s %s" % ["PASS" if condition else "FAIL", detail])
