extends SceneTree
## Exercises the authored enemy level curve with live F1 spawns and weapon inputs.

const Game := preload("res://main.tscn")
const Enemy := preload("res://combat/enemies/enemy.gd")
const Items := preload("res://systems/items.gd")

const LEVELS := [1, 5, 10, 15, 20, 25]
const HIGH_LEVEL := 25
const THRALL_ID := 0
const GRAVE_MOTH_ID := 9
const DREAD_KNIGHT_ID := 19
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
		_check_floor_rarity_budget()
		await _check_training_progression_isolation()
		await _check_campaign_progression()
		await _check_enemy_checkpoint_life()
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
	_check(previous_life >= starting_life * 10.0 and previous_damage >= starting_damage * 4.0,
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


func _check_floor_rarity_budget() -> void:
	var entries: Array[Dictionary] = []
	for pack in range(5):
		for _member in range(4):
			entries.append({"pack": pack})
	var rng := RandomNumberGenerator.new()
	# Observed roster seed from a Depth 25 floor that rolled 15 elites in 20 slots.
	rng.seed = 3707578733 + 30289
	var roster: Array[Dictionary] = _game._roll_encounter_roster(entries, HIGH_LEVEL, rng, true)
	var elites := 0
	var rare_packs: Dictionary[int, int] = {}
	for index in range(roster.size()):
		var rarity: String = roster[index].rarity
		if rarity != "normal":
			elites += 1
		if rarity == "rare":
			var pack: int = entries[index].pack
			rare_packs[pack] = int(rare_packs.get(pack, 0)) + 1
	_check(elites <= 9, "The floor's elite budget preserves a majority of normal enemies")
	_check(not rare_packs.is_empty() and rare_packs.values().max() == 1, "Each pack has at most one rare")


func _check_training_progression_isolation() -> void:
	var campaign_before: Dictionary = _game.progression.snapshot()
	_check(_game._training_progression.xp == 0 and campaign_before.level == 1 and campaign_before.xp == 0,
		"Live arena kills and player level overrides grant no campaign experience")
	await _spawn_thrall(HIGH_LEVEL, HIGH_LEVEL)
	_game._open_inventory("inventory")
	var allocate := _game.inventory_ui.find_child("AllocateStrength", true, false) as Button
	if _check(is_instance_valid(allocate) and not allocate.disabled, "Training character sheet offers level-earned points"):
		var original_stamina: float = _player.stats.max_stamina
		allocate.pressed.emit()
		_check(is_equal_approx(float(_player.stats.max_stamina), original_stamina + 0.2),
			"Allocating Strength in Training updates the simulated guard pool")
	_game.inventory_ui.close()
	_game._leave_training_ground()
	_check(_game.progression.snapshot() == campaign_before and _player.combat_ability_level() == campaign_before.level,
		"Leaving Training restores the campaign player's own level, XP and attributes")


func _check_campaign_progression() -> void:
	_game._rng.seed = 94
	_game._select_depth(1)
	if not _check(_game.in_dungeon and not _game._enemies.is_empty(),
			"Start a fresh campaign run at Depth 1 for the progression test"):
		return
	var first_enemy: CharacterBody3D = _game._enemies.values().front()
	first_enemy.take_damage(first_enemy.max_health * 4.0)
	_check(_game.progression.level == 1 and _game.progression.xp > 0,
		"A real campaign enemy death credits the character with experience")
	for floor_index in _game._dungeon_floor_count():
		if floor_index > 0:
			var geometry: Node3D = _game._dungeon_floors[floor_index].geometry
			_game.player.place_at(geometry.to_global(geometry.spawn_position))
			_game._track_dungeon_floor()
		for enemy: CharacterBody3D in _game._enemies.values():
			enemy.take_damage(enemy.max_health * 4.0)
	_check(_game.run.cleared and _game.progression.level == 2 and _game.progression.points_available() == 1
		and _player.combat_ability_level() == 2 and _player.stats.max_health > 24.0,
		"The first actual Depth 1 clear reaches level 2 and refreshes player Life")
	_game._open_inventory("inventory")
	var allocate := _game.inventory_ui.find_child("AllocateStrength", true, false) as Button
	if _check(is_instance_valid(allocate) and not allocate.disabled, "The level-up point can be allocated on the character sheet"):
		allocate.pressed.emit()
		_check(_game.progression.attribute(&"strength") == 1 and _game.progression.points_available() == 0
			and is_equal_approx(float(_player.stats.max_stamina), 12.2),
			"Campaign allocation consumes the earned point and updates Maximum Stamina")
	_game.inventory_ui.close()
	_game._close_dungeon()
	await _ticks(2)


func _check_enemy_checkpoint_life() -> void:
	_game.unlocked = HIGH_LEVEL
	_game._rng.seed = 66103
	_game._select_depth(HIGH_LEVEL)
	if not _check(_game.in_dungeon, "Create a real level 25 dungeon for the checkpoint test"):
		return
	# Exercise import of a real threshold-linked layout and its legacy wounded enemy records.
	_game._enter_hub()
	_game._dungeon_root.free()
	_game.run.generation_version = 4
	_game._build_dungeon()
	_game._enter_dungeon(false)
	var actors: Dictionary = _game._enemies
	var moth_key := _find_actor_key(actors, GRAVE_MOTH_ID)
	var knight_key := _find_actor_key(actors, DREAD_KNIGHT_ID)
	var thrall_key := _find_actor_key(actors, THRALL_ID)
	if not _check(not moth_key.is_empty() and not knight_key.is_empty() and not thrall_key.is_empty(),
			"Seeded dungeon includes a Grave Thrall, Dread Knight and Grave Moth"):
		return
	var moth: CharacterBody3D = actors[moth_key]
	moth.restore_metamorphosis({"hatches": 2, "cocoon_remaining": 1.0})
	_game._change_dungeon_floor(1)
	if not _check(_game.run.floor_index == 1, "Descending records the current actors"):
		return
	var checkpoints: Dictionary = _game.run.floor_states["0"]["mob_states"]
	var thrall: Dictionary = checkpoints[thrall_key]
	var knight: Dictionary = checkpoints[knight_key]
	var cocoon: Dictionary = checkpoints[moth_key]
	var current_thrall_max := float(thrall.max_life)
	var current_knight_max := float(knight.max_life)
	var current_cocoon_max := float(cocoon.max_life)
	_check(current_thrall_max >= 112.0 and current_knight_max >= 378.0 and current_cocoon_max > 0.0,
		"Each stored actor records its current-phase maximum Life")

	# Original level 25 Life was 3.34x, with 40 Base Life on the Dread Knight.
	thrall.life = current_thrall_max / 14.0 * 3.34
	thrall.erase("max_life")
	knight.life = current_knight_max / (27.0 * 14.0) * 40.0 * 3.34 * 0.45
	knight.erase("max_life")
	cocoon.life = current_cocoon_max / 14.0 * 3.34 * 0.30
	cocoon.erase("max_life")

	_game._change_dungeon_floor(-1)
	if not _check(_game.run.floor_index == 0, "Ascending reloads the saved actors"):
		return
	actors = _game._enemies
	_check(is_equal_approx(actors[thrall_key].health, current_thrall_max),
		"An untouched legacy Grave Thrall returns with full updated Life")
	_check(is_equal_approx(actors[knight_key].health, current_knight_max * 0.45),
		"A wounded legacy Dread Knight retains its Life fraction after both scaling and base Life change")
	moth = actors[moth_key]
	_check(moth.is_cocoon() and moth.save_metamorphosis().hatches == 2
		and is_equal_approx(moth.max_health, current_cocoon_max)
		and is_equal_approx(moth.health, current_cocoon_max * 0.30),
		"A legacy Grave Moth cocoon keeps its hatch phase and its wound progress")

	_game._change_dungeon_floor(1)
	checkpoints = _game.run.floor_states["0"]["mob_states"]
	_check(is_equal_approx(float(checkpoints[knight_key].max_life), current_knight_max),
		"The next checkpoint stores updated maximum Life")
	_game._change_dungeon_floor(-1)
	_check(is_equal_approx(_game._enemies[knight_key].health, current_knight_max * 0.45),
		"Current checkpoint data restores the same wound progress on repeat visits")
	await _ticks(2)


func _find_actor_key(actors: Dictionary, archetype_id: int) -> String:
	for id: String in actors:
		if actors[id].archetype_id == archetype_id:
			return id
	return ""


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
