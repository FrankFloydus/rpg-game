extends SceneTree

const Game := preload("res://main.tscn")
const Discovery := preload("res://ui/dungeon_map_visibility.gd")
const Fog := preload("res://ui/dungeon_map_fog.gd")

var _game: Node3D
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var hall := {Vector2i(0, 0): 0, Vector2i(1, 0): 0, Vector2i(2, 0): 0, Vector2i(2, 1): 0}
	var sealed := {Vector2i(1, 0): true}
	var visible := Discovery.survey(hall, sealed, Vector2.ZERO)
	_check(visible.size() == 1, "A sealed tile hides itself and the connected space beyond")
	visible = Discovery.survey(hall, {}, Vector2.ZERO)
	_check(visible.has(Vector2i(2, 0)) and not visible.has(Vector2i(2, 1)),
		"Discovery follows a straight corridor and respects an inside corner")
	var narrow := {Vector2i.ZERO: 0, Vector2i.ONE: 0}
	_check(Discovery.survey(narrow, {}, Vector2.ZERO).size() == 1,
		"Diagonal contact cannot reveal across closed walls")
	_check(Discovery.survey(hall, {}, Vector2(1.56, 0.0)).has(Vector2i(2, 1)),
		"Looking past the bend reveals the adjacent leg at a fractional player position")
	_check_wall_fog()
	_check_landmarks()

	_game = Game.instantiate()
	_game.save_enabled = false
	root.add_child(_game)
	await process_frame
	_game._create_character(0, "Map Tester")
	await _ticks(6)
	_game.unlocked = 3
	_game._rng.seed = 95545
	_game._select_depth(3)
	await _ticks(16)
	var previous_mouse_mode := Input.mouse_mode
	await _tap_map()
	var map: Control = _game.hud.get_node("WorldContent/Map")
	_check(map.visible and not _game._modal and _game.player.gameplay_enabled
		and _game._actors.process_mode == Node.PROCESS_MODE_INHERIT
		and Input.mouse_mode == previous_mouse_mode, "Tab keeps live gameplay and mouse capture")
	var projection: Dictionary = map._map_projection()
	_check(is_equal_approx(projection.drawn.get_center().x, map.size.x * 0.5)
		and is_equal_approx(projection.drawn.get_center().y, map.size.y * 0.575)
		and projection.spacing <= 14.0, "The actual explored bounds are compact, horizontally centered and lowered")
	_check(not _game.hud.get_node("WorldContent/Notice").visible, "The objective notice stays clear of the map")
	var start: Vector2 = map._player_at
	_key(KEY_W, true)
	await _ticks(24)
	_key(KEY_W, false)
	await process_frame
	_check(map._player_at.distance_to(start) > 0.20, "The reveal follows movement continuously in map units")

	var secret := _secret_passage()
	var memory: Dictionary = _game._explored.duplicate()
	if _check(is_instance_valid(secret), "The seeded expedition has a concealed passage"):
		var hidden: Dictionary = _game._concealed_tiles.duplicate()
		var outward := secret.global_basis.z.normalized()
		var destination := secret.global_position + outward * 1.1 + Vector3.UP * 0.08
		_game.player.place_at(destination, atan2(outward.x, outward.z), 0.0)
		for tile: Vector2i in hidden:
			_game._explored[tile] = true
		_game._update_map()
		var filtered := true
		for tile: Vector2i in hidden:
			filtered = filtered and not _game._explored.has(tile)
		for wall: Vector3i in _game._map_fog.coverage:
			filtered = filtered and not hidden.has(Vector2i(wall.x, wall.y))
		_check(filtered, "A closed secret stays hidden even if a saved map contains stale tiles")
		_game._open_secret_passage(secret)
		var newly_known := false
		for wall: Vector3i in _game._map_fog.coverage:
			newly_known = newly_known or hidden.has(Vector2i(wall.x, wall.y))
		_check(newly_known, "Opening the wall reveals actual contours inside the secret")
		_check(memory.keys().all(func(tile: Vector2i) -> bool: return _game._explored.has(tile)),
			"Previously explored terrain remains when the reveal moves away")

	var first_floor_fog: Dictionary = _game._map_fog.coverage.duplicate()
	var first_floor_revision: int = map._fog_revision
	_place_on_floor(1)
	await _ticks(3)
	_check(map._floor == _game.dungeon and _game._dungeon_floor_index() == 1
		and map._caption.ends_with("2/2") and map._fog_revision > first_floor_revision
		and _game._map_fog.coverage != first_floor_fog,
		"Changing floor switches the reveal, contour and caption to the new floor")
	_place_on_floor(0)
	await _ticks(3)
	_check(map._floor == _game.dungeon and map._caption.ends_with("1/2")
		and first_floor_fog.keys().all(func(wall: Vector3i) -> bool:
			return (_game._map_fog.coverage.get(wall, 0) & first_floor_fog[wall]) == first_floor_fog[wall]),
		"Returning upstairs restores all partial wall coverage of the first floor")
	await _tap_map()
	_check(not map.visible and not _game._modal and _game.player.gameplay_enabled, "Closing Tab leaves gameplay live")
	_check(_game.hud.get_node("WorldContent/Notice").visible, "Closing the map restores the notice display")
	_game.free()
	await process_frame
	print("Map reveal: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _place_on_floor(index: int) -> void:
	var geometry: Node3D = _game._dungeon_floors[index].geometry
	_game.player.place_at(geometry.to_global(geometry.spawn_position), geometry.global_rotation.y + geometry.spawn_yaw)
	_game._track_dungeon_floor()


func _check_wall_fog() -> void:
	var fog := Fog.new()
	var straight := {}
	for x in 7:
		straight[Vector2i(x, 0)] = -1
	var corridor_wall := Vector3i(3, 0, 0)
	fog.observe(straight, {}, Vector2(-0.34, 0.0))
	var first: int = fog.coverage.get(corridor_wall, 0)
	fog.observe(straight, {}, Vector2(0.28, 0.0))
	var second: int = fog.coverage.get(corridor_wall, 0)
	_check(first > 0 and second > first and (second & first) == first,
		"A wall starts partially revealed and grows while the player stays inside one tile")

	var room := {}
	for y in range(-2, 3):
		for x in 9:
			room[Vector2i(x, y)] = 0
	fog.restore([])
	var far_wall := Vector3i(8, 0, 1)
	fog.observe(room, {}, Vector2.ZERO)
	_check(not fog.coverage.has(far_wall) and not fog.coverage.has(Vector3i(3, 0, 1)),
		"An open room has neither a far wall through fog nor a synthetic frontier")
	fog.observe(room, {}, Vector2(5.2, 0.0))
	_check(fog.coverage.has(far_wall), "Approaching the far side reveals the actual room wall")
	var visited: Dictionary = fog.coverage.duplicate()
	fog.observe(room, {}, Vector2.ZERO)
	_check(visited.keys().all(func(wall: Vector3i) -> bool: return fog.coverage[wall] == visited[wall]),
		"Moving away leaves visited wall coverage intact")
	var from_checkpoint := Fog.new()
	from_checkpoint.restore(fog.snapshot())
	_check(from_checkpoint.coverage == fog.coverage, "Fractional wall coverage survives serialization")

	var turn := {}
	for x in 5:
		turn[Vector2i(x, 0)] = -1
	for y in range(1, 6):
		turn[Vector2i(4, y)] = -1
	fog.restore([])
	var hidden_wall := Vector3i(4, 2, 3)
	var passage_panel := Vector3i(4, 0, 2)
	var sealed := {Vector2i(4, 1): true}
	fog.observe(turn, {}, Vector2(1.25, 0.0))
	_check(not fog.coverage.has(hidden_wall), "An opaque corner occludes the adjoining corridor")
	fog.observe(turn, sealed, Vector2(3.72, 0.10))
	_check(fog.coverage.has(passage_panel) and not fog.coverage.has(hidden_wall),
		"A sealed passage shows its face and hides the nearby corridor")
	fog.observe(turn, {}, Vector2(3.72, 0.10))
	_check(not fog.coverage.has(passage_panel) and fog.coverage.has(hidden_wall),
		"Opening a passage removes its obsolete outline and reveals the line of sight around the turn")


func _secret_passage() -> Node3D:
	for prop in _game._props.get_children():
		if prop.payload.get("kind") == "secret_passage":
			return prop
	return null


func _check_landmarks() -> void:
	var cells := {}
	for x in range(-6, 7):
		cells[Vector2i(x, 0)] = 0
	var fog := Fog.new()
	var coffers: Array[Dictionary] = [
		{"id": "near", "kind": "locked_coffer", "at": Vector2(1.2, 0.0)},
		{"id": "far", "kind": "trial_coffer", "at": Vector2(3.1, 0.0)},
		{"id": "altar", "kind": "blood_altar", "at": Vector2(-2.3, 0.0)},
	]
	var marks := coffers.duplicate()
	marks.append({"id": "portcullis", "kind": "route_gate", "at": Vector2(2.0, 0.0)})
	fog.observe_landmarks(marks, cells, {Vector2i(-2, 0): true}, Vector2.ZERO)
	_check(fog.landmark_snapshot() == ["near", "portcullis"],
		"Only the observed coffer and gate are shown through closed terrain")
	var saved := fog.landmark_snapshot()
	fog.restore([])
	fog.restore_landmarks(saved)
	fog.observe_landmarks(marks, cells, {Vector2i(-2, 0): true}, Vector2(-6.0, 0.0))
	_check(fog.landmark_snapshot() == saved, "Landmarks stay discovered after moving away and restoring the floor")
	fog.observe_landmarks(coffers, cells, {}, Vector2(1.0, 0.0))
	_check(fog.landmark_snapshot() == ["near", "far", "altar"],
		"Opening the route and revealing the altar discovers the landmarks behind them")
	coffers.pop_front()
	fog.observe_landmarks(coffers, cells, {}, Vector2.ZERO)
	_check(fog.landmark_snapshot() == ["far", "altar"], "Used coffer and gate icons do not linger")


func _tap_map() -> void:
	_key(KEY_TAB, true)
	await _ticks(3)
	_key(KEY_TAB, false)
	await _ticks(2)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame


func _check(ok: bool, description: String) -> bool:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(description)
	else:
		print("PASS  ", description)
	return ok
