extends SceneTree
## Exercises the committed disc, obstacle interception and repeated poison contacts.

const Pod := preload("res://combat/effects/mire_spore_pod.tscn")
const SporeLob := preload("res://combat/abilities/mire_spore_lob.tres")

class Target extends Node3D:
	var gameplay_enabled := true
	var combat_enabled := true
	var hits: Array[Dictionary] = []

	func receive_ground_damage(amount: float, damage_type: String,
			_source: Node3D, ability: Dictionary) -> bool:
		hits.append({"amount": amount, "type": damage_type, "ability": ability})
		return true

var _stage := Node3D.new()
var _target := Target.new()
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.add_child(_stage)
	_stage.add_child(_target)
	_build_static(Vector3(0.0, -0.20, 0.0), Vector3(18.0, 0.4, 18.0))
	await _ticks(3)
	var center := Vector3(1.7, 0.0, 0.0)
	_target.position = center + Vector3.FORWARD * 2.0
	var pod := _launch(center, 1.0)
	var warning := pod._warning as MeshInstance3D
	var pool := pod.get_node("GroundPool") as MeshInstance3D
	var shell := pod.get_node("Pod") as Node3D
	var launch := shell.global_position
	await _ticks(29)
	_check(warning.visible and warning.global_position.is_equal_approx(center + Vector3.UP * 0.063)
		and is_equal_approx(warning.scale.x, SporeLob.pool_radius),
		"The full warning stays on the originally committed floor disc")
	_check(shell.global_position.y > launch.y and warning.get_instance_shader_parameter(&"windup") > 0.64,
		"The visible pod rises on an arc as the original warning fills")
	await _ticks(34)
	_check(not warning.visible and pool.visible and not shell.visible and _target.hits.is_empty(),
		"Leaving the disc avoids the impact, then the warning becomes a visible pool")
	_target.position = center + Vector3(0.0, 1.1, 0.0)
	await _ticks(46)
	_check(_target.hits.is_empty(), "The pool does not hit someone above its floor")
	_target.position = center + Vector3(0.35, 0.08, -0.17)
	await _ticks(83)
	var proper_ticks := _target.hits.all(func(hit: Dictionary) -> bool:
		return (is_equal_approx(hit.amount, 8.0 * SporeLob.tick_damage_multiplier)
			and hit.type == "poison" and hit.ability.unblockable and hit.ability.id == SporeLob.id)
	)
	_check(_target.hits.size() >= 2 and proper_ticks,
		"Standing in spores applies repeated attributable, unblockable Poison ticks")
	_target.position = center + Vector3.RIGHT * 2.0
	var before := _target.hits.size()
	await _ticks(125)
	_check(_target.hits.size() == before and not is_instance_valid(pod),
		"Leaving the pool stops damage and the expired pool frees itself")
	_target.position = center
	var obstacle := _build_static(Vector3(0.0, 1.20, 0.0), Vector3(0.22, 2.4, 3.0))
	await _ticks(3)
	pod = _launch(center, 0.8)
	await _ticks(52)
	_check(not is_instance_valid(pod) and _target.hits.size() == before,
		"A world obstacle intercepts the pod before the warned floor can take damage")
	obstacle.queue_free()
	await _ticks(3)
	_target.position = center
	pod = _launch(center, 0.6)
	await _ticks(38)
	_check(_target.hits.size() == before + 1 and is_equal_approx(_target.hits.back().amount, 8.0),
		"The original marked center takes full burst damage at landing")
	_stage.free()
	print("Mire Censer Spore Lob: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


func _launch(center: Vector3, duration: float) -> Node3D:
	var pod := Pod.instantiate() as Node3D
	_stage.add_child(pod)
	var ability: Dictionary = SporeLob.combat_details()
	ability["unblockable"] = true
	pod.launch(SporeLob, Vector3(-2.3, 0.82, 0.0), center, duration, 0.35,
		8.0, _stage, _target, ability, Callable())
	return pod


func _build_static(point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = point
	_stage.add_child(body)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	return body


func _ticks(count: int) -> void:
	for _index in count:
		await physics_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(description)
