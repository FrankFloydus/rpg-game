extends SceneTree
## Exercises the held mouse controls and guard timing in the real Training Ground.

const Game = preload("res://main.tscn")
const Items = preload("res://systems/items.gd")
const StatusCatalog = preload("res://combat/effects/status_catalog.gd")
const SpikePlate = preload("res://world/hazards/spike_plate.tscn")
const CARRION_BRUTE := 12

var _game: Node3D
var _player: CharacterBody3D
var _target: CharacterBody3D
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
	if _check(is_instance_valid(_game.training_ground), "A fresh game enters the real Training Ground"):
		_game.training_roster.present()
		_game._spawn_training_enemy(0)
		for actor in _game._training_actors.get_children():
			if actor is CharacterBody3D:
				_target = actor
				_target.set_physics_process(false)
				break
		if _check(is_instance_valid(_target), "The Training Ground spawns a stationary combat target"):
			_player.stats.merge({"damage_min": 4.0, "damage_max": 4.0, "crit_chance": 0.0,
				"dodge_chance": 0.0, "mana_regen": 0.0}, true)
			await _check_attacks()
			await _check_charged_chain()
			await _check_directional_chain("mace_2h", 0.25)
			await _check_directional_chain("axe_1h", 0.53)
			await _check_directional_chain("axe_2h", 0.40)
			await _check_directional_chain("sword_2h", 0.40)
			await _check_guard()
			await _check_jump()
			await _check_camera_impacts()
			await _check_world_warnings()
	_game.free()
	await _ticks(2)
	print("Hearth Below combat input: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_attacks() -> void:
	await _reset()
	var cues: Array[StringName] = []
	var record_swing := func(_message: String, event: String) -> void:
		if event == "swing":
			cues.append(_player._strike_animation)
	_player.feedback.connect(record_swing)
	_mouse(MOUSE_BUTTON_LEFT, true)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _ticks(3)
	_check(cues.is_empty() and _damage_hits() == 0,
		"Melee windup stays silent until its authored contact window")
	await _ticks(14)
	_check(_damage_hits() == 1 and is_equal_approx(_target.health, 296.0),
		"A real click that starts and ends in one tick lands a single Light Attack")
	_check(cues.size() == 1, "The active melee clip plays one swing cue")
	_check(not _player._can_buffer_attack(), "The early recovery frames precede the editable buffer marker")
	_mouse(MOUSE_BUTTON_LEFT, true)
	_mouse(MOUSE_BUTTON_LEFT, false)
	_check(is_zero_approx(_player._light_buffer), "A tap before Input Buffer does not queue a strike")
	for frame in 30:
		if _player._can_buffer_attack():
			break
		await _ticks(1)
	_mouse(MOUSE_BUTTON_LEFT, true)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _ticks(31)
	_check(_damage_hits() == 2 and is_equal_approx(_target.health, 292.0),
		"A tap after Input Buffer is held through recovery and then lands")
	_check(cues == [&"light", &"light_2"], "A buffered light queues the opposite clip and plays its own cue once")
	await _wait_for_chain_input()
	_mouse(MOUSE_BUTTON_LEFT, true)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _wait_for_damage_hits(3, 60)
	_check(cues == [&"light", &"light_2", &"light"] and _damage_hits() == 3,
		"The light attack chain returns to the opener on its third committed swing")

	await _reset()
	Input.action_press("attack")
	await _ticks(15)
	_check(_player.attack_charge_fraction() > 0.0 and _damage_hits() == 0 and is_equal_approx(_player.mana, 12.0),
		"Holding LMB winds up a visible charge before spending Mana or landing a hit")
	await _wait_for_damage_hits(1, 72)
	_check(_damage_hits() == 1 and is_equal_approx(_target.health, 293.0) and is_equal_approx(_player.mana, 9.0),
		"The full hold automatically lands the stronger hit and spends Mana once")
	await _ticks(90)
	_check(_damage_hits() == 1, "Holding past release does not repeat attacks")
	Input.action_release("attack")
	await _ticks(1)
	var released_swings := cues.size()

	await _reset()
	_mouse(MOUSE_BUTTON_LEFT, true)
	await _ticks(16)
	_mouse(MOUSE_BUTTON_LEFT, false)
	_check(_player._strike_animation == &"light" and is_zero_approx(_player.attack_charge_fraction())
		and is_zero_approx(_player._weapon._transition_remaining) and _damage_hits() == 0,
		"Releasing a charge selects the light immediately with zero blend and respects Trace Start")
	await _wait_for_damage_hits(1, 32)
	_check(_damage_hits() == 1 and is_equal_approx(_target.health, 296.0)
		and _saw_cancel("Released before full charge") and is_equal_approx(_player.mana, 12.0),
		"A partial charge release lands a single Light Attack for normal damage and no Mana")
	_check(cues.size() == released_swings + 1 and cues.back() == &"light", "The partial release plays one light swing cue")

	await _reset()
	Input.action_press("attack")
	await _ticks(16)
	_mouse(MOUSE_BUTTON_RIGHT, true)
	_check(_player.is_blocking() and _player.attack_charge_fraction() == 0.0 and _saw_cancel("Guard raised"),
		"A real RMB press raises guard and cancels charge immediately, before the next tick")
	await _ticks(32)
	_check(_damage_hits() == 0 and is_equal_approx(_player.mana, 12.0), "Blocking does not launch or pay for a charged attack")
	Input.action_release("attack")
	_mouse(MOUSE_BUTTON_RIGHT, false)

	await _reset()
	_mouse(MOUSE_BUTTON_RIGHT, true)
	_mouse(MOUSE_BUTTON_LEFT, true)
	_check(_player.guard_is_held() and not _player.is_blocking(),
		"LMB drops an active guard before the next physics tick")
	await _ticks(18)
	_check(_damage_hits() == 1 and is_equal_approx(_target.health, 296.0)
		and is_equal_approx(_player.mana, 12.0) and not _player.is_blocking(),
		"Attacking through guard yields one light hit with no Mana cost and exposes recovery")
	await _ticks(30)
	_check(_player.is_blocking() and _damage_hits() == 1,
		"Held RMB automatically guards again when the attack finishes")
	_mouse(MOUSE_BUTTON_LEFT, false)
	_mouse(MOUSE_BUTTON_RIGHT, false)
	_player.feedback.disconnect(record_swing)
	await _check_retimed_trace()
	await _check_animated_blade_cover()


func _check_charged_chain() -> void:
	await _reset()
	var expected: Array[StringName] = [&"heavy", &"heavy_2", &"heavy"]
	var releases: Array[StringName] = []
	var record_swing := func(_message: String, event: String) -> void:
		if event == "swing":
			releases.append(_player._strike_animation)
	_player.feedback.connect(record_swing)
	for index in expected.size():
		await _wait_for_chain_input()
		Input.action_press("attack")
		for _frame in 120:
			await _ticks(1)
			if _player.attack_charge_fraction() > 0.10:
				break
		var expected_charge := &"charge_2" if expected[index] == &"heavy_2" else &"charge"
		_check(_player._strike_animation == expected[index]
			and _player._weapon._main_animation.current_animation == expected_charge,
			"Charged step %d winds into %s before release" % [index + 1, expected[index]])
		await _wait_for_damage_hits(index + 1, 60)
		Input.action_release("attack")
		await _ticks(1)
	_check(releases == expected and _damage_hits() == 3 and is_equal_approx(_player.mana, 3.0),
		"Three auto-releases alternate through the real Heavy Attack cooldown and spend Mana once each")
	for _frame in 180:
		if _player._chain_time_left <= 0.0:
			break
		await _ticks(1)
	_mouse(MOUSE_BUTTON_LEFT, true)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _wait_for_damage_hits(4, 60)
	_check(releases.size() == 4 and releases.back() == &"light", "An expired chain returns to the light opener")
	await _wait_for_chain_input()
	Input.action_press("attack")
	await _wait_for_damage_hits(5, 72)
	Input.action_release("attack")
	await _ticks(1)
	_check(releases.size() == 5 and releases.back() == &"heavy_2",
		"A hold buffered after the light opener selects the opposite charged release")
	_player.feedback.disconnect(record_swing)


func _wait_for_chain_input() -> void:
	for _frame in 90:
		if _player._can_buffer_attack():
			return
		await _ticks(1)


func _check_directional_chain(weapon_type: String, move_limit: float) -> void:
	var equipment: Dictionary = _player._equipment
	var stats: Dictionary = _player.stats.duplicate()
	_player.update_equipment({"main_hand": {"type": weapon_type}})
	_player.stats.merge(stats, true)
	await _reset()
	var releases: Array[StringName] = []
	var record_swing := func(_message: String, event: String) -> void:
		if event == "swing":
			releases.append(_player._strike_animation)
	var impacts: Array[Vector2] = []
	var record_impact := func(_enemy: Node3D, _amount: float, _critical: bool) -> void:
		impacts.append(Vector2(_player._weapon._impact_pause, _player._weapon._impact_recoil))
	_player.feedback.connect(record_swing)
	_player.struck.connect(record_impact)
	for index in range(4):
		await _wait_for_chain_input()
		_mouse(MOUSE_BUTTON_LEFT, true)
		_mouse(MOUSE_BUTTON_LEFT, false)
		await _wait_for_damage_hits(index + 1, 100)
	_check(releases == [&"light", &"light_2", &"light_3", &"light"] and _damage_hits() == 4,
		"%s taps cycle through both sweeps and the overhead strike" % weapon_type)
	await _reset()
	releases.clear()
	var windups: Array[StringName] = []
	for index in range(4):
		await _wait_for_chain_input()
		Input.action_press("attack")
		for _frame in 140:
			await _ticks(1)
			if _player.attack_charge_fraction() > 0.10:
				break
		windups.append(StringName(_player._weapon._main_animation.current_animation))
		await _wait_for_damage_hits(index + 1, 100)
		Input.action_release("attack")
		await _ticks(1)
	_check(windups == [&"charge", &"charge_2", &"charge_3", &"charge"]
		and releases == [&"heavy", &"heavy_2", &"heavy_3", &"heavy"]
		and _damage_hits() == 4 and is_zero_approx(_player.mana),
		"%s holds wind up and cycle through both sweeps and the overhead strike" % weapon_type)
	await _reset()
	releases.clear()
	for index in range(2):
		await _wait_for_chain_input()
		_mouse(MOUSE_BUTTON_LEFT, true)
		_mouse(MOUSE_BUTTON_LEFT, false)
		await _wait_for_damage_hits(index + 1, 100)
	await _wait_for_chain_input()
	Input.action_press("attack")
	await _wait_for_damage_hits(3, 110)
	Input.action_release("attack")
	await _ticks(1)
	_check(releases == [&"light", &"light_2", &"heavy_3"] and _damage_hits() == 3,
		"Two %s taps can chain into the overhead charged hit" % weapon_type)
	_check(impacts.size() == 11 and impacts.all(func(impact: Vector2) -> bool:
		return is_zero_approx(impact.x) and impact.y > 0.0),
		"Each %s contact recoils while its follow-through continues at the authored phase" % weapon_type)
	_player.feedback.disconnect(record_swing)
	_player.struck.disconnect(record_impact)
	await _check_strafe_charge(weapon_type, move_limit)
	_player.update_equipment(equipment)
	_player.stats.merge(stats, true)


func _check_strafe_charge(weapon_type: String, move_limit: float) -> void:
	var target_origin: Vector3 = _target.global_position
	var lateral_hits: Array[float] = []
	var record_contact := func(enemy: Node3D, _amount: float, _critical: bool) -> void:
		if _player._strike_sweep == null:
			return
		for contact: Dictionary in _player._strike_sweep.contacts():
			if contact.target == enemy:
				lateral_hits.append(_player.get_aim_transform().basis.x.dot(contact.direction))
				break
	_player.struck.connect(record_contact)
	for index in range(2):
		_target.global_position = target_origin
		await _reset()
		lateral_hits.clear()
		# A pending overhead strike makes each directional override observable.
		_player._next_chain_stage = 3
		_player._chain_time_left = 1.0
		var strafe := &"left" if index == 0 else &"right"
		var reverse := &"right" if index == 0 else &"left"
		var charge_clip := &"charge_2" if index == 0 else &"charge"
		var strike_clip := &"heavy_2" if index == 0 else &"heavy"
		var strafe_sign := -1.0 if index == 0 else 1.0
		Input.action_press(strafe)
		await _ticks(8)
		var walk_speed := _planar_speed()
		var lateral_walk: float = _player.get_aim_transform().basis.x.dot(_player.velocity)
		Input.action_press("attack")
		for _frame in 40:
			await _ticks(1)
			if _player.attack_charge_fraction() > 0.07:
				break
		_check(_player.attack_charge_fraction() > 0.0 and _player._strike_animation == strike_clip
			and _player._weapon._main_animation.current_animation == charge_clip,
			"Charging %s while strafing %s loads from the opposite side" % [weapon_type, strafe])
		_check(walk_speed > 1.0 and _planar_speed() > walk_speed * 0.65,
			"Charging %s eases into its movement penalty" % weapon_type)
		await _ticks(13)
		_check(absf(_planar_speed() / walk_speed - move_limit) < 0.07,
			"A loaded %s reduces strafe speed to %.0f%%" % [weapon_type, move_limit * 100.0])
		Input.action_release(strafe)
		await _ticks(3)
		var held_through_neutral: bool = _player._strike_animation == strike_clip \
			and _player._weapon._main_animation.current_animation == charge_clip
		Input.action_press(reverse)
		await _ticks(5)
		_check(held_through_neutral and _player.attack_charge_fraction() > 0.0 and _player._strike_animation == strike_clip
			and _player._weapon._main_animation.current_animation == charge_clip,
			"Releasing or reversing strafe mid-charge leaves the displayed pose and traced attack latched")
		_target.global_position = Vector3(_player.global_position.x, target_origin.y, _player.global_position.z) \
			- _player.global_basis.z * 1.6
		await _wait_for_damage_hits(1, 80)
		_check(_damage_hits() == 1 and _player._next_chain_stage == 3 - index
			and _planar_speed() < walk_speed * (move_limit + 0.10),
			"The latched %s swing lands while planted and advances from the stage it used" % weapon_type)
		_check(lateral_walk * strafe_sign > 1.0 and lateral_hits.size() == 1
			and lateral_hits[0] * strafe_sign > 0.20,
			"Strafing %s with %s launches a traced swing that travels %s" % [strafe, weapon_type, strafe])
		Input.action_release("attack")
		for _frame in 100:
			if _player._attack_timer <= 0.0:
				break
			await _ticks(1)
		_check(_planar_speed() > walk_speed * 0.90,
			"The %s gives strafe speed back through follow-through" % weapon_type)
		Input.action_release(reverse)
	_player.struck.disconnect(record_contact)

	_target.global_position = target_origin
	await _reset()
	var mana: float = _player.mana
	Input.action_press("left")
	Input.action_press("attack")
	await _ticks(25)
	Input.action_release("left")
	_target.global_position = Vector3(_player.global_position.x, target_origin.y, _player.global_position.z) \
		- _player.global_basis.z * 1.6
	Input.action_release("attack")
	_mouse(MOUSE_BUTTON_LEFT, false)
	_check(_player._strike_animation == &"light_2" and _player.attack_charge_fraction() == 0.0
		and _player._weapon._transition_remaining == 0.0 and _damage_hits() == 0,
		"Releasing a leftward %s charge keeps the side and immediately enters its light" % weapon_type)
	await _wait_for_damage_hits(1, 32)
	_check(_damage_hits() == 1 and _player._next_chain_stage == 3 and is_equal_approx(_player.mana, mana),
		"A converted %s swing advances from the chosen side and spends no Mana" % weapon_type)


func _planar_speed() -> float:
	return Vector2(_player.velocity.x, _player.velocity.z).length()


func _wait_for_damage_hits(expected: int, limit: int) -> void:
	for _frame in limit:
		if _damage_hits() >= expected:
			return
		await _ticks(1)


func _check_retimed_trace() -> void:
	await _reset()
	var clip: Animation = _player._weapon.attack_animation(false)
	var start := clip.get_marker_time(&"Trace Start")
	var color := clip.get_marker_color(&"Trace Start")
	var edited_start := lerpf(start, clip.get_marker_time(&"Trace End"), 0.65)
	clip.remove_marker(&"Trace Start")
	clip.add_marker(&"Trace Start", edited_start)
	var swing_times: Array[float] = []
	var record := func(_message: String, event: String) -> void:
		if event == "swing":
			swing_times.append(_player._current_clip_time())
	_player.feedback.connect(record)
	_mouse(MOUSE_BUTTON_LEFT, true)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _ticks(8)
	_check(swing_times.is_empty() and _damage_hits() == 0,
		"Moving Trace Start later delays both the whoosh and damage")
	await _ticks(24)
	_check(swing_times.size() == 1 and swing_times[0] >= edited_start
		and swing_times[0] - edited_start <= 1.0 / Engine.physics_ticks_per_second,
		"The player honors the edited marker on its first active physics tick")
	_player.feedback.disconnect(record)
	clip.remove_marker(&"Trace Start")
	clip.add_marker(&"Trace Start", start)
	clip.set_marker_color(&"Trace Start", color)


func _check_animated_blade_cover() -> void:
	await _reset()
	var wall := _add_test_wall(1.1)
	await _ticks(2)
	_mouse(MOUSE_BUTTON_LEFT, true)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _ticks(26)
	_check(is_equal_approx(_target.health, 300.0) and _damage_hits() == 0,
		"A viewmodel sword already past a wall cannot damage a covered target")
	wall.queue_free()


func _add_test_wall(width: float) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var stone := BoxShape3D.new()
	stone.size = Vector3(width, 2.2, 0.12)
	shape.shape = stone
	wall.add_child(shape)
	_game._training_actors.add_child(wall)
	wall.global_position = _target.global_position.lerp(_player.global_position, 0.44) + Vector3.UP * 1.02
	return wall


func _check_guard() -> void:
	await _reset()
	_check(is_equal_approx(_player.max_stamina(), 12.0) and is_equal_approx(_player.stamina, 12.0),
		"The unshielded player starts with 12 Stamina")
	_mouse(MOUSE_BUTTON_RIGHT, true)
	var starting_life: float = _player.life
	_check(not _player.receive_enemy_hit(2.0, "physical", "burning")
		and is_equal_approx(_player.life, starting_life) and not _player._ailments.has("burning")
		and is_equal_approx(_player.stamina, 7.9),
		"Manual block spends Stamina and prevents a direct hit and its on-hit effect")

	var before_unblockable: float = _player.stamina
	_check(_player.receive_enemy_hit(3.0, "physical", "", null, {"unblockable": true})
		and is_equal_approx(_player.life, starting_life - 3.0)
		and is_equal_approx(_player.stamina, before_unblockable),
		"An unblockable impact deals Life damage and leaves Stamina alone")
	var burn := StatusCatalog.get_effect("burning")
	_player.receive_combat_effect(burn, 0.45, 2.0, null, {})
	await _ticks(32)
	_check(_player.life < starting_life - 3.0 and is_equal_approx(_player.stamina, before_unblockable),
		"Damage over time keeps ticking through a held guard without consuming Stamina")
	await _ticks(32)
	_mouse(MOUSE_BUTTON_RIGHT, false)
	await _ticks(40)
	_check(is_equal_approx(_player.stamina, before_unblockable),
		"Lowering a spent guard waits for recovery even after the last hit was over a second ago")
	await _ticks(31)
	var regained: float = _player.stamina - before_unblockable
	_check(regained > 1.45 and regained < 1.65, "Starter Stamina recovers at about 3.2 points per second")
	_player.restore_stamina(before_unblockable)
	_mouse(MOUSE_BUTTON_RIGHT, true)

	_player.receive_enemy_hit(2.0, "physical")
	_check(_player.is_blocking() and is_equal_approx(_player.stamina, 3.8), "The unshielded stance can absorb a second normal hit")
	var before_break: float = _player.life
	_player.receive_enemy_hit(2.0, "physical")
	_check(not _player.is_blocking() and _player.guard_is_held() and is_zero_approx(_player.stamina)
		and is_equal_approx(_player.life, before_break), "The last available block absorbs the hit and breaks guard")
	_check(_player.receive_enemy_hit(2.0, "physical") and is_equal_approx(_player.life, before_break - 2.0),
		"Further hits land during guard break even while RMB stays down")
	await _ticks(118)
	_check(is_zero_approx(_player.stamina) and not _player.is_blocking(), "Depletion prevents recharge for two seconds")
	_mouse(MOUSE_BUTTON_RIGHT, false)
	await _ticks(3)
	_mouse(MOUSE_BUTTON_RIGHT, true)
	await _ticks(7)
	_check(_player.stamina > 0.0 and _player.stamina < 1.0 and not _player.is_blocking(),
		"RMB release and re-press during break preserves the timer and still requires one point")
	await _ticks(13)
	_check(_player.stamina >= 1.0 and _player.is_blocking(), "Holding RMB resumes the guard at one Stamina")
	_mouse(MOUSE_BUTTON_RIGHT, false)

	_player.update_equipment({"main_hand": Items.starter_weapon(),
		"off_hand": {"type": "shield", "stats": {"max_stamina": 3.0}}})
	_player.restore_full()
	_mouse(MOUSE_BUTTON_RIGHT, true)
	var absorbed := 0
	while _player.is_blocking() and absorbed < 8:
		_player.receive_enemy_hit(2.0, "physical")
		absorbed += 1
	_check(is_equal_approx(_player.max_stamina(), 15.0) and absorbed == 5,
		"A starter shield raises maximum Stamina and withstands five comparable hits")
	_mouse(MOUSE_BUTTON_RIGHT, false)
	_player.restore_stamina(5.0)
	await _ticks(60)
	_check(absf(_player.stamina - 8.44) < 0.10,
		"Extra capacity contributes a measured recovery bonus without a full-gauge refill")

	_player.restore_stamina(1.0)
	_mouse(MOUSE_BUTTON_RIGHT, true)
	_check(_player.is_blocking() and not _player.receive_enemy_hit(2.0, "physical") and is_zero_approx(_player.stamina),
		"Exactly one point allows one last block")
	_mouse(MOUSE_BUTTON_RIGHT, false)

	_player.restore_stamina(200.0)
	_check(is_equal_approx(_player.stamina, _player.max_stamina()), "Recovered save data clamps Stamina to the equipped maximum")
	_player.restore_stamina(0.0)
	_mouse(MOUSE_BUTTON_RIGHT, true)
	await _ticks(118)
	_check(is_zero_approx(_player.stamina) and not _player.is_blocking(),
		"Resuming with depleted Stamina honors the guard break delay")
	_mouse(MOUSE_BUTTON_RIGHT, false)


func _check_jump() -> void:
	await _reset()
	await _ticks(4)
	var ground: Vector3 = _player.global_position
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	Input.parse_input_event(space)
	Input.flush_buffered_events()
	await _ticks(5)
	var displacement: Vector3 = _player.global_position - ground
	_check(not _player.is_on_floor() and displacement.y > 0.24 and
		Vector2(displacement.x, displacement.z).length() < 0.02,
		"Space starts a vertical jump without a horizontal dash")
	_check(_player.receive_enemy_hit(1.0, "physical"), "Jumping does not grant invulnerability")
	_mouse(MOUSE_BUTTON_RIGHT, true)
	_check(_player.is_blocking() and _player.velocity.y > 0.0,
		"RMB can raise guard in the air without cancelling upward motion")
	_mouse(MOUSE_BUTTON_RIGHT, false)
	await _ticks(63)
	_check(_player.is_on_floor() and _player.global_position.distance_to(ground) < 0.04,
		"A held Space input lands normally without auto-jumping")
	space = InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.pressed = false
	Input.parse_input_event(space)
	Input.flush_buffered_events()
	_player.combat_enabled = false
	Input.action_press("jump")
	await _ticks(4)
	Input.action_release("jump")
	_check(_player.global_position.y > ground.y + 0.2, "Jump works when combat is disabled")
	_player.combat_enabled = true


func _check_camera_impacts() -> void:
	await _reset()
	var light_aim: Transform3D = _player.get_aim_transform()
	_mouse(MOUSE_BUTTON_LEFT, true)
	_mouse(MOUSE_BUTTON_LEFT, false)
	var light := await _camera_response(30, light_aim.basis.z)
	_check(_damage_hits() == 1 and light.x > 0.10 and light.x < 0.45 and light.y < 0.001,
		"A plain light hit gives a subtle kick with no combat aim change")
	var opening_kick: Vector3 = _player.camera._shake_peak
	await _wait_for_chain_input()
	_mouse(MOUSE_BUTTON_LEFT, true)
	_mouse(MOUSE_BUTTON_LEFT, false)
	await _wait_for_damage_hits(2, 60)
	var returning_kick: Vector3 = _player.camera._shake_peak
	_check(_damage_hits() == 2 and opening_kick.y * returning_kick.y < 0.0
		and opening_kick.z * returning_kick.z < 0.0,
		"The sword's actual opening and returning light traces kick in opposite directions")

	await _reset()
	_player.place_at(_player.global_position, _player.rotation.y + PI, 0.0)
	var whiff_aim: Transform3D = _player.get_aim_transform()
	_mouse(MOUSE_BUTTON_LEFT, true)
	_mouse(MOUSE_BUTTON_LEFT, false)
	var whiff := await _camera_response(45, whiff_aim.basis.z)
	_check(_damage_hits() == 0 and whiff.x < 0.01 and whiff.y < 0.001,
		"A swing through empty air gives no hit shake")

	await _reset()
	var wall := _add_test_wall(1.9)
	await _ticks(2)
	var wall_aim: Vector3 = _player.get_aim_transform().basis.z
	Input.action_press("attack")
	var surface := await _camera_response(90, wall_aim)
	Input.action_release("attack")
	_check(_damage_hits() == 0 and surface.x > 0.35 and surface.x < 1.3 and surface.y < 0.001,
		"A charged weapon meeting stone recoils without landing a hit through the wall or turning aim")
	wall.queue_free()

	await _reset()
	var heavy_aim: Transform3D = _player.get_aim_transform()
	Input.action_press("attack")
	var heavy := await _camera_response(80, heavy_aim.basis.z)
	Input.action_release("attack")
	_check(_damage_hits() == 1 and heavy.x > light.x * 2.2 and heavy.x < 1.5 and heavy.y < 0.001,
		"A real charged strike gives one bounded camera kick without turning the combat aim")
	_check(_player.camera._shake_offset.is_zero_approx(), "The view settles after the charged strike")

	var side: Vector3 = heavy_aim.basis.x
	var down: Vector3 = -heavy_aim.basis.y
	var right_cut := await _sample_weapon_kick("sword_1h", side)
	var left_cut := await _sample_weapon_kick("sword_1h", -side)
	var chop := await _sample_weapon_kick("sword_1h", down)
	_check(right_cut.y < -0.4 and right_cut.z < -0.5 and left_cut.y > 0.4 and left_cut.z > 0.5
		and chop.x < -0.6 and absf(chop.y) < 0.01,
		"Opposite arcs reverse yaw and roll, and a vertical chop primarily pitches the camera")
	var greatsword := await _sample_weapon_kick("sword_2h", side)
	var maul := await _sample_weapon_kick("mace_2h", side)
	_check(greatsword.length() > right_cut.length() * 1.2 and maul.length() > greatsword.length() * 1.12,
		"Two-handed strikes kick harder, with a heavier response for blunt impact")

	await _reset()
	var incoming_aim: Transform3D = _player.get_aim_transform()
	_player.receive_enemy_hit(9.0, "physical", "", _target)
	var incoming := await _camera_response(18, incoming_aim.basis.z)
	_check(incoming.x > heavy.x and incoming.x <= 1.9 and incoming.y < 0.001,
		"A substantial incoming hit has a stronger shake without aim drift")
	_player.receive_enemy_hit(9.0, "physical", "", _target)
	await _ticks(6)
	var incoming_peak: Vector3 = _player.camera._shake_peak
	_player.get_node("CameraFeedback").present_weapon_impact(_target.aim_point(), side, "mace_2h", true, 1, false)
	_check(_player.camera._shake_peak.is_equal_approx(incoming_peak),
		"A weapon contact cannot cut off an incoming hit's recoil")

	await _reset()
	var guard_aim: Transform3D = _player.get_aim_transform()
	_mouse(MOUSE_BUTTON_RIGHT, true)
	_player.receive_enemy_hit(2.0, "physical", "", _target)
	var guard := await _camera_response(14, guard_aim.basis.z)
	_player.restore_stamina(1.0)
	_player.receive_enemy_hit(2.0, "physical", "", _target)
	var broken := await _camera_response(18, guard_aim.basis.z)
	_mouse(MOUSE_BUTTON_RIGHT, false)
	_check(guard.x > 0.20 and guard.x < 0.85 and broken.x > 1.5 and broken.x <= 2.15
		and guard.y < 0.001 and broken.y < 0.001,
		"A successful guard has a small kick and guard break has a distinct heavier kick")

	await _reset()
	var dot_aim: Transform3D = _player.get_aim_transform()
	_player._apply_damage(5.0)
	var dot := await _camera_response(18, dot_aim.basis.z)
	_check(dot.x < 0.01 and dot.y < 0.001, "Damage over time leaves the view steady")


func _camera_response(ticks: int, aim: Vector3) -> Vector2:
	var response := Vector2.ZERO
	for frame in ticks:
		await _ticks(1)
		var current_aim: Transform3D = _player.get_aim_transform()
		response.x = maxf(response.x, rad_to_deg(_player.camera._shake_offset.length()))
		response.y = maxf(response.y, aim.angle_to(current_aim.basis.z))
	return response


func _sample_weapon_kick(weapon: String, travel: Vector3) -> Vector3:
	_player.camera.clear_combat_shake()
	_player.get_node("CameraFeedback").present_weapon_impact(_target.aim_point(), travel, weapon, true, 1, false)
	var peak := Vector3.ZERO
	for _tick in 7:
		await _ticks(1)
		var sample: Vector3 = _player.camera._shake_offset
		if sample.length_squared() > peak.length_squared():
			peak = sample
	return peak * (180.0 / PI)


func _check_world_warnings() -> void:
	_game._reset_training_combat()
	_game.player.place_at(Vector3(0.0, 0.08, -0.75))
	_player.restore_full()
	_game._combat_events.clear()
	_game.training_roster.present()
	_game._spawn_training_enemy(CARRION_BRUTE)
	var brute: CharacterBody3D
	for actor in _game._training_actors.get_children():
		if actor is CharacterBody3D:
			brute = actor
			break
	if not _check(is_instance_valid(brute), "The real Training Ground spawns a Carrion Brute"):
		return
	_mouse(MOUSE_BUTTON_RIGHT, true)
	var starting_life: float = _player.life
	var stamina: float = _player.stamina
	var warned := false
	var slam_landed := false
	for frame in 210:
		await _ticks(1)
		warned = warned or (is_instance_valid(brute._attack_warning) and brute._attack_warning.visible)
		for event: Dictionary in _game._combat_events:
			if event["kind"] == &"damage" and event["ability_id"] == &"butchers_slam":
				slam_landed = true
				break
		if slam_landed:
			break
	_check(warned and slam_landed and _player.is_blocking() and _player.life < starting_life
		and is_equal_approx(_player.stamina, stamina), "The Brute's visible ground warning leads to a hit that bypasses guard")
	_mouse(MOUSE_BUTTON_RIGHT, false)

	_game._reset_training_combat()
	_player.restore_full()
	var hazard := SpikePlate.instantiate() as Node3D
	hazard.configure("spike_plate", 2, _player)
	hazard.position = _player.global_position
	_game._training_actors.add_child(hazard)
	var warnings: Array[String] = []
	hazard.warning_started.connect(func(kind: String, _point: Vector3) -> void: warnings.append(kind))
	_mouse(MOUSE_BUTTON_RIGHT, true)
	starting_life = _player.life
	stamina = _player.stamina
	await _ticks(160)
	_check(warnings == ["spike_plate"] and _player.is_blocking() and _player.life < starting_life
		and is_equal_approx(_player.stamina, stamina), "A telegraphed spike plate damages the guarded player without spending Stamina")
	_mouse(MOUSE_BUTTON_RIGHT, false)


func _reset() -> void:
	_target.max_health = 300.0
	_target.health = _target.max_health
	var point := _target.global_position + Vector3(0.0, 0.06, 1.6)
	var aim: Vector3 = (_target.aim_point() - point - Vector3.UP * 1.56).normalized()
	_player.place_at(point, atan2(-aim.x, -aim.z), asin(aim.y))
	_player.restore_full()
	_game._combat_events.clear()
	await _ticks(2)


func _damage_hits() -> int:
	var total := 0
	for event: Dictionary in _game._combat_events:
		if event["kind"] == &"damage" and event["side"] == &"player":
			total += 1
	return total


func _saw_cancel(reason: String) -> bool:
	for event: Dictionary in _game._combat_events:
		if event["kind"] == &"cast_cancel" and event["side"] == &"player" and event["detail"] == reason:
			return true
	return false


func _mouse(button: MouseButton, pressed: bool) -> void:
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
