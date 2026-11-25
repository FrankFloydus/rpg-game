extends SceneTree
## Checks the chamber hazard against live player movement, life, guard and combat logging.

const Game := preload("res://main.tscn")
const LavaFloor := preload("res://world/props/lava_floor.tscn")
const CENTER := Vector3(0.0, 0.04, -1.0)
const EXTENT := Vector2(4.8, 3.8)

var _game: Node3D
var _player: CharacterBody3D
var _lava: Node3D
var _events: Array[Dictionary] = []
var _captures := ""
var _checks := 0
var _failures := 0


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			_captures = argument.trim_prefix("--capture-dir=")
	_run.call_deferred()


func _run() -> void:
	_game = Game.instantiate()
	_game.save_directory = "user://test_runs/lava_chamber_%d" % OS.get_process_id()
	_game.preferences_path = _game.save_directory.path_join("settings.cfg")
	root.add_child(_game)
	current_scene = _game
	_game._start_training_from_title()
	await _ticks(4)
	_player = _game.player
	_player.combat_event.connect(_events.append)
	_player.stats.dodge_chance = 100.0
	_player.stats.fire_resist = 0.0
	_lava = LavaFloor.instantiate()
	_lava.configure(_player, EXTENT)
	_lava.position = CENTER
	_game._training_actors.add_child(_lava)
	var warning := _lava._warning as MeshInstance3D
	var surface := _lava.get_node("Surface") as MeshInstance3D
	var start_life: float = _player.life
	_player.place_at(Vector3(0.0, 0.06, 4.4), 0.0, -0.36)
	await _ticks(14)
	await _capture("lava_dormant")
	_check(not warning.visible and surface.get_instance_shader_parameter(&"heat") == 0.0,
		"Dormant floor remains safe during the approach")
	await _until_warning(warning)
	await _ticks(73)
	await _capture("lava_warning")
	_check(warning.visible and is_equal_approx(warning.scale.x, EXTENT.x * 0.5)
		and is_equal_approx(warning.scale.z, EXTENT.y * 0.5)
		and warning.global_position.distance_to(CENTER) < 0.10 and _player.life == start_life,
		"The red warning uses the exact safe basin dimensions and deals no early damage")
	await _ticks(70)
	await _capture("lava_molten")
	_check(not warning.visible and surface.get_instance_shader_parameter(&"heat") > 0.8
		and _player.life == start_life, "The molten phase leaves the dry perimeter safe")
	_player.place_at(CENTER + Vector3.UP * 0.02)
	var guard: float = _player.stamina
	Input.action_press("block")
	await _ticks(87)
	_check(_player.life < start_life and _player.is_blocking() and _player.stamina == guard,
		"Standing in lava applies resistance-mitigated damage without spending Stamina")
	_check(_events.size() >= 2 and _events.all(_logged_fire),
		"Repeated fire ticks appear with a Lava Floor entry on the Dungeon side")
	Input.action_release("block")
	_player.place_at(CENTER + Vector3.RIGHT * (EXTENT.x * 0.5 + 0.22))
	var remaining_life: float = _player.life
	await _ticks(180)
	_check(_player.life == remaining_life and surface.get_instance_shader_parameter(&"heat") == 0.0,
		"Stepping beyond the marked perimeter stops damage and the molten floor cools")
	await _until_warning(warning, 550)
	_check(warning.visible, "The chamber rearms into a new warning after dormancy")
	_lava.set_active(false)
	await _ticks(150)
	_check(not warning.visible and surface.get_instance_shader_parameter(&"heat") == 0.0,
		"Clearing the dungeon disables the basin and immediately cools the surface")
	_game.free()
	await process_frame
	print("Lava chamber: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _logged_fire(entry: Dictionary) -> bool:
	return entry.kind == &"damage" and entry.ability_id == &"lava_floor" and entry.side == &"world" \
		and "Fire" in entry.detail and entry.amount > 0


func _until_warning(warning: MeshInstance3D, timeout := 250) -> void:
	for _frame in timeout:
		if warning.visible:
			break
		await _ticks(1)


func _ticks(count: int) -> void:
	for _frame in count:
		await physics_frame


func _capture(name_tag: String) -> void:
	if not _captures.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		if root.use_hdr_2d:
			frame.convert(Image.FORMAT_RGB8)
			frame.linear_to_srgb()
		_check(frame.save_png(_captures.path_join(name_tag + ".png")) == OK, "Captured %s" % name_tag)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
