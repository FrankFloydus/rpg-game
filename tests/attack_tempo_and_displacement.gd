extends SceneTree
## Verifies the shared attack clock and actual collision-sensitive combat movement.

const Game := preload("res://main.tscn")
const Items := preload("res://systems/items.gd")
const EnemyCatalog := preload("res://combat/enemies/enemy_catalog.gd")
const WeaponRoles := preload("res://combat/weapons/weapon_roles.gd")
const Tempo := preload("res://data/attack_tempo.tres")
const Enrage := preload("res://combat/effects/enrage.tres")
const ColossusSlam := preload("res://combat/abilities/sepulchre_slam.tres")

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
	await _ticks(3)
	_player = _game.player
	await _check_tempo()
	await _check_player_push()
	await _check_enemy_push()
	await _check_level_five_maul()
	await _check_maul_playpath()
	await _check_maul_level_disparity()
	await _check_maul_cleave()
	_game.free()
	await process_frame
	print("Hearth Below attack tempo and displacement: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_tempo() -> void:
	_check(is_equal_approx(Tempo.weapon_rate(20.0, false, 1.15), 1.38)
		and is_equal_approx(Tempo.weapon_rate(80.0, true, 1.15), 1.60),
		"Temporary haste and item attack speed compose before the shared cap")
	_player.place_at(Vector3(0, 0.08, 1.2))
	_player.update_equipment({"main_hand": Items.training_weapon_preview("oath_blade")})
	_player.restore_full()
	_player.stats.attack_speed = 210.0
	_player._soul_timer = 2.0
	_player.receive_combat_effect(Enrage, 2.0, 0.0, null, {})
	var trace_phases: Array[float] = []
	var swing_phases: Array[float] = []
	var cue := func(_message: String, sound: String) -> void:
		if sound == "swing":
			swing_phases.append(_player._current_clip_time())
	_player.feedback.connect(cue)
	_player.weapon_trace = func(_transform: Transform3D, _size: Vector3) -> void:
		trace_phases.append(_player._current_clip_time())
	var light: AbilityDefinition = _player._weapon_attack_ability(false)
	_player.cast_ability(light)
	var clip = _player._strike_clip
	var start_clock: float = _player._attack_timer
	_check(is_equal_approx(start_clock, clip.length / 1.60), "The actual light attack starts at no more than 1.60×")
	await _ticks(3)
	var elapsed := start_clock - float(_player._attack_timer)
	var phase: float = _player._current_clip_time()
	_check(elapsed >= 0.016 and is_equal_approx(phase, elapsed * 1.60)
		and _player._can_buffer_attack() == (phase >= clip.input_buffer),
		"The authored animation and input buffer use the gameplay clock under cap")
	for tick in range(36):
		if not trace_phases.is_empty() and not swing_phases.is_empty():
			break
		await _ticks(1)
	_check(not trace_phases.is_empty() and swing_phases.size() == 1
		and trace_phases[0] >= clip.trace_start and is_equal_approx(swing_phases[0], trace_phases[0]),
		"The capped weapon still opens its collision trace and swing sound on the same authored marker")
	_player.weapon_trace = Callable()
	_player.feedback.disconnect(cue)
	_player.place_at(Vector3(0, 0.08, 1.2))
	_player.update_equipment({"main_hand": Items.training_weapon_preview("crypt_knife")})
	_player.restore_full()
	_player.stats.attack_speed = 250.0
	_player.receive_combat_effect(Enrage, 2.0, 0.0, null, {})
	var charged: AbilityDefinition = _player._weapon_attack_ability(true)
	_player.cast_ability(charged, true, true)
	_check(_player._charge_duration >= _player.charge_seconds and _player._charging_attack,
		"The charged dagger keeps the authored minimum wind-up")
	await _ticks(16)
	_check(_player._charging_attack, "Even extreme haste does not release the charge before 0.34s")
	_player.restore_full()


func _check_player_push() -> void:
	var attacker := _spawn(16, Vector3(0, 0.08, 1))
	await _ticks(2)
	_prepare_player(Vector3(0, 0.08, 3))
	var ability := ColossusSlam.combat_details()
	var initial_life: float = _player.life
	_player._set_guard_held(true)
	_player.receive_enemy_hit(3.0, "physical", "", attacker, ability)
	_check(is_equal_approx(initial_life, _player.life) and _player._push_velocity.is_zero_approx(),
		"A block prevents a displacement-capable hit and its knockback")
	_player._set_guard_held(false)
	_player.receive_enemy_hit(0.05, "physical", "", attacker, ability)
	_check(_player._push_velocity.is_zero_approx(), "An impact rounded to zero does not move the player")
	_player.receive_enemy_hit(3.0, "physical", "", attacker, ability)
	var push: Vector3 = _player._push_velocity
	var opposing := ability.merged({"push_direction": Vector3.RIGHT})
	_player.receive_enemy_hit(3.0, "physical", "", attacker, opposing)
	_check(push.z > 4.0 and _player._push_velocity.is_equal_approx(push) and _player.life < initial_life - 3.0,
		"Major hits push away from their source while another hit cannot stack its motion")
	await _ticks(24)
	_check(_player.global_position.z > 3.70 and is_zero_approx(_player._push_velocity.length()),
		"The real CharacterBody moves in that direction and comes to rest")
	_prepare_player(Vector3(0, 0.08, 3))
	var wall := _wall_at(Vector3(0, 0, 3.85))
	await _ticks(2)
	_player.receive_enemy_hit(3.0, "physical", "", attacker, ability)
	await _ticks(24)
	_check(_player.global_position.z < 3.5 and _player._push_velocity.is_zero_approx(),
		"A solid wall stops the player knockback")
	wall.queue_free()
	attacker.queue_free()
	await _ticks(2)


func _check_enemy_push() -> void:
	_prepare_player(Vector3(0, 0.08, 3))
	var capacities: Array[float] = []
	for weapon: String in ["pilgrim_cudgel", "quarry_maul", "oath_blade"]:
		var enemy := _spawn(0, Vector3(0, 0.08, 1.15))
		await _ticks(2)
		enemy.max_health = 50.0
		enemy.health = enemy.max_health
		_player.update_equipment({"main_hand": Items.training_weapon_preview(weapon)})
		_player.stats.merge({"damage_min": 9.0, "damage_max": 9.0, "crit_chance": 0.0}, true)
		var hits: Array[Dictionary] = [{"target": enemy, "point": enemy.aim_point(), "direction": Vector3.FORWARD}]
		_player._resolve_attack(true, {}, null, hits, {"count": 0})
		capacities.append(enemy._impulse.length())
		enemy.queue_free()
		await _ticks(2)
	_check(capacities[0] > 1.6 and capacities[1] > capacities[0] and is_zero_approx(capacities[2]),
		"Charged mauls move a living target more than cudgels while a charged cutting hit keeps its normal reaction")
	var thrall := _spawn(0, Vector3(0, 0.08, 1.15))
	await _ticks(2)
	var contact := WeaponRoles.contact("mace_2h", "quarry_maul", true, {})
	thrall.max_health = 45.0
	thrall.health = thrall.max_health
	_check(not thrall.receive_blunt_knockback(Vector3.BACK, 1.0, contact)
		and thrall.receive_blunt_knockback(Vector3.BACK, 18.0, contact)
		and not thrall.receive_blunt_knockback(Vector3.RIGHT, 18.0, contact),
		"Living knockback requires meaningful damage and a fresh recovery interval")
	thrall.queue_free()
	await _ticks(2)


func _prepare_player(point: Vector3) -> void:
	_player.place_at(point)
	_player.restore_full()
	_player.stats.merge({"dodge_chance": 0.0, "armor": 0.0}, true)
	_player.ward = 0.0


func _check_level_five_maul() -> void:
	var progression := CharacterProgression.for_training(5)
	progression.allocate(&"strength", 4)
	_player.set_character_progression(progression)
	_player.update_equipment({"main_hand": Items.training_weapon_preview("charnel_mallet", 5)})
	var rng := RandomNumberGenerator.new()
	var near_max_seed := 0
	for seed_value in 256:
		rng.seed = seed_value
		rng.randf() # Critical chance roll precedes the damage roll.
		if rng.randf() > 0.96:
			near_max_seed = seed_value
			break
	for enemy_level in [5, 1]:
		# Stop the previous sweep before introducing a fresh target into its arc.
		_player.place_at(Vector3(0, 0.08, 2.5))
		var enemy := _spawn(0, Vector3(0, 0.08, 0.5), enemy_level)
		await _ticks(2)
		_aim_at_maul_target(enemy)
		_player._rng.seed = near_max_seed
		var full_life: float = enemy.max_health
		var started_full := is_equal_approx(float(enemy.health), full_life)
		_press_attack(true)
		for _tick in 138:
			if enemy.health < full_life:
				break
			await _ticks(1)
		_press_attack(false)
		var dealt: float = full_life - enemy.health
		var survived: bool = enemy.health > 0.0
		_check(started_full and _player._strike_heavy and dealt > 0.0 and survived == (enemy_level == 5),
			"A level-five plain Mallet charge %s a level-%d Thrall (%.0f Life removed, %.1f left)" % [
				"injures" if enemy_level == 5 else "defeats", enemy_level, dealt, enemy.health])
		enemy.queue_free()
		await _ticks(2)


func _check_maul_playpath() -> void:
	for depth: int in [6, 7]:
		var progression := CharacterProgression.for_training(depth)
		progression.allocate(&"strength", depth - 1)
		_player.set_character_progression(progression)
		var weapon := Items.training_weapon_preview("charnel_mallet")
		_player.update_equipment({"main_hand": weapon})
		var enemy := _spawn(12, Vector3(0, 0.08, 0.5), depth)
		await _ticks(2)
		_aim_at_maul_target(enemy)
		_player._rng.seed = 11039 + depth
		var original_life: float = enemy.health
		_press_attack(true)
		for tick in range(138):
			if enemy.health < original_life:
				break
			await _ticks(1)
		_press_attack(false)
		var dealt: float = original_life - enemy.health
		_check(dealt > 0.0 and enemy.health > 0.0 and _player._strike_heavy,
			"Depth %d: a full charged white Charnel Mallet lands %.0f and the Brute retains %.1f of %.1f Life" % [
				depth, dealt, enemy.health, original_life])
		enemy.queue_free()
		await _ticks(2)


func _check_maul_level_disparity() -> void:
	_player.set_character_progression(CharacterProgression.for_training(6))
	_player.update_equipment({"main_hand": Items.training_weapon_preview("charnel_mallet")})
	for enemy_level: int in [6, 14]:
		for rarity: String in ["normal", "magic", "rare"]:
			var enemy := _spawn(12, Vector3(0, 0.08, 0.5), enemy_level, rarity)
			await _ticks(2)
			for heavy: bool in [false, true]:
				_aim_at_maul_target(enemy)
				_player.stats.merge({"damage_min": 9.0, "damage_max": 9.0, "fire_damage": 4.0}, true)
				var contacts: Array[float] = []
				var struck := func(target: Node3D, resolved: float, _critical: bool) -> void:
					if target == enemy:
						contacts.append(resolved)
				_player.struck.connect(struck)
				_press_attack(true)
				if not heavy:
					_press_attack(false)
				for tick in range(138):
					if not contacts.is_empty():
						break
					await _ticks(1)
				_press_attack(false)
				_player.struck.disconnect(struck)
				var dealt: float = contacts[0] if not contacts.is_empty() else -1.0
				var expected := (18.0 if heavy else 13.0) if enemy_level == 6 else 1.0
				var mode := "Charged" if heavy else "Light"
				_check(contacts.size() == 1 and dealt == expected and enemy.health > 0.0
					and _player._strike_heavy == heavy,
					"%s maul against Level %d %s makes one traced contact for %.0f damage (expected %.0f)" % [
						mode, enemy_level, rarity, dealt, expected])
			enemy.queue_free()
			await _ticks(2)


func _check_maul_cleave() -> void:
	var first := _spawn(12, Vector3(-0.30, 0.08, 0.5), 6)
	var second := _spawn(12, Vector3(0.30, 0.08, 0.5), 6)
	await _ticks(2)
	_aim_at_maul_target(first, (first.global_position + second.global_position) * 0.5)
	_player.stats.merge({"damage_min": 9.0, "damage_max": 9.0, "fire_damage": 4.0}, true)
	var damage: Array[float] = []
	var struck := func(target: Node3D, dealt: float, _critical: bool) -> void:
		if target in [first, second]:
			damage.append(dealt)
	_player.struck.connect(struck)
	_press_attack(true)
	for tick in range(138):
		if damage.size() >= 2:
			break
		await _ticks(1)
	_press_attack(false)
	_player.struck.disconnect(struck)
	_check(damage == [18.0, 9.0], "Charged maul cleave deals full damage once and half on its second physical contact (%s)" % [damage])
	first.queue_free()
	second.queue_free()
	await _ticks(2)


func _aim_at_maul_target(enemy: CharacterBody3D, center := Vector3.INF) -> void:
	var standing := (center if center.is_finite() else enemy.global_position) + Vector3.BACK * 1.74 + Vector3.UP * 0.02
	var aim: Vector3 = (enemy.aim_point() - standing - Vector3.UP * 1.56).normalized()
	_player.place_at(standing, 0.0, asin(aim.y))
	_player.restore_full()
	_player.stats.crit_chance = 0.0


func _press_attack(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _spawn(id: int, point: Vector3, level := 1, rarity := "normal") -> CharacterBody3D:
	var enemy := EnemyCatalog.instantiate(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 947
	var affixes: Array[String] = []
	if rarity != "normal":
		affixes.append("quick")
	enemy.setup(_player, level, rarity, rng, Callable(), Callable(), affixes)
	enemy.position = point
	_game._training_actors.add_child(enemy)
	enemy.set_physics_process(false)
	return enemy


func _wall_at(point: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.8, 3.0, 0.24)
	var body := CollisionShape3D.new()
	body.shape = shape
	body.position.y = 1.5
	wall.add_child(body)
	wall.position = point
	_game._training_actors.add_child(wall)
	return wall


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame


func _check(passed: bool, message: String) -> void:
	_checks += 1
	if passed:
		print("PASS  " + message)
	else:
		_failures += 1
		push_error("FAIL  " + message)
