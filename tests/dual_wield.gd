extends SceneTree
## Drives the real player in the Training Ground and captures weapon-specific hits.

const Game := preload("res://main.tscn")
const Items := preload("res://systems/items.gd")
const WeaponRoles := preload("res://combat/weapons/weapon_roles.gd")

var _player: CharacterBody3D
var _target: CharacterBody3D
var _hits: Array[Dictionary] = []
var _volumes: Array[Vector3] = []
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Node3D = Game.instantiate()
	game.save_enabled = false
	root.add_child(game)
	game.title_screen.training_requested.emit()
	await _ticks(3)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_player = game.player
	game.training_roster.present()
	game._spawn_training_enemy(0)
	for actor in game._training_actors.get_children():
		if actor is CharacterBody3D:
			_target = actor
			_target.set_physics_process(false)
			_target.max_health = 1000.0
			_target.health = 1000.0
			break
	if _check(is_instance_valid(_target), "Training Ground provides the target"):
		_player.struck.connect(_record_hit)
		_player.weapon_trace = _record_volume
		var knife := Items.training_weapon_preview("crypt_knife")
		var sword := Items.training_weapon_preview("oath_blade")
		var mace := Items.training_weapon_preview("pilgrim_cudgel")
		_check(knife.slot == "one_hand" and knife.type == "dagger_1h" and knife.base_stats.damage_min == 1
			and knife.base_stats.damage_max == 2 and Items.canonical_footprint(knife) == Vector2i(1, 2),
			"Crypt Knife starts at 1–2 and fits either hand")
		_check(_light_length(knife) < _light_length(sword) and _light_length(sword) < _light_length(mace),
			"Authored attack cadence makes the dagger faster than the sword and mace")
		_place({"off_hand": knife})
		_check(_player.weapon_type == "dagger_1h" and _player.stats.damage_min == 1.0
			and _player.stats.damage_max == 2.0, "An off-hand-only weapon remains usable without unarmed damage")
		await _strike(1, false, false)
		_check(_hits.size() == 1 and not _volumes.is_empty(), "A solo dagger hits through its actual marked trace")

		# Deliberately distinct fixed ranges expose accidental addition of both hands.
		knife.stats.damage_min = 2
		knife.stats.damage_max = 2
		sword.stats.damage_min = 6
		sword.stats.damage_max = 6
		mace.stats.damage_min = 8
		mace.stats.damage_max = 8
		_place({"main_hand": knife, "off_hand": sword})
		_check(_player._dual_wield and _player.stats.damage_min == 4.0,
			"Weapon pair displays its average base damage")
		await _strike(1, false, false)
		_check(_hit_matches(0, WeaponRoles.MAIN_HAND, 2.0), "Right-hand opener uses only the dagger")
		await _strike(2, false, false)
		_check(_hit_matches(0, WeaponRoles.OFF_HAND, 6.0), "Second light uses only the left-hand sword")
		await _strike(3, false, false)
		_check(_hit_matches(0, WeaponRoles.MAIN_HAND, 2.0), "Light finisher is a single forward lunge")
		await _strike(3, true, false)
		_check(_hits.size() == 2 and _hits[0].clip == &"dual_heavy_3" and _volumes_on_both_sides(),
			"Dual heavy lunge actually sweeps both blades")
		_place({"main_hand": knife, "off_hand": mace})
		await _strike(3, true, false)
		_check(_hits.size() == 2 and _hits[0].clip == &"dual_clash" and _volumes_on_both_sides(),
			"A mace pair crosses both independently traced weapons")
		await _strike(2, true, true)
		_check(_hit_matches(0, WeaponRoles.OFF_HAND, 8.0), "Releasing an off-hand wind-up early uses that hand's light")
		for base_id: String in ["riveted_buckler", "knot_talisman", "clouded_sphere"]:
			_check_support_pose(sword, base_id)
		game.free()
		await _ticks(2)
	print("Hearth Below dual wield: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _place(equipment: Dictionary) -> void:
	_player.update_equipment(equipment)
	var point := _target.global_position + Vector3(0.0, 0.06, 1.60)
	var aim: Vector3 = (_target.aim_point() - point - Vector3.UP * 1.56).normalized()
	_player.place_at(point, atan2(-aim.x, -aim.z), asin(aim.y))
	_player.restore_full()
	_player.stats.crit_chance = 0.0
	_player.stats.mana_regen = 0.0


func _light_length(item: Dictionary) -> float:
	_player.update_equipment({"main_hand": item})
	return _player._weapon.attack_animation(false).length


func _check_support_pose(sword: Dictionary, base_id: String) -> void:
	var held := Items.training_weapon_preview(base_id)
	_place({"main_hand": sword, "off_hand": held})
	var view: Node3D = _player._weapon
	view._process(0.03)
	var idle: Vector3 = view._offhand_pose.position
	view.start_driven_swing(view.attack_clip_name(false, 2), false, 0.42)
	view._process(0.04)
	var swing: Vector3 = view._offhand_pose.position
	_check(swing.x < idle.x - 0.08 and swing.y < idle.y - 0.06,
		"%s tucks down and out of the crossing sword's path (%s → %s)" % [held.name, idle, swing])


func _strike(stage: int, charge: bool, release_early: bool) -> void:
	for frame in range(160):
		if _player._attack_timer <= 0.0 and _player._can_buffer_attack():
			break
		await _ticks(1)
	_target.health = 1000.0
	_hits.clear()
	_volumes.clear()
	_player._next_chain_stage = stage
	_player._chain_time_left = 1.0
	_mouse(true)
	if charge:
		for frame in range(90):
			await _ticks(1)
			if release_early and _player.attack_charge_fraction() > 0.55:
				break
			if not release_early and not _hits.is_empty():
				break
	_mouse(false)
	await _ticks(65)


func _record_hit(enemy: Node3D, amount: float, _critical: bool) -> void:
	if enemy != _target:
		return
	_hits.append({"damage": amount, "hand": _player._strike_hand, "clip": _player._strike_animation})


func _record_volume(pose: Transform3D, _size: Vector3) -> void:
	_volumes.append(_player.get_aim_transform().affine_inverse() * pose.origin)


func _volumes_on_both_sides() -> bool:
	return _volumes.any(func(center: Vector3) -> bool: return center.x < -0.12) \
		and _volumes.any(func(center: Vector3) -> bool: return center.x > 0.12)


func _hit_matches(index: int, hand: StringName, damage: float) -> bool:
	return _hits.size() == 1 and _hits[index].hand == hand and is_equal_approx(_hits[index].damage, damage)


func _mouse(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _ticks(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func _check(condition: bool, name: String) -> bool:
	_checks += 1
	if condition:
		print("PASS  " + name)
	else:
		_failures += 1
		push_error("FAIL  %s | hits: %s | volumes: %d" % [name, _hits, _volumes.size()])
	return condition
