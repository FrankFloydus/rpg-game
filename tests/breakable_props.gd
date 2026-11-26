extends SceneTree
## Covers native weapon strikes and blocking collision for the new floor props.

const Player := preload("res://player/player.tscn")
const Crate := preload("res://world/modules/breakable_crate.tscn")
const Pottery := preload("res://world/modules/breakable_pottery.tscn")
const Urn := preload("res://world/modules/breakable_urn.tscn")
const Candles := preload("res://world/modules/floor_votive_cluster.tscn")
const Thrall := preload("res://combat/enemies/grave_thrall/grave_thrall.tscn")

var _player: CharacterBody3D
var _stage := Node3D.new()
var _checks := 0
var _failures := 0
var _events := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for action: StringName in [&"forward", &"back", &"left", &"right", &"jump"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	root.add_child(_stage)
	_make_solid(Vector3(0, -0.19, 0), Vector3(16, 0.38, 20))
	_player = Player.instantiate()
	_stage.add_child(_player)
	_player.combat_enabled = true
	_player.update_equipment({"main_hand": {"type": "sword_1h"}})

	var crate := _spawn(Crate, Vector3(0, 0, -1.25))
	_aim_at(crate.aim_point())
	await _ticks(4)
	_check(_hits_solid(crate), "Intact crate blocks movement and line of sight")
	_player.attack(false)
	await _ticks(18)
	_check(_events == 1 and not crate.get_node("Intact").visible, "Normal sword contact shatters the crate once")
	_check(_shards(crate) == 13 and not _hits_solid(crate), "Crate fragments scatter without blocking the player")
	crate.break_from(Vector3.FORWARD)
	_check(_shards(crate) == 13 and _events == 1, "A second hit cannot spawn more fragments")

	var jar := _spawn(Pottery, Vector3(0, 0, -4.2))
	var obstruction := _make_solid(Vector3(0, 0.7, -2.5), Vector3(1.1, 1.8, 0.3))
	_aim_at(jar.aim_point())
	await _ticks(3)
	_player.attack(false)
	await _ticks(19)
	_check(_events == 1 and _hits_solid(obstruction), "A melee strike cannot break a distant jar behind a wall")
	_player.update_equipment({"main_hand": {"type": "staff"}})
	_aim_at(jar.aim_point())
	await _ticks(3)
	_player.attack(false)
	await _ticks(21)
	_check(_events == 1 and jar.get_node("Intact").visible, "A staff bolt cannot shatter a jar through a wall")
	obstruction.free()
	_aim_at(jar.aim_point())
	await _ticks(3)
	_player.attack(false)
	await _ticks(21)
	_check(_events == 2 and _shards(jar) == 14 and not _hits_solid(jar), "An aimed staff bolt shatters pottery at range")

	var urn := _spawn(Urn, Vector3(0, 0, -1.65))
	urn.break_silently()
	_check(_events == 2 and _shards(urn) == 0 and not urn.get_node("Intact").visible,
		"Restoring a broken urn produces no sound event or fragments")
	await process_frame
	_check(not is_instance_valid(urn), "A restored broken urn leaves no collider or visible prop")

	var candles := Candles.instantiate()
	_stage.add_child(candles)
	var emitters := candles.find_children("*", "GPUParticles3D", true, false)
	_check(emitters.size() == 12 and candles.get_node("Candlelight") is OmniLight3D,
		"Four floor candles use the authored GPU flame and share one point light")
	await _test_melee_contact_policy()
	_stage.free()
	await _ticks(2)
	print("Hearth Below breakable props: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _test_melee_contact_policy() -> void:
	_player.update_equipment({"main_hand": {"type": "sword_1h"}})
	var point := Vector3(0, 0, -1.25)
	var stopping_crate := _spawn(Crate, point)
	var continues := await _strike_until_break(stopping_crate)
	_check(not stopping_crate.get_node("Intact").visible and not continues,
		"A default solid crate shatters and ends the active melee sweep")

	var pass_through_crate := _spawn(Crate, point)
	pass_through_crate.melee_hit_through = true
	pass_through_crate.melee_contact_mass = 0.25
	continues = await _strike_until_break(pass_through_crate)
	_check(not pass_through_crate.get_node("Intact").visible and continues,
		"A hit-through crate shatters and leaves the melee sweep active with cleave remaining")

	var heavy_crate := _spawn(Crate, point)
	heavy_crate.melee_hit_through = true
	heavy_crate.melee_contact_mass = 20.0
	continues = await _strike_until_break(heavy_crate)
	_check(not heavy_crate.get_node("Intact").visible and continues,
		"A hit-through crate leaves the sweep active even after spending its cleave budget")

	var protected_crate := _spawn(Crate, point)
	protected_crate.allow_melee_damage = false
	await _strike_until_break(protected_crate)
	_check(protected_crate.get_node("Intact").visible and _hits_solid(protected_crate),
		"A crate with melee damage disabled remains intact and blocking after a real sword attack")

	_player.stats.merge({"damage_min": 2.0, "damage_max": 2.0, "crit_chance": 0.0}, true)
	var light_prop_damage := await _strike_through_prop(0.25)
	_check(light_prop_damage > 0.0, "The same swing hits an actor after breaking a light hit-through prop")
	var heavy_prop_damage := await _strike_through_prop(20.0)
	_check(is_zero_approx(heavy_prop_damage), "A heavy hit-through prop exhausts cleave before the actor behind it")


func _strike_through_prop(mass: float) -> float:
	var start := Vector3(3, 0, 0)
	var enemy := Thrall.instantiate() as CharacterBody3D
	var rng := RandomNumberGenerator.new()
	rng.seed = 45021
	enemy.setup(_player, 1, "normal", rng)
	enemy.position = start + Vector3.FORWARD * 1.57
	_stage.add_child(enemy)
	enemy.set_physics_process(false)
	var crate := _spawn(Crate, start + Vector3.FORWARD * 1.06)
	crate.scale = Vector3(0.75, 1.72, 0.65)
	crate.melee_hit_through = true
	crate.melee_contact_mass = mass
	var break_health: Array[float] = []
	crate.broken.connect(func() -> void: break_health.append(enemy.health))
	var life: float = enemy.health
	_aim_at(enemy.aim_point() - Vector3.UP * 0.26, start)
	await _ticks(4)
	_player.attack(false)
	await _ticks(30)
	_check(break_health.size() == 1 and is_equal_approx(break_health[0], life),
		"A hit-through prop receives one contact before the covered enemy")
	var damage: float = life - enemy.health
	crate.free()
	enemy.free()
	return damage


func _strike_until_break(prop: StaticBody3D) -> bool:
	_aim_at(prop.aim_point())
	await _ticks(4)
	_player.attack(false)
	for _tick in range(18):
		await physics_frame
		if not prop.get_node("Intact").visible:
			return _player.get("_strike_pending") == true
	return false


func _spawn(scene: PackedScene, point: Vector3) -> StaticBody3D:
	var prop: StaticBody3D = scene.instantiate()
	prop.position = point
	prop.broken.connect(func() -> void: _events += 1)
	_stage.add_child(prop)
	return prop


func _make_solid(point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = point
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	_stage.add_child(body)
	return body


func _aim_at(target: Vector3, origin := Vector3.ZERO) -> void:
	var direction := (target - origin - Vector3.UP * 1.56).normalized()
	_player.place_at(origin, atan2(-direction.x, -direction.z), asin(direction.y))


func _hits_solid(expected: StaticBody3D) -> bool:
	var origin: Vector3 = _player.camera.global_position
	var forward: Vector3 = -_player.camera.global_basis.z
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + forward * 8.0, 1)
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.get("collider") == expected


func _shards(prop: Node3D) -> int:
	return prop.find_children("*", "RigidBody3D", false, false).size()


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)

