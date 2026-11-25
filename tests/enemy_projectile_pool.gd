extends SceneTree
## Checks actual raycast hits, sustained GPU retirement and room-owned reuse.

const Game := preload("res://main.tscn")
const Projectile := preload("res://combat/effects/enemy_projectile.gd")
const Pool := preload("res://combat/effects/enemy_projectile_pool.gd")
const Catalog := preload("res://combat/enemies/enemy_catalog.gd")

var _game: Node
var _caster: CharacterBody3D
var _owner: Node3D
var _checks := 0
var _failed := 0
var _traces: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_game = Game.instantiate()
	_game.save_enabled = false
	root.add_child(_game)
	_game.title_screen.training_requested.emit()
	await _ticks(3)
	_owner = _game._training_actors
	_caster = Catalog.instantiate(1)
	var affixes: Array[String] = []
	_game._prepare_training_enemy(_caster, 1, "normal", affixes, Vector3(0.0, 0.08, -2.6))
	_caster.set_physics_process(false)
	_caster.set_ability_trace(_traces.append)
	_caster._attack_ability = _caster._cast_definition().combat_details()
	await _check_native_ranged_shot()
	await _check_magical_fade()
	await _check_range_and_clock()
	var retained := await _check_burst_and_cap()
	_game.queue_free()
	await _ticks(3)
	_check(retained.all(func(id: int) -> bool: return not is_instance_id_valid(id)),
		"Removing the training scene also frees every detached pooled projectile")
	print("enemy_projectile_pool: %d/%d checks passed" % [_checks - _failed, _checks])
	quit(1 if _failed > 0 else 0)


func _check_native_ranged_shot() -> void:
	_game.player.place_at(Vector3(0.0, 0.08, 1.5))
	_game.player.restore_full()
	_game.player.stats.dodge_chance = 0.0
	var before: float = _game.player.life
	await _ticks(2)
	var start := Vector3(0.0, 0.92, -0.4)
	_caster._spawn_projectile(start, Vector3.BACK)
	var shot := _active_shot()
	if not _check(shot != null and shot.in_flight() and shot._arrow.visible,
			"The live archer path creates an active physical projectile under the encounter owner"):
		return
	await _ticks(25)
	_check(_game.player.life < before and _traces.size() == 1 and _traces[0].hit,
		"The pooled projectile uses the real player collision and records one hit")
	_check(not shot.is_inside_tree() and not shot.in_flight() and shot._source == null
		and shot._player == null and shot._ability.is_empty() and not shot._trace.is_valid(),
		"Retirement removes the idle node and releases combat references")
	_caster._spawn_projectile(start, Vector3.BACK)
	_check(_active_shot() == shot and shot._source.get_ref() == _caster and shot._trace.is_valid(),
		"The next real shot reuses the same node with fresh combat data")
	await _ticks(25)
	_check(_traces.size() == 2, "A reused projectile reports only its own collision")


func _check_magical_fade() -> void:
	var shot := Pool.take(_owner) as Projectile
	_launch_short(shot, "cold")
	_check(shot._bolt.visible and not shot._arrow.visible and shot._trail.emitting,
		"A reused projectile selects its current elemental core and GPU trail")
	await _ticks(3)
	_check(shot.is_inside_tree() and not shot.in_flight() and not shot._core.visible
		and not shot._trail.emitting and shot._fade_remaining > 0.0 and shot._trail.get_parent() == shot._bolt,
		"The finished bolt leaves its authored GPU particles in place while the core is retired")
	var second := Pool.take(_owner) as Projectile
	_check(second != shot, "A projectile with a fading GPU trail cannot be reused yet")
	_launch_short(second, "physical")
	await _ticks(26)
	var pool := _owner.get_node(NodePath(Pool.POOL_NAME))
	_check(pool._available.has(shot) and pool._available.has(second),
		"Both variants return to the owner only after their visual lifetime")


func _check_range_and_clock() -> void:
	var trace: Array[Dictionary] = []
	var origin := Vector3(-3.0, 1.15, -0.30)
	var exact_range := 0.25
	var shot := Pool.take(_owner) as Projectile
	shot.launch(origin, origin + Vector3.FORWARD, 12.0, 1.0, "physical", "",
		_caster, _game.player, Color.WHITE, exact_range, {}, trace.append)
	await _ticks(4)
	_check(trace.size() == 1 and is_equal_approx(origin.distance_to(trace[0].end), exact_range),
		"Expiry records the full authored distance, including the final partial physics tick")

	var wall := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.30, 0.30, 0.01)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	wall.position = origin + Vector3.FORWARD * 0.24
	wall.add_child(collision)
	_owner.add_child(wall)
	await _ticks(2)
	trace.clear()
	shot = Pool.take(_owner) as Projectile
	shot.launch(origin, origin + Vector3.FORWARD, 12.0, 1.0, "physical", "",
		_caster, _game.player, Color.WHITE, exact_range, {}, trace.append)
	await _ticks(4)
	_check(trace.size() == 1 and is_equal_approx(origin.distance_to(trace[0].end), 0.235),
		"A wall reached in the final partial physics tick still intercepts the shot")
	wall.queue_free()
	await _ticks(2)

	trace.clear()
	shot = Pool.take(_owner) as Projectile
	shot.launch(origin, origin + Vector3.FORWARD, 12.0, 1.0, "physical", "",
		_caster, _game.player, Color.WHITE, 2.4, {}, trace.append)
	_owner.process_mode = Node.PROCESS_MODE_DISABLED
	await _ticks(9)
	_check(shot.global_position.is_equal_approx(origin) and shot.in_flight(),
		"Suspending the encounter owner freezes both the shot's position and lifetime")
	var original_speed := Engine.time_scale
	Engine.time_scale = 0.075
	_owner.process_mode = Node.PROCESS_MODE_INHERIT
	await _ticks(12)
	var slow_motion_travel := origin.distance_to(shot.global_position)
	_check(slow_motion_travel > 0.14 and slow_motion_travel < 0.21 and shot.in_flight(),
		"The card hand's 7.5 percent world speed slows the shot's flight and lifetime together")
	Engine.time_scale = original_speed
	await _ticks(15)
	_check(trace.size() == 1 and is_equal_approx(origin.distance_to(trace[0].end), 2.4),
		"Restoring world speed completes exactly the remainder of the same projectile")


func _check_burst_and_cap() -> Array[int]:
	var shots: Array[Node3D] = []
	for count in Pool.MAX_RETAINED + 6:
		var shot := Pool.take(_owner) as Projectile
		_launch_short(shot, "physical")
		shots.append(shot)
	var identities: Array[int] = []
	for shot in shots:
		identities.append(shot.get_instance_id())
	_check(identities.size() == Pool.MAX_RETAINED + 6
		and shots.all(func(shot: Node3D) -> bool: return shot.in_flight())
		and not _has_duplicate_id(identities), "An oversize volley retains every in-flight shot")
	await _ticks(6)
	var pool := _owner.get_node(NodePath(Pool.POOL_NAME))
	_check(pool._available.size() == Pool.MAX_RETAINED,
		"Finished shots are retained only up to the fixed owner capacity")
	return identities


func _has_duplicate_id(ids: Array[int]) -> bool:
	var found := {}
	for id in ids:
		if found.has(id):
			return true
		found[id] = true
	return false


func _launch_short(shot: Node3D, element: String) -> void:
	var start := Vector3(-1.7, 1.15, -0.3)
	shot.launch(start, start + Vector3.FORWARD, 12.0, 1.0, element, "",
		_caster, _game.player, Color("#8bdbe9"), 0.12, {"id": &"pool_fixture"})


func _active_shot() -> Projectile:
	for child in _owner.get_children():
		if child is Projectile and child.in_flight():
			return child
	return null


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame


func _check(condition: bool, description: String) -> bool:
	_checks += 1
	if condition:
		print("PASS " + description)
	else:
		_failed += 1
		printerr("FAIL " + description)
	return condition
