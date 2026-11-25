extends SceneTree
## Covers the Wax Brood's auxiliary hit lifecycle and the Legate's one-shot summon.

const Game := preload("res://main.tscn")
const Catalog := preload("res://combat/enemies/enemy_catalog.gd")
const Waxling := preload("res://combat/enemies/wax_brood/waxling.gd")

var _game: Node3D
var _player: CharacterBody3D
var _checks := 0
var _failures := 0
var _summons := 0
var _corpse: Node3D
var _reclaims := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_game = Game.instantiate()
	_game.save_enabled = false
	root.add_child(_game)
	_game.title_screen.training_requested.emit()
	await _ticks(5)
	_player = _game.player
	await _waxling_hit_and_evade(false)
	await _waxling_hit_and_evade(true)
	await _waxling_interruption()
	await _legate(false)
	await _legate(true)
	await _reclaimer(false)
	await _reclaimer(true)
	_game.free()
	await _ticks(2)
	print("Wax Brood and grave caster combat: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _waxling_hit_and_evade(evade: bool) -> void:
	var brood := await _spawn(22)
	_check(await _wait_for(&"cast_end", &"kindle_brood", 160), "Wax Brood hatches its own clutch in regular AI")
	var clutch: Array = brood._waxlings
	if not _check(clutch.size() == 2 and not clutch[0].is_in_group(&"enemies"),
			"Up to two strikeable waxlings belong to the caster rather than the encounter roster"):
		return
	_check(await _wait_for(&"cast_start", &"waxling_flare", 190), "A waxling stops and lights a fuse after pursuing")
	var warnings := get_nodes_in_group(Waxling.HAZARD_GROUP)
	if not _check(warnings.size() == 1, "A clutch never marks two flares simultaneously"):
		return
	var armed := warnings[0] as Waxling
	var committed := armed.global_position
	var life: float = _player.life
	var exit_point := committed + Vector3.RIGHT * 2.15 if evade else committed + Vector3.BACK * 0.48
	_player.place_at(exit_point + Vector3.UP * 0.08)
	_player._set_guard_held(true)
	await _ticks(10)
	_check(armed.global_position.is_equal_approx(committed) and armed._warning.visible,
		"The active red warning stays on the committed spot")
	_check(await _wait_for(&"cast_end", &"waxling_flare", 85), "The fuse resolves once")
	_check(is_equal_approx(_player.life, life) if evade else _player.life < life,
		"Stepping clear avoids the flare" if evade else "A flare inside the warning bypasses block")
	_player._set_guard_held(false)
	brood.queue_free()
	await _ticks(3)
	_check(get_nodes_in_group(Waxling.HAZARD_GROUP).is_empty(), "Unloading the hive frees all of its warnings")


func _waxling_interruption() -> void:
	var brood := await _spawn(22)
	if not _check(await _wait_for(&"cast_start", &"waxling_flare", 350), "A later clutch begins a fresh fuse"):
		return
	var armed := get_first_node_in_group(Waxling.HAZARD_GROUP) as Waxling
	var hit_point := armed.aim_point()
	armed.break_from(Vector3.FORWARD, hit_point)
	_check(_saw(&"cast_cancel", &"waxling_flare") and not armed.is_in_group(Waxling.HAZARD_GROUP),
		"Striking the hatchling cancels the fuse immediately")
	brood.take_damage(1000.0)
	await _ticks(50)
	_check(not _saw(&"cast_end", &"waxling_flare") and get_nodes_in_group(Waxling.HAZARD_GROUP).is_empty(),
		"The hive's death extinguishes its surviving brood without a blast")


func _legate(interrupt: bool) -> void:
	var legate := await _spawn(25, 25, "magic")
	_summons = 0
	legate.summon_requested.connect(func(_enemy: Node3D) -> void: _summons += 1)
	_check(legate.health == 1.0 and legate.max_health == 1.0, "A scaled magic Legate still has exactly 1 Life")
	if not _check(await _wait_for(&"cast_start", &"raise_the_levy", 130), "Legate starts its invocation in regular AI"):
		return
	if interrupt:
		legate.take_damage(1000.0)
	else:
		_check(not legate.receive_stun_impact(1000.0, legate) and not legate.is_stunned(),
			"Even overwhelming stun buildup cannot stop the invocation")
		var cover := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(3.0, 2.8, 0.3)
		collision.shape = shape
		cover.add_child(collision)
		_game._training_actors.add_child(cover)
		cover.global_position = legate.global_position.lerp(_player.global_position, 0.5) + Vector3.UP * 1.4
		await _ticks(2)
		_check(not legate._has_sight(), "Real world cover cuts sight during the invocation")
	await _ticks(195)
	_check(_saw(&"cast_cancel", &"raise_the_levy") and _summons == 0 if interrupt else
		_saw(&"cast_end", &"raise_the_levy") and _summons == 1 and not is_instance_valid(legate),
		"Killing the Legate prevents the summons" if interrupt else "A completed invocation emits one summons and removes the Legate")


func _reclaimer(interrupt: bool) -> void:
	var reclaimer := await _spawn(26, 5)
	_reclaims = 0
	reclaimer.configure_revival(func(_caster: Node3D, _max_range: float) -> Node3D: return _corpse,
		func(_caster: Node3D, target: Node3D) -> bool:
			if target != _corpse:
				return false
			_reclaims += 1
			_corpse.queue_free()
			_corpse = null
			return true)
	await _ticks(30)
	_check(not _saw(&"cast_start", &"raise_the_fallen"), "Reclaimer does not cast without a corpse")
	_corpse = Node3D.new()
	_corpse.name = "Fallen Sentry"
	_game._training_actors.add_child(_corpse)
	_corpse.global_position = Vector3(1.8, 0.05, 2.25)
	if not _check(await _wait_for(&"cast_start", &"raise_the_fallen", 90),
			"Reclaimer starts the channel after finding a corpse"):
		return
	_check(reclaimer._beam.visible and reclaimer._motes.global_position.distance_to(_corpse.global_position) < 0.22,
		"The ritual visibly terminates at the locked corpse")
	if interrupt:
		_check(reclaimer.receive_stun_impact(1000.0, reclaimer), "The Reclaimer can be stunned during the ritual")
		_check(await _wait_for(&"cast_cancel", &"raise_the_fallen", 24) and not reclaimer._beam.visible
			and _reclaims == 0, "Stun closes the ritual without raising a corpse")
		_corpse.queue_free()
		_corpse = null
	else:
		_check(await _wait_for(&"cast_end", &"raise_the_fallen", 155) and _reclaims == 1,
			"An uninterrupted ritual completes the revival exactly once")


func _spawn(id: int, level := 4, rarity := "normal") -> CharacterBody3D:
	_game._reset_training_combat()
	_game._combat_events.clear()
	_player.place_at(Vector3(0.0, 0.08, 5.2))
	_player.restore_full()
	_player.stats.dodge_chance = 0.0
	var enemy := Catalog.instantiate(id)
	var rng := RandomNumberGenerator.new()
	rng.seed = 531
	enemy.setup(_player, level, rarity, rng, Callable(_game.training_ground, "navigation_route"))
	enemy.position = Vector3(0.0, 0.08, -1.2)
	enemy.configure_encounter(0, false, 16.0)
	enemy.configure_ai(_game._training_encounter, _game._training_pressure)
	enemy.combat_event.connect(_game._record_combat_event)
	enemy._decision_time = 0.0
	_game._training_actors.add_child(enemy)
	await _ticks(2)
	return enemy


func _wait_for(kind: StringName, ability: StringName, ticks: int) -> bool:
	for index in ticks:
		if _saw(kind, ability):
			return true
		await _ticks(1)
	return _saw(kind, ability)


func _saw(kind: StringName, ability: StringName) -> bool:
	for event: Dictionary in _game._combat_events:
		if event.get("kind") == kind and event.get("ability_id") == ability:
			return true
	return false


func _ticks(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame


func _check(condition: bool, message: String) -> bool:
	_checks += 1
	if condition:
		print("PASS  " + message)
	else:
		_failures += 1
		push_error(message)
	return condition
