extends SceneTree
## Covers native weapon strikes and blocking collision for the new floor props.

const Player := preload("res://player/player.tscn")
const Crate := preload("res://world/modules/breakable_crate.tscn")
const Pottery := preload("res://world/modules/breakable_pottery.tscn")
const Urn := preload("res://world/modules/breakable_urn.tscn")
const Candles := preload("res://world/modules/floor_votive_cluster.tscn")

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
	_stage.free()
	await _ticks(2)
	print("Hearth Below breakable props: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


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


func _aim_at(target: Vector3) -> void:
	var direction := (target - Vector3.UP * 1.56).normalized()
	_player.place_at(Vector3.ZERO, atan2(-direction.x, -direction.z), asin(direction.y))


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

