extends SceneTree
## Exercises the authored enemy level curve with live F1 spawns and weapon inputs.

const Game := preload("res://main.tscn")
const Enemy := preload("res://combat/enemies/enemy.gd")
const Items := preload("res://systems/items.gd")

const LEVELS := [1, 5, 10, 15, 20, 25]
const HIGH_LEVEL := 25
const THRALL_ID := 0
const EARLY_RAPIER_ID := "practice_balance_rapier"
const ARENA_ENEMY_POINT := Vector3(0.0, 0.08, 0.0)
const ARENA_PLAYER_POINT := Vector3(0.0, 0.08, 1.52)
const EYE_HEIGHT := 1.56

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
	_game._training_rng.seed = 2204
	_game._create_character(0, "Balance Tester")
	_game._enter_training_ground()
	await _ticks(6)
	_player = _game.player
	if _check(is_instance_valid(_game.training_ground), "Training starts from a live campaign"):
		await _check_level_progression()
		await _check_weapon_progression()
		await _check_guard_pressure()
		await _check_training_progression_isolation()
	_game.free()
	await _ticks(2)
	print("Hearth Below enemy level balance: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_level_progression() -> void:
	var previous_life := 0.0
	var previous_damage := 0.0
	var starting_life := 0.0
	var starting_damage := 0.0
	for level: int in LEVELS:
		var enemy := await _spawn_thrall(level)
		if enemy == null:
			return
		enemy.set_physics_process(false)
		var summary: Dictionary = enemy.combat_tuning_summary()
		var life := float(summary.life)
		var damage := float(summary.attack_damage)
		_check(enemy.enemy_level == level and summary.level == level and enemy.rarity == "normal"
			and is_equal_approx(enemy.health, life), "F1 spawns a full-Life normal enemy at level %d" % level)
		_check(life > previous_life and damage > previous_damage,
			"Level %d increases both combat stats (%.2f Life, %.2f Attack Damage)" % [level, life, damage])
		if level == 1:
			starting_life = life
			starting_damage = damage
		previous_life = life
		previous_damage = damage
	_check(previous_life >= starting_life * 9.0 and previous_damage >= starting_damage * 4.0,
		"Enemy level 25 remains meaningfully above starter level in both Life and damage")


func _check_weapon_progression() -> void:
	var starter := await _count_real_swings(1)
	_check(starter.defeated and starter.hits >= 2 and starter.hits <= 7,
		"The level 1 Thrall remains a short fight for a level 1 starter (%d swings)" % starter.hits)
	var level_ten_reference := await _count_real_swings(10, 10, 1)
	var level_ten_gap := await _count_real_swings(10, 1, 3)
	_check(level_ten_reference.first_damage > 0.0 and level_ten_gap.hits == 3 and not level_ten_gap.defeated
		and is_zero_approx(level_ten_gap.total_damage),
		"A level 1 starter can contact a level 10 Thrall but its damage rounds to zero")
	var practice: RefCounted = _game._training_inventory
	var early_rapier := Items.training_weapon_item("funeral_rapier", EARLY_RAPIER_ID)
	if not _check(practice.add_item(early_rapier) and practice.equip_item(StringName(EARLY_RAPIER_ID), "main_hand").is_empty()
			and _player.stats.damage_min == 6.0 and _player.stats.damage_max == 10.0
			and _player.stats.armor == 0.0, "Equip the plain 6–10 Physical rapier on the unarmoured character"):
		return
	var level_matched_rapier := await _count_real_swings(HIGH_LEVEL, HIGH_LEVEL)
	_check(level_matched_rapier.defeated and level_matched_rapier.hits >= 8,
		"The same 6–10 Rapier can deal normal damage when the player matches the enemy level")
	_game._combat_events.clear()
	var extreme_gap := await _count_real_swings(HIGH_LEVEL, 1, 6)
	_check(extreme_gap.hits == 6 and not extreme_gap.defeated and is_zero_approx(extreme_gap.total_damage),
		"The level 1 Rapier still contacts a level 25 enemy and its damage rounds to zero")
	_check(_game._combat_events.any(func(event: Dictionary) -> bool:
		return event.kind == &"status" and String(event.get("detail", "")).contains("Glancing")),
		"The extreme level gap is visible in the combat log as a glancing hit")
	var fitted := _find_rapier_from_level_stock()
	if not _check(not fitted.is_empty() and practice.add_item(fitted)
			and practice.equip_item(StringName(fitted["id"]), "main_hand").is_empty()
			and _player.stats.damage_min > 10.0, "The real level 25 item pool offers a stronger rapier of the same base"):
		return
	var matched := await _count_real_swings(HIGH_LEVEL, HIGH_LEVEL)
	_check(matched.defeated and matched.hits >= 3 and matched.hits <= 6,
		"Matched level and gear keep a level 25 normal fight short (%d swings, %.2f s)" % [
			matched.hits, matched.seconds])


func _find_rapier_from_level_stock() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90391
	for attempt in 64:
		for item: Dictionary in Items.roll_vendor(HIGH_LEVEL, rng):
			if item.base_id == "funeral_rapier":
				return item
	return {}


func _count_real_swings(level: int, player_level := 1, hit_limit := 60) -> Dictionary:
	var enemy := await _spawn_thrall(level, player_level)
	if enemy == null:
		return {"hits": 0, "seconds": 0.0, "first_damage": 0.0, "total_damage": 0.0, "defeated": false}
	enemy.set_physics_process(false)
	_aim_duel(enemy)
	_player._rng.seed = 9981
	await _ticks(4)
	var hit_damage: Array[float] = []
	var track_hit := func(target: Node3D, damage: float, _critical: bool) -> void:
		if target == enemy:
			hit_damage.append(damage)
	_player.struck.connect(track_hit)
	var ticks := 0
	while ticks < 2400 and not enemy._dead and hit_damage.size() < hit_limit:
		if _player._attack_timer <= 0.0 and not _player._strike_pending:
			_mouse_event(MOUSE_BUTTON_LEFT, true)
			_mouse_event(MOUSE_BUTTON_LEFT, false)
		await _ticks(1)
		ticks += 1
	_player.struck.disconnect(track_hit)
	var total_damage := 0.0
	for damage in hit_damage:
		total_damage += damage
	return {"hits": hit_damage.size(), "seconds": float(ticks) / Engine.physics_ticks_per_second,
		"first_damage": hit_damage.front() if not hit_damage.is_empty() else 0.0,
		"total_damage": total_damage, "defeated": enemy._dead}


func _check_guard_pressure() -> void:
	var low := await _measure_first_block(1)
	var high := await _measure_first_block(HIGH_LEVEL)
	_check(low > 0.0 and low < 0.55, "The first level 1 hit spends part of the bare-weapon guard")
	_check(is_equal_approx(high, 1.0),
		"The first level 25 hit empties the level 1 bare-weapon guard (%.0f%% Stamina)" % (high * 100.0))


func _measure_first_block(level: int) -> float:
	var enemy := await _spawn_thrall(level)
	if enemy == null:
		return -1.0
	_aim_duel(enemy)
	var initial_stamina: float = _player.stamina
	_mouse_event(MOUSE_BUTTON_RIGHT, true)
	for frame in 180:
		await _ticks(1)
		if _player.stamina < initial_stamina:
			break
	_mouse_event(MOUSE_BUTTON_RIGHT, false)
	return 1.0 - (_player.stamina / initial_stamina)


func _check_training_progression_isolation() -> void:
	var campaign_before: Dictionary = _game.progression.snapshot()
	_check(_game._training_progression.xp == 0 and campaign_before.level == 1 and campaign_before.xp == 0,
		"Live arena kills and player level overrides grant no campaign experience")
	await _spawn_thrall(HIGH_LEVEL, HIGH_LEVEL)
	_game._open_inventory("inventory")
	var allocate := _game.inventory_ui.find_child("Strength", true, false).get_node_or_null("Controls/Allocate") as Button
	if _check(is_instance_valid(allocate) and not allocate.disabled, "Training character sheet offers level-earned points"):
		var original_stamina: float = _player.stats.max_stamina
		allocate.pressed.emit()
		_check(is_equal_approx(float(_player.stats.max_stamina), original_stamina + 0.2),
			"Allocating Strength in Training updates the simulated guard pool")
	_game.inventory_ui.close()
	_game._leave_training_ground()
	_check(_game.progression.snapshot() == campaign_before and _player.combat_ability_level() == campaign_before.level,
		"Leaving Training restores the campaign player's own level, XP and attributes")


func _spawn_thrall(level: int, player_level := 1) -> CharacterBody3D:
	_game._reset_training_combat()
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_F1
		event.physical_keycode = KEY_F1
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	await _ticks(3)
	if not _check(_game.training_roster.is_open(), "F1 opens the production arena roster"):
		return null
	var level_selector := _game.training_roster.find_child("EnemyLevel", true, false) as SpinBox
	var player_level_selector := _game.training_roster.find_child("PlayerLevel", true, false) as SpinBox
	var thrall_card := _game.training_roster.find_child("Enemy%d" % THRALL_ID, true, false) as Button
	player_level_selector.get_line_edit().text = str(player_level)
	player_level_selector.apply()
	level_selector.get_line_edit().text = str(level)
	thrall_card.pressed.emit()
	if not _check(_player.combat_ability_level() == player_level, "F1 applies independent player level %d" % player_level):
		return null
	for actor: Node in _game._training_actors.get_children():
		if actor is Enemy:
			return actor
	_check(false, "The roster should create a real Grave Thrall")
	return null


func _aim_duel(enemy: CharacterBody3D) -> void:
	enemy.global_position = ARENA_ENEMY_POINT
	var direction: Vector3 = (enemy.aim_point() - ARENA_PLAYER_POINT - Vector3.UP * EYE_HEIGHT).normalized()
	_player.place_at(ARENA_PLAYER_POINT, atan2(-direction.x, -direction.z), asin(direction.y))
	_player.restore_full()


func _mouse_event(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _ticks(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if condition:
		print("PASS  " + description)
	else:
		_failures += 1
		push_error("FAIL  " + description)
	return condition
