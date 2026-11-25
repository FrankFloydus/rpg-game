extends SceneTree
## Keeps ordinary threats relevant against continuous movement while preserving a response to aimed attacks.

const Game := preload("res://main.tscn")
const Catalog := preload("res://combat/enemies/enemy_catalog.gd")
const AbilityDefinition := preload("res://combat/abilities/ability_definition.gd")
const Slam := preload("res://combat/abilities/sepulchre_slam.tres")
const GRAVEKNIFE_CUT := &"graveknife_cut"

var _game: Node3D
var _player: CharacterBody3D
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_game = Game.instantiate()
	_game.save_enabled = false
	root.add_child(_game)
	_game.title_screen.training_requested.emit()
	await _ticks(5)
	_player = _game.player
	_player.stats.merge({"max_health": 1000.0, "dodge_chance": 0.0, "life_regen": 0.0, "armor": 0.0}, true)
	await _check_open_floor_pursuit()
	await _check_guarding_strafe(false)
	await _check_guarding_strafe(true)
	await _check_aimed_projectile(false)
	await _check_aimed_projectile(true)
	await _check_committed_slam()
	_game.free()
	await _ticks(2)
	print("Hearth Below enemy movement pressure: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_open_floor_pursuit() -> void:
	var enemy := _spawn(6, Vector3(0, 0.08, -4), Vector3(0, 0.08, -2.1))
	var enemy_start := enemy.global_position
	var player_start := _player.global_position
	Input.action_press("back")
	var started := await _wait_for(&"cast_start", &"sentinel_sweep", 55)
	var landed := await _wait_for(&"damage", &"sentinel_sweep", 85)
	Input.action_release("back")
	var enemy_travel := _flat(enemy.global_position - enemy_start).length()
	var player_travel := _flat(_player.global_position - player_start).length()
	_check(started and landed and player_travel > 0.5,
		"The Crypt Guard's normal swing threatens a backpedaling player (guard %.2f m, player %.2f m)" % [
			enemy_travel, player_travel])


func _check_guarding_strafe(face_thrall: bool) -> void:
	var start := Vector3(0.0 if face_thrall else -5.0, 0.08, 2.0)
	var thrall := _spawn(0, start + Vector3.FORWARD * 2.8, start)
	var initial_life: float = _player.life
	var initial_stamina: float = _player.stamina
	var prior_position := _player.global_position
	var traveled := 0.0
	var needed_blocks := 2 if face_thrall else 1
	var blocks := 0
	_hold_right_mouse(true)
	Input.action_press("right")
	for frame in 240:
		if face_thrall:
			var toward := thrall.global_position - _player.global_position
			_player.rotation.y = atan2(-toward.x, -toward.z)
		await _ticks(1)
		var position := _player.global_position
		traveled += _flat(position - prior_position).length()
		prior_position = position
		blocks = _graveknife_blocks()
		if blocks >= needed_blocks:
			break
	var guarded: bool = _player.is_blocking()
	Input.action_release("right")
	_hold_right_mouse(false)
	var movement := "circling the Thrall" if face_thrall else "walking sideways"
	_check(guarded and traveled > 1.0 and blocks >= needed_blocks
		and _saw(&"cast_start", GRAVEKNIFE_CUT) and _saw(&"cast_end", GRAVEKNIFE_CUT)
		and _player.stamina < initial_stamina and is_equal_approx(_player.life, initial_life),
		"RMB guard blocks Graveknife Cut while %s (%d blocks, %.2f m traveled)" % [movement, blocks, traveled])


func _graveknife_blocks() -> int:
	var count := 0
	for event: Dictionary in _game._combat_events:
		if event.get("kind") == &"status" and event.get("ability_id") == GRAVEKNIFE_CUT \
				and str(event.get("detail", "")).begins_with("Blocked"):
			count += 1
	return count


func _hold_right_mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check_aimed_projectile(reverse_on_launch: bool) -> void:
	var enemy := _spawn(1, Vector3(0, 0.08, -3), Vector3(-3, 0.08, 4))
	var player_start := _player.global_position
	Input.action_press("right")
	var released := await _wait_for(&"cast_end", &"ossuary_shot", 85)
	var release_point := _player.global_position
	enemy.set_physics_process(false)
	if reverse_on_launch:
		Input.action_release("right")
		Input.action_press("left")
	var landed := await _wait_for(&"damage", &"ossuary_shot", 56)
	Input.action_release("right")
	Input.action_release("left")
	var player_travel := _flat(release_point - player_start).length()
	player_travel += _flat(_player.global_position - release_point).length()
	_check(released and landed != reverse_on_launch and player_travel > 0.5,
		"The Ossuary Archer hits steady strafing (player %.2f m)" % player_travel if not reverse_on_launch else
		"An Ossuary Shot can be evaded by reversing direction after release (player %.2f m)" % player_travel)


func _check_committed_slam() -> void:
	var enemy := _spawn(16, Vector3(0, 0.08, 0), Vector3(0, 0.08, 2.84), 5, Slam)
	var warned := await _wait_for(&"cast_start", &"sepulchre_slam", 50)
	var start := enemy.global_position
	var observed_warning: Node3D = enemy._attack_warning
	var visible_before_exit := is_instance_valid(observed_warning) and observed_warning.visible
	for frame in 60:
		if enemy._attack_remaining <= 0.43:
			break
		await _ticks(1)
	Input.action_press("back")
	var released := await _wait_for(&"cast_end", &"sepulchre_slam", 60)
	Input.action_release("back")
	_check(warned and released and visible_before_exit and not _saw(&"damage", &"sepulchre_slam")
		and _flat(enemy.global_position - start).length() < 0.4,
		"The visible Sepulchre Slam remains planted and walking out of the warning escapes")


func _spawn(id: int, enemy_position: Vector3, player_position: Vector3, level := 1,
		ability: AbilityDefinition = null) -> CharacterBody3D:
	_game._reset_training_combat()
	_player.place_at(player_position)
	_player.restore_full()
	_game._combat_events.clear()
	var enemy := Catalog.instantiate(id)
	if ability != null:
		enemy.ability_loadout = [ability] as Array[AbilityDefinition]
	var rng := RandomNumberGenerator.new()
	rng.seed = 851
	enemy.setup(_player, level, "normal", rng, Callable(_game.training_ground, "navigation_route"))
	enemy.position = enemy_position
	enemy.configure_encounter(0, false, 16.0)
	enemy.configure_ai(_game._training_encounter, _game._training_pressure)
	enemy.combat_event.connect(_game._record_combat_event)
	enemy._decision_time = 0.0
	_game._training_actors.add_child(enemy)
	return enemy


func _saw(kind: StringName, ability: StringName) -> bool:
	for event: Dictionary in _game._combat_events:
		if event.get("side") == &"enemy" and event.get("kind") == kind and event.get("ability_id") == ability:
			return true
	return false


func _wait_for(kind: StringName, ability: StringName, frames: int) -> bool:
	for frame in frames:
		if _saw(kind, ability):
			return true
		await _ticks(1)
	return _saw(kind, ability)


func _flat(value: Vector3) -> Vector3:
	return Vector3(value.x, 0, value.z)


func _ticks(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("PASS  " + description)
	else:
		_failures += 1
		push_error("FAIL  " + description)
