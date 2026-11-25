extends SceneTree
## Checks partial charged attacks against the live Training Ground viewmodel.

const Game := preload("res://main.tscn")
const WEAPON_TYPES := ["unarmed", "sword_1h", "axe_1h", "mace_1h", "sword_2h", "axe_2h", "mace_2h", "staff"]
const THREE_STAGE_WEAPONS := ["axe_1h", "axe_2h", "mace_2h", "sword_2h"]

var _game: Node3D
var _player: CharacterBody3D
var _view: Node3D
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_game = Game.instantiate()
	_game.save_enabled = false
	root.add_child(_game)
	current_scene = _game
	_game.title_screen.training_requested.emit()
	await _ticks(3)
	_player = _game.player
	_view = _player._weapon
	for weapon_type: String in WEAPON_TYPES:
		await _check_release(weapon_type)
	for weapon_type: String in THREE_STAGE_WEAPONS:
		await _check_release(weapon_type, 2)
		await _check_release(weapon_type, 3)
	await _check_release("sword_1h", 2)
	await _check_release("axe_2h", 1, 0.36)
	await _check_release("axe_2h", 1, 0.74)
	await _check_unavailable_light()
	await _check_interruptions()
	await _check_render_substeps()
	_game.free()
	await process_frame
	print("Hearth Below charge return: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_release(weapon_type: String, chain_stage := 1, release_fraction := 0.0) -> void:
	await _prepare(weapon_type)
	_player._next_chain_stage = chain_stage
	_player._chain_time_left = 1.0
	var label := "%s charge %d" % [weapon_type, chain_stage]
	var light: AbilityDefinition = _player._weapon_attack_ability(false)
	var heavy: AbilityDefinition = _player._weapon_attack_ability(true)
	var light_clip: StringName = _view.attack_clip_name(false, chain_stage)
	# Exercise the real movement/sway lane on both a shield user and large weapons.
	var strafe_after_start := weapon_type in THREE_STAGE_WEAPONS
	var walking := strafe_after_start or weapon_type == "sword_1h" or weapon_type.ends_with("2h")
	if walking and not strafe_after_start:
		Input.action_press("right")
	var start: Vector3 = _player.position
	var mana: float = _player.mana
	_game._combat_events.clear()
	var release_threshold := 0.84 if weapon_type.ends_with("2h") else 0.57
	if weapon_type.begins_with("axe_"):
		release_threshold = 0.90
	if release_fraction > 0.0:
		release_threshold = release_fraction
		label += " at %d%%" % roundi(release_fraction * 100.0)
	await _hold_partial_charge(release_threshold, strafe_after_start)
	var progress: float = _view.rendered_charge_fraction()
	_release_charge()
	var entry_time: float = _player._current_clip_time() if _player._strike_clip != null else -1.0
	_check(_player._strike_pending and _player._strike_ability == light and not _player._strike_heavy
		and _player._strike_animation == light_clip and _player._strike_chain_stage == chain_stage
		and is_zero_approx(_view._transition_remaining) and _view._main_charge_return == null,
		label + " releases immediately into the selected light attack without a transition blend")
	_check(entry_time > 0.0 and entry_time < _player._strike_clip.trace_start
		and is_equal_approx(entry_time, progress * 0.85 * _player._strike_clip.trace_start)
		and not _player._clip_released and is_equal_approx(_player.mana, mana),
		label + " retains partial anticipation and leaves the damage window unopened")
	_view._process(0.0)
	_check(_view._main_animation.current_animation == light_clip
		and is_equal_approx(_view._main_animation.current_animation_position, entry_time)
		and (_view._offhand_animation == null or (_view._offhand_animation.current_animation == &"light"
			and _view._offhand_handoff_remaining > 0.0)),
		label + " presents the same authored motion and phase before the next physics tick")
	await _ticks(70)
	Input.action_release("right")
	var travel: float = _player.position.distance_to(start)
	_check(_cast_events() == [[heavy.id, &"cast_start"], [heavy.id, &"cast_cancel"],
			[light.id, &"cast_start"], [light.id, &"cast_end"]]
		and not _player._strike_pending and is_equal_approx(_player.mana, mana) and (not walking or travel > 0.3),
		label + " completes only one light, spends no heavy Mana, and resumes movement")


func _check_unavailable_light() -> void:
	await _prepare("sword_1h")
	_player._next_chain_stage = 2
	_player._chain_time_left = 1.0
	var normal_light: AbilityDefinition = _player._weapon_attack_ability(false)
	var unavailable := normal_light.duplicate() as AbilityDefinition
	var mana: float = _player.mana
	unavailable.mana_cost = mana + 1.0
	_player.light_ability_override = unavailable
	var heavy: AbilityDefinition = _player._weapon_attack_ability(true)
	await _hold_partial_charge()
	var hands := _capture_view_pose()
	_release_charge()
	_check(_view._main_charge_return != null and _view._main_charge_return._charge == &"charge_2"
		and _view._offhand_charge_return != null and _view._offhand_charge_return._charge == &"charge",
		"An unavailable light returns along the selected alternate charge and shield pose")
	_view._process(0.0)
	var release_pose := _capture_view_pose()
	var release_step := _position_step(hands, release_pose)
	var release_angle := _rotation_step(hands, release_pose)
	# The moving shield's sleeve is pinned again after applying continuous sway.
	_check(release_step < 0.004 and release_angle < 0.002,
		"Unavailable light preserves the rendered grip, shoulder and elbow at release (%.5fm, %.4frad)" %
		[release_step, release_angle])
	var largest_step := 0.0
	var largest_turn := 0.0
	var previous := hands
	for frame in range(36):
		await _ticks(1)
		var current := _capture_view_pose()
		largest_step = maxf(largest_step, _position_step(previous, current))
		largest_turn = maxf(largest_turn, _rotation_step(previous, current))
		previous = current
		if _view._main_charge_return == null:
			break
	var settled_pose := _capture_view_pose()
	_view._process(0.0)
	var idle_pose := _capture_view_pose()
	_check(_position_step(settled_pose, idle_pose) < 0.004 and _rotation_step(settled_pose, idle_pose) < 0.002,
		"The unavailable-light fallback meets live idle without a final-frame jump")
	_check(not _player._strike_pending and is_equal_approx(_player.mana, mana)
		and _cast_events() == [[heavy.id, &"cast_start"], [heavy.id, &"cast_cancel"]],
		"The unavailable light never starts a cast or spends Mana")
	_check(_view._main_charge_return == null and _view._main_animation.current_animation == &"idle"
		and largest_step < 0.16 and largest_turn < deg_to_rad(25.0),
		"The unavailable-light recovery settles smoothly (%.3fm max step, %.1f° max turn)" %
		[largest_step, rad_to_deg(largest_turn)])
	_player.light_ability_override = null


func _check_interruptions() -> void:
	await _prepare("sword_1h")
	await _hold_partial_charge()
	_mouse(MOUSE_BUTTON_RIGHT, true)
	_check(_player.is_blocking() and not _player._strike_pending and _view._main_charge_return == null,
		"RMB takes priority immediately and interrupts the charge without releasing a strike")
	_release_charge()
	_mouse(MOUSE_BUTTON_RIGHT, false)
	await _prepare("mace_2h")
	await _hold_partial_charge()
	_player.gameplay_enabled = false
	_release_charge()
	_check(not _player._strike_pending and _view._main_charge_return == null,
		"Pause cancels the charge without starting a light attack")
	_player.gameplay_enabled = true
	await _ticks(2)
	await _hold_partial_charge()
	_player.update_equipment({"main_hand": {"type": "staff"}})
	_release_charge()
	_check(not _player._strike_pending and _view._main_charge_return == null and _view._type == "staff",
		"Equipment swap ends the charge without releasing a light attack")


func _check_render_substeps() -> void:
	await _prepare("sword_1h")
	_player.set_physics_process(false)
	# Widen the interval for the fixture so headless fixed-FPS and uncapped rendering can sample it.
	var previous_rate := Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 10
	_view.start_driven_swing(&"light", false, 0.15, true)
	_view.set_swing_phase(0.45)
	var last_tick := -1
	var last_phase := 0.0
	var between_samples := false
	for frame in 48:
		await process_frame
		_view._process(0.0)
		var phase: float = _view._display_phase
		var tick := Engine.get_physics_frames()
		if tick == last_tick and phase > last_phase + 0.001 and phase < 0.45:
			between_samples = true
			break
		last_phase = phase
		last_tick = tick
	Engine.physics_ticks_per_second = previous_rate
	_view.cancel_swing()
	_player.set_physics_process(true)
	_check(between_samples, "The authored display phase advances across render frames between the same two physics samples")


func _prepare(weapon_type: String) -> void:
	var equipment: Dictionary = {}
	if weapon_type != "unarmed":
		equipment["main_hand"] = {"type": weapon_type}
	if weapon_type == "sword_1h":
		equipment["off_hand"] = {"type": "shield"}
	_player.update_equipment(equipment)
	_player.restore_full()
	_player.place_at(_game.training_ground.spawn_position, _game.training_ground.spawn_yaw)
	await _ticks(4)
	_game._combat_events.clear()


func _hold_partial_charge(minimum := 0.57, strafe_after_start := false) -> void:
	_mouse(MOUSE_BUTTON_LEFT, true)
	for frame in range(64):
		await _ticks(1)
		# These weapons take their side from movement at charge start. Start neutral to
		# exercise the selected chain stage, then strafe throughout the return.
		if strafe_after_start and _view._rendered_charge_phase > 0.0:
			Input.action_press("right")
			strafe_after_start = false
		if _player.attack_charge_fraction() > 0.0 and _view._rendered_charge_phase >= minimum:
			return
	_check(false, "A partial charge pose appears before commitment (gameplay %s, input %s, charge %.3f)" %
		[_player.gameplay_enabled, Input.is_action_pressed("attack"), _player.attack_charge_fraction()])


func _release_charge() -> void:
	_mouse(MOUSE_BUTTON_LEFT, false)


func _mouse(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _cast_events() -> Array[Array]:
	var result: Array[Array] = []
	for event: Dictionary in _game._combat_events:
		if event["side"] == &"player" and String(event["kind"]).begins_with("cast_"):
			result.append([event["ability_id"], event["kind"]])
	return result


func _capture_view_pose() -> Array[Transform3D]:
	var poses: Array[Transform3D] = []
	var camera_space: Transform3D = _view.global_transform.affine_inverse()
	for animator in [_view._main_animation, _view._offhand_animation]:
		if animator == null:
			continue
		var item: Node = animator.get_parent()
		poses.append(camera_space * item.get_node("Pose").global_transform)
		for anchor in [^"RightShoulder", ^"LeftShoulder"]:
			var shoulder := item.get_node_or_null(anchor) as Node3D
			if shoulder != null:
				poses.append(camera_space * shoulder.global_transform)
		var skeleton := item.find_child("Skeleton3D", true, false) as Skeleton3D
		if skeleton != null:
			for name_key in ["Right Elbow", "Left Elbow"]:
				var bone := skeleton.find_bone(name_key)
				if bone >= 0:
					poses.append(camera_space * skeleton.global_transform * skeleton.get_bone_global_pose(bone))
	return poses


func _position_step(first: Array[Transform3D], second: Array[Transform3D]) -> float:
	var distance := 0.0
	for index in first.size():
		distance = maxf(distance, first[index].origin.distance_to(second[index].origin))
	return distance


func _rotation_step(first: Array[Transform3D], second: Array[Transform3D]) -> float:
	var angle := 0.0
	for index in first.size():
		angle = maxf(angle, first[index].basis.get_rotation_quaternion().angle_to(
			second[index].basis.get_rotation_quaternion()))
	return angle


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
