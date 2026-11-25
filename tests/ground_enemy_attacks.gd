extends SceneTree
## Starts the real Training Ground and isolates individual authored cast results.

const Game := preload("res://main.tscn")
const EnemyCatalog := preload("res://combat/enemies/enemy_catalog.gd")

var _game: Node3D
var _player: CharacterBody3D
var _checks := 0
var _failures := 0
var _capture_directory := ""


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-dir="):
			_capture_directory = argument.trim_prefix("--capture-dir=")
	_run.call_deferred()


func _run() -> void:
	_game = Game.instantiate()
	_game.save_enabled = false
	root.add_child(_game)
	_game.title_screen.training_requested.emit()
	await _ticks(3)
	_player = _game.player
	await _check_sigil()
	await _check_snare()
	await _check_conduit()
	if _check(EnemyCatalog.ARCHETYPES.size() > 24 and EnemyCatalog.ARCHETYPES[24].name == "Grave Burrower",
			"Grave Burrower is registered in the live roster"):
		await _check_burrower()
		await _check_burrow_cover()
		await _check_burrow_selection()
	if _check(EnemyCatalog.ARCHETYPES.size() > 27 and EnemyCatalog.ARCHETYPES[27].name == "Crypt Scurrer",
			"Crypt Scurrer is registered in the live roster"):
		await _check_scurrers()
	_game.free()
	await process_frame
	print("Hearth Below ground attacks: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _check_sigil() -> void:
	for outside: bool in [true, false]:
		_place_player(Vector3(0, 0.08, 4))
		var enemy := _spawn(5, Vector3(0, 0.08, -2))
		await _ticks(3)
		_begin_move(enemy, "cinder_sigil", Vector3.BACK)
		var origin: Vector3 = enemy._floor_warning_origin()
		var warning := enemy._attack_warning as MeshInstance3D
		var initial := warning.global_transform
		_check(warning.visible and enemy._attack_ability.unblockable and enemy._windup_total >= 0.80,
			"Cinder Sigil presents a readable fixed floor lane")
		if outside:
			enemy._advance_windup(enemy._windup_total * 0.54, Vector3.BACK)
			await _capture("cinder_sigil_warning")
		_place_player(Vector3(2.3 if outside else 0.0, 0.08, 4))
		enemy._advance_windup(enemy._windup_total, _player.global_position - origin)
		_check(warning.global_transform.is_equal_approx(initial), "The sigil never rotates to follow the player")
		var life: float = _player.life
		_player._set_guard_held(true)
		enemy._release_attack()
		_check(is_equal_approx(_player.life, life) if outside else _player.life < life,
			"Side-stepping avoids the burst" if outside else "Standing in the marked line takes unblockable fire damage")
		_check(not warning.visible and enemy._attack_phase != enemy.AttackPhase.DASH,
			"The caster releases one stationary fire burst and removes the warning")
		if not outside and not _capture_directory.is_empty():
			await _ticks(7)
			await _capture("cinder_sigil_release")
		_player._set_guard_held(false)
		enemy.queue_free()
		await _ticks(2)
	await _check_sigil_cover()


func _check_sigil_cover() -> void:
	_place_player(Vector3(0, 0.08, 4))
	var enemy := _spawn(5, Vector3(0, 0.08, -2))
	await _ticks(3)
	_begin_move(enemy, "cinder_sigil", Vector3.BACK)
	var cover := _close_cover(Vector3(0, 0, 1))
	await _ticks(2)
	enemy._fire_volley()
	_check(is_equal_approx(_player.life, _player.stats.max_health), "A closing door blocks the marked flame line")
	cover.queue_free()
	enemy.queue_free()
	await _ticks(2)


func _check_conduit() -> void:
	_place_player(Vector3(0, 0.08, 4))
	var enemy := _spawn(14, Vector3(0, 0.08, -2))
	await _ticks(3)
	_begin_move(enemy, "soot_conduit", Vector3.BACK)
	_check(enemy._attack_warning.visible and enemy._windup_total >= 1.0,
		"Soot Conduit marks a narrow lane before any damage")
	enemy._advance_windup(enemy._windup_total, Vector3.BACK)
	enemy._release_attack()
	var beam: Node3D = enemy._conduit
	if not _check(is_instance_valid(beam) and not enemy._advance_area_trace(),
			"A real beam occupies the committed casting phase"):
		enemy.queue_free()
		return
	var initial_life: float = _player.life
	await _ticks(20)
	var first_tick: float = _player.life
	_check(first_tick < initial_life and is_instance_valid(beam), "Staying inside the beam takes timed lightning damage")
	await _capture("soot_conduit_active")
	_player.place_at(Vector3(2.1, 0.08, 4))
	await _ticks(18)
	_check(is_equal_approx(_player.life, first_tick), "Leaving the fixed channel avoids the next tick")
	_player.place_at(Vector3(0, 0.08, 4))
	var cover := _close_cover(Vector3(0, 0, 1))
	await _ticks(18)
	_check(is_equal_approx(_player.life, first_tick) and float(beam._footprint.reach) < 3.0,
		"Closing cover clips the beam's visible length and stops its damage")
	cover.queue_free()
	await _ticks(16)
	_check(_player.life < first_tick and is_instance_valid(beam), "Re-entering a clear beam receives the next tick")
	var last_life: float = _player.life
	enemy.take_damage(999.0, "physical", _player)
	await _ticks(25)
	_check(not is_instance_valid(beam) and is_equal_approx(_player.life, last_life),
		"Killing the revenant removes the beam before its next tick")
	enemy.queue_free()
	await _ticks(2)


func _check_snare() -> void:
	_place_player(Vector3(0, 0.08, 5))
	var enemy := _spawn(8, Vector3(0, 0.08, -1))
	await _ticks(3)
	_begin_move(enemy, "rime_snare", Vector3.BACK)
	enemy._advance_windup(enemy._windup_total, Vector3.BACK)
	enemy._release_attack()
	var snare := _game._training_actors.get_node_or_null("RimeSnare") as Node3D
	if not _check(is_instance_valid(snare), "Gutter Marksman throws a real snare"):
		return
	var landing: Vector3 = enemy._snare_destination
	_check(not snare._landed and not snare._armed and is_equal_approx(landing.y, 0.0),
		"The snare flies toward a grounded point before it can arm")
	await _ticks(34)
	_place_player(landing + Vector3.UP * 0.09)
	_check(snare._landed and not snare._armed and not _player._ailments.has("chilled"),
		"The landed snare leaves time to step away before it can trigger")
	if not _capture_directory.is_empty():
		_player.place_at(landing + Vector3(0, 0.08, 1.75), 0.0, -0.61)
		await _ticks(43)
		await _capture("rime_snare_armed")
		_place_player(landing + Vector3.UP * 0.09)
	await _ticks(56)
	_check(not is_instance_valid(snare) and _player._ailments.has("chilled")
		and is_equal_approx(_player.life, _player.stats.max_health), "An armed snare triggers once and slows without damage")
	enemy.queue_free()
	await _ticks(2)


func _check_burrow_cover() -> void:
	_place_player(Vector3(0, 0.08, 4))
	var enemy := _spawn(24, Vector3(0, 0.08, -2))
	await _ticks(3)
	_begin_move(enemy, "grave_tunnel", Vector3.BACK)
	var cover := _close_cover(Vector3(0, 0, 0.6))
	await _ticks(2)
	enemy._advance_windup(enemy._windup_total, Vector3.BACK)
	enemy._release_attack()
	for tick in range(130):
		if enemy._advance_dash(1.0 / 60.0):
			break
		await physics_frame
	_check(not enemy._submerged and enemy.global_position.z < cover.global_position.z,
		"A wall across a committed tunnel causes the burrower to surface on the near side")
	cover.queue_free()
	enemy.queue_free()
	await _ticks(2)


func _close_cover(point: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 3.0, 0.48)
	var body := CollisionShape3D.new()
	body.shape = shape
	body.position.y = 1.5
	wall.add_child(body)
	_game._training_actors.add_child(wall)
	wall.global_position = point
	return wall


func _check_burrow_selection() -> void:
	_place_player(Vector3(0, 0.08, 4))
	var enemy := _spawn(24, Vector3(0, 0.08, -1))
	enemy.set_physics_process(true)
	var chose_tunnel := false
	for tick in range(205):
		if enemy._move_id == "grave_tunnel" and enemy._attack_warning != null and enemy._attack_warning.visible:
			chose_tunnel = true
			break
		await _ticks(1)
	_check(chose_tunnel, "The live enemy brain chooses Grave Tunnel at distance")
	enemy.queue_free()
	await _ticks(2)


func _check_scurrers() -> void:
	_place_player(Vector3(0, 0.08, 4))
	var lead := _spawn(27, Vector3(0, 0.08, -1))
	var flank := _spawn(27, Vector3(2, 0.08, -1))
	await _ticks(2)
	lead._rest_offset = 0.031
	flank._rest_offset = 0.158
	_begin_move(lead, "scurrer_bite", Vector3.BACK)
	_begin_move(flank, "scurrer_bite", Vector3.BACK)
	_check(lead.ability_loadout.size() == 1 and lead._attack_warning == null and flank._attack_warning == null,
		"A scurrer has one ordinary bite and no telegraph decal")
	_check(flank._windup_total - lead._windup_total >= 0.05 and lead.health < 5.0,
		"Weak scurrers use staggered bite timing")
	lead.queue_free()
	flank.queue_free()
	await _ticks(2)


func _check_burrower() -> void:
	_place_player(Vector3(0, 0.08, 4))
	var enemy := _spawn(24, Vector3(0, 0.08, -1))
	await _ticks(3)
	_begin_move(enemy, "grave_tunnel", Vector3.BACK)
	var origin: Vector3 = enemy.global_position
	_check(enemy._attack_warning.visible and enemy._windup_total >= 0.68,
		"Grave Tunnel marks direction before sinking")
	enemy._advance_windup(enemy._windup_total, Vector3.BACK)
	enemy._release_attack()
	var model := enemy.get_node("Model") as Node3D
	var life: float = enemy.health
	enemy.take_damage(8.0, "physical", _player, enemy.aim_point())
	_check(enemy._submerged and not model.visible and is_equal_approx(life, enemy.health),
		"A submerged burrower hides its model and rejects direct contact")
	_place_player(Vector3(2.7, 0.08, 4))
	var reached_mouth := false
	var finished := false
	var delta := 1.0 / 60.0
	for tick in range(160):
		finished = enemy._advance_dash(delta)
		reached_mouth = reached_mouth or (not enemy._submerged and enemy._tunnel_end_warning.visible)
		if finished:
			break
		await physics_frame
	_check(finished and reached_mouth and model.visible and enemy._tunnel_end_warning != null
		and not enemy._tunnel_end_warning.visible and enemy.global_position.z > origin.z + 4.0
		and absf(enemy.global_position.x - origin.x) < 0.02,
		"The burrower surfaces with a warning along its original heading after a side-step")
	_check(is_equal_approx(_player.life, _player.stats.max_health),
		"Standing clear of the emergence disk avoids the attack")
	enemy.queue_free()
	await _ticks(2)


func _spawn(id: int, point: Vector3) -> CharacterBody3D:
	var enemy := EnemyCatalog.instantiate(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 891
	enemy.setup(_player, 1, "normal", rng)
	enemy.configure_encounter(-1, false, 16.0)
	enemy.configure_ai(_game._training_encounter, _game._training_pressure)
	enemy.position = point
	_game._training_actors.add_child(enemy)
	enemy._target = _player
	enemy.set_physics_process(false)
	return enemy


func _begin_move(enemy: CharacterBody3D, id: String, direction: Vector3) -> void:
	enemy._move_id = id
	enemy._profile = enemy._attack_profiles[id]
	enemy._begin_attack(direction)


func _place_player(point: Vector3) -> void:
	_player.place_at(point)
	_player.restore_full()
	_player.stats.dodge_chance = 0.0
	_player.stats.armor = 0.0


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame


func _capture(label: String) -> void:
	if _capture_directory.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var path := _capture_directory.path_join(label + ".png")
	_check(root.get_texture().get_image().save_png(path) == OK, "Captured " + label)


func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if condition:
		print("PASS  " + message)
	else:
		_failures += 1
		push_error("FAIL  " + message)
	return condition
