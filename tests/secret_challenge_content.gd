extends SceneTree
## Covers authored route connectivity and actual movement through the floor fixture.

const Catalog := preload("res://world/secret_challenges/secret_challenge_catalog.gd")
const Route := preload("res://world/secret_challenges/secret_challenge_route.gd")
const Hazard := preload("res://world/hazards/spike_plate.tscn")
const Ember := preload("res://world/hazards/ember_vent.tscn")
const Miasma := preload("res://world/hazards/miasma_vent.tscn")
const Telegraph := preload("res://combat/effects/enemy_telegraph.gd")
const DIRECTIONS := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
const CENTRE := Vector3(0.0, 0.05, -0.6)

var _checks := 0
var _failures := 0
var _game: Node
var _player: CharacterBody3D
var _capture_root := ""


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			_capture_root = argument.trim_prefix("--capture-dir=")
	_run.call_deferred()


func _run() -> void:
	_check_catalogue()
	var scene := load("res://main.tscn") as PackedScene
	_game = scene.instantiate()
	_game.save_enabled = false
	root.add_child(_game)
	_game.title_screen.training_requested.emit()
	await _ticks(3)
	_player = _game.player
	await _check_native_fixture(Hazard, "spike_plate", Vector2i.RIGHT)
	await _check_native_fixture(Ember, "ember_vent", Vector2i.DOWN)
	await _check_native_fixture(Miasma, "miasma_vent", Vector2i.LEFT)
	await _check_cover()
	_game.free()
	await process_frame
	print("secret_challenge_content: %d/%d checks passed" % [_checks - _failures, _checks])
	quit(1 if _failures > 0 else 0)


func _check_catalogue() -> void:
	var ids := {}
	var primary_paths := {}
	var depths := {}
	var minimum := 99999
	var maximum := 0
	var alternates := 0
	for route: Route in Catalog.ROUTES:
		ids[route.id] = true
		depths[route.min_depth] = true
		primary_paths["/".join(route.rows)] = true
		var path := _check_route(route, false)
		minimum = mini(minimum, path)
		maximum = maxi(maximum, path)
		if not route.alternate_rows.is_empty():
			var alternate := _check_route(route, true)
			_check(alternate != path and route.ingress() == route.ingress(true),
				"An alternate %s changes travel length and uses the same hidden opening" % route.display_name)
			minimum = mini(minimum, alternate)
			maximum = maxi(maximum, alternate)
			alternates += 1
	_check(ids.size() >= 20 and ids.size() == primary_paths.size() and depths.size() >= 3,
		"At least twenty unique authored routes are gated across multiple depths")
	_check(minimum <= 8 and maximum >= 25 and alternates >= 4,
		"Secret challenges have different lengths as well as authored within-route alternatives")


func _check_route(route: Route, alternate: bool) -> int:
	var floor := {}
	for cell in route.floor_cells(alternate):
		floor[cell] = true
	var start := route.ingress(alternate)
	var reward := route.reward(alternate)
	var reachable := _distances(floor, start)
	var connected: bool = reachable.has(reward) and reachable.size() == floor.size()
	var clean := start.x == 0 and _degree(floor, reward) == 1
	for cell: Vector2i in floor:
		clean = clean and (cell.x != 0 or cell == start)
	var sockets := route.sockets(alternate)
	var has_mandatory := false
	var aligned := true
	for cell: Vector2i in sockets:
		var socket = sockets[cell]
		var planar: Vector2i = socket.facing
		aligned = (aligned and _degree(floor, cell) == 2 and floor.has(cell + planar)
			and floor.has(cell - planar) and planar.length_squared() == 1)
		if not socket.optional and not _distances(floor, start, cell).has(reward):
			has_mandatory = true
	_check(connected and clean and aligned and has_mandatory,
		"%s has a traversable closed corridor, readable oriented traps, and a reward behind a required trap" % route.display_name)
	return int(reachable.get(reward, 0))


func _degree(floor: Dictionary, cell: Vector2i) -> int:
	var links := 0
	for step: Vector2i in DIRECTIONS:
		links += int(floor.has(cell + step))
	return links


func _distances(floor: Dictionary, start: Vector2i, blocked := Vector2i(-1, -1)) -> Dictionary:
	var queue: Array[Vector2i] = [start]
	var reached := {start: 0}
	var cursor := 0
	while cursor < queue.size():
		var cell := queue[cursor]
		for step: Vector2i in DIRECTIONS:
			var candidate := cell + step
			if candidate != blocked and floor.has(candidate) and not reached.has(candidate):
				reached[candidate] = int(reached[cell]) + 1
				queue.append(candidate)
		cursor += 1
	return reached


func _check_native_fixture(scene: PackedScene, kind: String, axis: Vector2i) -> void:
	var hazard := scene.instantiate() as Node3D
	hazard.position = CENTRE
	hazard.configure(kind, 1, _player, 0.0, {"challenge": true, "heading": axis, "reach": 1.35})
	hazard.set_active(false)
	_game._training_actors.add_child(hazard)
	_player.restore_full()
	_player.stats.merge({"dodge_chance": 0.0, "armor": 0.0}, true)
	var along := Vector3(axis.x, 0.0, axis.y)
	var across := along.cross(Vector3.UP)
	var intended := CENTRE + across * 1.45
	_player.place_at(intended, atan2(-along.x, -along.z))
	var life: float = _player.life
	await _ticks(85)
	_check(not hazard._warning.visible and _player.life == life, "%s stays dormant before the passage opens" % kind)
	hazard.set_active(true)
	await _ticks(78)
	var wide: bool = hazard._warning.visible and hazard._warning.scale.x >= 1.60
	var aligned: bool = hazard._footprint_direction().is_equal_approx(along)
	_check(wide and aligned and hazard._effects.size() == 2
		and Telegraph.contains(hazard._footprint, hazard._footprint_origin(), along, intended),
		"%s aligns two authored fixtures and its warning across the full walkable floor" % kind)
	if not _capture_root.is_empty():
		await _ticks(24)
	await _capture(kind + "_warning", along)
	for frame in 105:
		if hazard._contact_tested:
			break
		await _ticks(1)
	_check(_player.life < life, "%s damages a player near the side of its firing strip" % kind)
	if not _capture_root.is_empty():
		await _ticks(8)
	await _capture(kind + "_contact", along)
	hazard.set_active(false)
	_player.restore_full()
	_player.stats.dodge_chance = 0.0
	_player.place_at(CENTRE, atan2(-along.x, -along.z))
	life = _player.life
	hazard.set_active(true)
	await _ticks(80)
	Input.action_press("forward")
	await _ticks(26)
	Input.action_release("forward")
	await _ticks(83)
	var depth: float = along.dot(_player.global_position - CENTRE)
	_check(depth > 0.72 and _player.life >= life,
		"%s can be escaped on foot from the centre after its warning starts" % kind)
	hazard.queue_free()
	await _ticks(3)


func _check_cover() -> void:
	var hazard := Hazard.instantiate() as Node3D
	hazard.configure("spike_plate", 1, _player, 0.0, {"challenge": true, "heading": Vector2i.DOWN, "reach": 1.08})
	hazard.position = CENTRE
	_game._training_actors.add_child(hazard)
	var barrier := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = Vector3(3.0, 1.7, 0.25)
	collider.shape = cube
	barrier.add_child(collider)
	barrier.position = CENTRE + Vector3(0.0, 0.85, 1.28)
	_game._training_actors.add_child(barrier)
	_player.place_at(CENTRE + Vector3(0.0, 0.05, 2.4))
	await _ticks(168)
	_check(not hazard._warning.visible, "An occluding wall keeps a challenge fixture quiet at short range")
	barrier.queue_free()
	await _ticks(12)
	_check(hazard._warning.visible, "A player in open view activates the same fixture once the obstruction is removed")
	hazard.queue_free()


func _capture(label: String, direction: Vector3) -> void:
	if _capture_root.is_empty() or DisplayServer.get_name() == "headless":
		return
	var previous := _player.global_position
	var yaw := _player.rotation.y
	var pitch: float = _player.view_pitch()
	_player.place_at(CENTRE + Vector3.UP * 0.02 - direction * 2.45,
		atan2(-direction.x, -direction.z), -0.51)
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(_capture_root.path_join(label + ".png"))
	_player.place_at(previous, yaw, pitch)


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS " + description)
	else:
		_failures += 1
		printerr("FAIL " + description)
