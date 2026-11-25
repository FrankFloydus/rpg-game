extends SceneTree
## Exercises Thornback's attacks and timed guard through the Training Ground.

const Game = preload("res://main.tscn")
const AbilityDefinition = preload("res://combat/abilities/ability_definition.gd")
const Items = preload("res://systems/items.gd")
const THORNBACK := 15

var _game: Node3D
var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_game = Game.instantiate()
	_game.save_enabled = false
	root.add_child(_game)
	_game._create_character(0, "Thornback Tester")
	_aim(_game.hub.training_arrival_position(), _game.hub.interaction_position("training_portal"))
	await _tap(KEY_E)
	if _check(is_instance_valid(_game.training_ground), "The hub portal opens the Training Ground"):
		_game.player.place_at(Vector3(0.0, 0.08, 3.0))
		var thornback := await _spawn(3)
		if thornback:
			await _exercise_guard(thornback)
		await _exercise_attack(1, &"briar_charge", "Briar Charge")
		await _exercise_attack(1, &"thornback_lash", "Thornback Lash")
	_game.free()
	await _ticks(2)
	print("Hearth Below Thornback combat: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _exercise_guard(thornback: CharacterBody3D) -> void:
	thornback.max_health = 500.0
	thornback.health = thornback.max_health
	var guard: AbilityDefinition
	for ability: AbilityDefinition in thornback.ability_loadout:
		if ability.action_key == "thornback_guard":
			guard = ability
			break
	if not _check(guard != null, "Thornback equips the shared Briar Guard ability"):
		return
	var profile := guard.runtime_profile()
	var rate := Engine.physics_ticks_per_second
	var spike_materials := _spike_materials(thornback)
	_check(not spike_materials.is_empty() and not thornback.is_thornback_reflecting() and not _spikes_glow(spike_materials),
		"Thornback starts with its normal spike materials")

	# Hold the encounter math steady while taking weapon and timer measurements.
	thornback.set_physics_process(false)
	thornback._base_speed = 0.0
	_equip(Items.starter_weapon())
	var inactive := await _strike(thornback, 1.6)
	_check(inactive.dealt > 0.0 and is_zero_approx(inactive.lost),
		"A standard melee attack outside the stance damages only Thornback")
	_aim(thornback.global_position + Vector3(0.0, 0.05, 6.0), thornback.aim_point())
	thornback.set_physics_process(true)
	var warmup_frames := roundi((float(profile.first_delay) + thornback._rest_offset * 10.0) * rate)
	var start := await _wait_for_guard(thornback, true, warmup_frames + 16)
	if not _check(start >= warmup_frames - 10 and thornback.is_thornback_reflecting(),
			"An engaged Thornback enables the stance after its initial delay"):
		return
	_check(_spikes_glow(_spike_materials(thornback)), "The live stance gives every spike a red emissive material")

	var duration_frames := roundi(float(profile.duration) * rate)
	var active_frames := await _wait_for_guard(thornback, false, duration_frames + 8)
	_check(not thornback.is_thornback_reflecting() and absi(active_frames - duration_frames) <= 1,
		"Reflection lasts for the configured duration and then expires")
	_check(_spike_materials(thornback) == spike_materials, "Expiry restores the original materials")

	var cooldown_frames := roundi((guard.cooldown - float(profile.duration) + thornback._rest_offset * 10.0) * rate)
	var elapsed := await _wait_for_guard(thornback, true, cooldown_frames + 16)
	if not _check(thornback.is_thornback_reflecting() and absi(elapsed - cooldown_frames) <= 2,
			"The stance recurs after its cooldown"):
		return
	await _tap(KEY_F1)
	var paused_remaining: float = thornback._thornback_guard_remaining
	await _ticks(duration_frames)
	_check(_game.training_roster.is_open() and is_equal_approx(thornback._thornback_guard_remaining, paused_remaining),
		"The active stance timer pauses with the Training Ground roster")
	await _tap(KEY_F1)

	# Isolate reflected damage from Thornback's ordinary attacks.
	thornback.set_physics_process(false)
	_equip(Items.starter_weapon())
	var melee := await _strike(thornback, 1.6)
	_check(melee.dealt > 0.0 and is_equal_approx(melee.lost, melee.dealt),
		"A landed sword hit reflects the damage actually dealt")

	_equip({"type": "staff", "stats": {"cold_damage": 4.0}})
	var ranged := await _strike(thornback, 5.5)
	_check(ranged.dealt > 0.0 and is_zero_approx(ranged.lost), "A real staff strike bypasses the reflection stance")
	var enemy_life: float = thornback.health
	var player_life: float = _game.player.life
	thornback.apply_status("burning", 0.60, 8.0, _game.player)
	thornback._update_statuses(0.20)
	_check(thornback.health < enemy_life and is_equal_approx(_game.player.life, player_life),
		"Player damage over time reaches Thornback without reflection")

	_equip(Items.starter_weapon())
	_game.player.stats.fire_damage = 4.0
	_game.player.stats.armor = 55.0
	_game.player.stats.ward = 3.0
	_game.player.restore_full()
	var heavy := await _strike(thornback, 1.6, true)
	var expected := roundf(Items.physical_damage_after_armor(heavy.dealt, 55.0)) - 3.0
	_check(heavy.dealt > melee.dealt and is_equal_approx(heavy.lost, expected) and is_zero_approx(_game.player.ward),
		"An elemental heavy swing reflects one hit rounded after physical armor and before Ward")

	_equip(Items.starter_weapon())
	thornback.health = 5.0
	var killing := await _strike(thornback, 1.6)
	_check(not thornback.is_in_group("enemies") and is_equal_approx(killing.dealt, 5.0)
		and is_equal_approx(killing.lost, killing.dealt), "A killing melee hit still reflects the Life it removed")


func _exercise_attack(spawn_level: int, ability_id: StringName, ability_name: String) -> void:
	_game._reset_training_combat()
	_equip(Items.starter_weapon())
	# The first spawn is at (0, 0.08, -3). Keep the player in an open, straight charge lane.
	_game.player.place_at(Vector3(0.0, 0.08, 0.60))
	_game._combat_events.clear()
	var initial_life: float = _game.player.life
	var thornback := await _spawn(spawn_level)
	if thornback == null:
		return
	var did_hit := false
	for frame in Engine.physics_ticks_per_second * 5:
		await _ticks(1)
		for event: Dictionary in _game._combat_events:
			if event.get("kind") == &"damage" and event.get("ability_id") == ability_id:
				did_hit = float(event.get("amount", 0.0)) > 0.0
				break
		if did_hit:
			break
	_check(thornback.enemy_level == spawn_level and did_hit and _game.player.life < initial_life,
		"Level %d Thornback damages a stationary player with %s" % [spawn_level, ability_name])


func _wait_for_guard(thornback: CharacterBody3D, active: bool, limit: int) -> int:
	for frame in range(limit):
		if thornback.is_thornback_reflecting() == active:
			return frame
		await _ticks(1)
	return limit


func _spike_materials(thornback: CharacterBody3D) -> Array[StandardMaterial3D]:
	var materials: Array[StandardMaterial3D] = []
	var model: Node3D = thornback._model
	for spike: MeshInstance3D in model._thornback_spike_bases + model._thornback_spike_tips:
		materials.append(spike.get_active_material(0) as StandardMaterial3D)
	return materials


func _spikes_glow(materials: Array[StandardMaterial3D]) -> bool:
	if materials.is_empty():
		return false
	for material in materials:
		if material == null or not material.emission_enabled or material.emission.r <= material.emission.g * 2.0:
			return false
	return true


func _equip(item: Dictionary) -> void:
	var player: Node3D = _game.player
	player.update_equipment({"main_hand": item})
	player.stats.merge({"max_health": 1000.0, "damage_min": 16.0, "damage_max": 16.0, "armor": 0.0,
		"crit_chance": 0.0, "dodge_chance": 0.0, "ward": 0.0,
		"life_regen": 0.0, "life_on_kill": 0.0, "life_leech": 0.0}, true)
	player.restore_full()


func _strike(thornback: CharacterBody3D, distance: float, charged := false) -> Dictionary:
	var player: Node3D = _game.player
	_aim(thornback.global_position + Vector3(0.0, 0.06, distance), thornback.aim_point())
	await _ticks(2)
	var player_life: float = player.life
	var target_life: float = thornback.health
	Input.action_press("attack")
	if not charged:
		await _ticks(1)
		Input.action_release("attack")
	for frame in range(120):
		if thornback.health < target_life:
			break
		await _ticks(1)
	if charged:
		Input.action_release("attack")
	return {"dealt": target_life - thornback.health, "lost": player_life - player.life}


func _spawn(spawn_level: int) -> CharacterBody3D:
	await _tap(KEY_F1)
	var card := _game.training_roster.find_child("Enemy%d" % THORNBACK, true, false) as Button
	var level := _game.training_roster.find_child("EnemyLevel", true, false) as SpinBox
	if not _check(_game.training_roster.is_open() and is_instance_valid(card) and is_instance_valid(level),
			"The F1 roster offers Thornback and Enemy Level"):
		return null
	level.value = spawn_level
	card.grab_focus()
	await _tap(KEY_ENTER)
	for actor in _game._training_actors.get_children():
		if actor is CharacterBody3D and actor.archetype_id == THORNBACK:
			return actor
	_check(false, "Selecting the portrait spawns Thornback")
	return null


func _aim(point: Vector3, target: Vector3) -> void:
	var direction := (target - point - Vector3.UP * 1.56).normalized()
	_game.player.place_at(point, atan2(-direction.x, -direction.z), asin(direction.y))


func _tap(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await _ticks(3)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _ticks(3)


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
