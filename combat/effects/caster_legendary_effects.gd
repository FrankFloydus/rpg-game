extends RefCounted

const Rules := preload("res://data/caster_legendary_rules.tres")
const Chill := preload("res://combat/effects/chilled.tres")
const Fracture := preload("res://combat/effects/rime_fracture.tscn")
const Arc := preload("res://player/effects/staff_arc.tscn")
const RIME := "rime_that_rings"
const TITHE := "tithe_of_sparks"
const TITHE_ICON := preload("res://assets/rework/icons/shocked.tres")

var _rime_wait := 0.0
var _tithe_wait := 0.0
var _mana_tithe := 0.0
var _rime_equipped := false
var _tithe_equipped := false


func update_equipped(effects: Array[String]) -> bool:
	var was_primed := is_primed()
	_rime_equipped = effects.has(RIME)
	_tithe_equipped = effects.has(TITHE)
	if not _tithe_equipped:
		_mana_tithe = 0.0
	return was_primed != is_primed()


func reset() -> bool:
	var was_primed := is_primed()
	_rime_wait = 0.0
	_tithe_wait = 0.0
	_mana_tithe = 0.0
	return was_primed


func advance(delta: float) -> void:
	_rime_wait = maxf(0.0, _rime_wait - delta)
	_tithe_wait = maxf(0.0, _tithe_wait - delta)


func is_primed() -> bool:
	return _tithe_equipped and _mana_tithe >= Rules.tithe_mana


func record_staff_spend(amount: float) -> bool:
	if not _tithe_equipped or is_primed():
		return false
	_mana_tithe = minf(Rules.tithe_mana, _mana_tithe + amount)
	return is_primed()


func was_chilled(enemy: Node3D) -> bool:
	return _rime_equipped and enemy.has_combat_effect("chilled")


func on_staff_hit(player: CharacterBody3D, enemy: Node3D, hit: Dictionary, previously_chilled: bool) -> bool:
	if _rime_equipped:
		if enemy.health > 0.0:
			enemy.receive_combat_effect(Chill, Rules.rime_chill_seconds, Chill.on_hit_potency(0.0), player, {})
		if previously_chilled and _rime_wait <= 0.0 and _fracture(player, enemy, float(hit.amount)):
			_rime_wait = Rules.rime_cooldown
	if not is_primed() or _tithe_wait > 0.0 or not _arcs(player, enemy, float(hit.amount)):
		return false
	_mana_tithe = 0.0
	_tithe_wait = Rules.tithe_cooldown
	return true


func append_statuses(active: Array[Dictionary]) -> void:
	if is_primed():
		active.append({"id": &"tithe_of_sparks", "name": "Sparks Primed", "beneficial": true,
			"remaining": INF, "icon": TITHE_ICON,
			"description": "Your next eligible staff hit sends lightning arcs to nearby enemies."})


func _fracture(player: CharacterBody3D, enemy: Node3D, hit_amount: float) -> bool:
	var targets := _neighbors(enemy, Rules.rime_radius, Rules.rime_targets)
	if targets.is_empty():
		return false
	var visual := Fracture.instantiate() as GPUParticles3D
	enemy.get_parent().add_child(visual)
	visual.global_position = enemy.global_position + Vector3.UP * 0.045
	(visual.process_material as ShaderMaterial).set_shader_parameter(&"radius", Rules.rime_radius)
	visual.emitting = true
	var origin: Vector3 = enemy.aim_point()
	var ability := {"id": RIME, "name": "Rime Fracture",
		"description": "A staff hit fractures a chilled enemy and deals Cold damage to nearby enemies."}
	for target in targets:
		_damage(player, target, origin, "cold", hit_amount * Rules.rime_damage_factor, ability)
	return true


func _arcs(player: CharacterBody3D, enemy: Node3D, hit_amount: float) -> bool:
	var targets := _neighbors(enemy, Rules.tithe_radius, Rules.tithe_targets)
	if targets.is_empty():
		return false
	var origin: Vector3 = enemy.aim_point()
	var ability := {"id": TITHE, "name": "Tithe of Sparks",
		"description": "Releases a stored Mana tithe as Lightning arcs from an enemy struck with a staff."}
	for target in targets:
		var arc := Arc.instantiate()
		enemy.get_parent().add_child(arc)
		arc.align_to(origin, target.aim_point(), Color("#bf9cf4"))
		_damage(player, target, origin, "lightning", hit_amount * Rules.tithe_damage_factor, ability)
	return true


static func _neighbors(enemy: Node3D, radius: float, limit: int) -> Array[Node3D]:
	var origin: Vector3 = enemy.aim_point()
	var space := enemy.get_world_3d().direct_space_state
	var nearby: Array[Node3D] = []
	for node in enemy.get_tree().get_nodes_in_group("enemies"):
		var target := node as Node3D
		if target == null or target == enemy or target.health <= 0.0 or target.is_queued_for_deletion():
			continue
		var point: Vector3 = target.aim_point()
		if absf(enemy.global_position.y - target.global_position.y) > 1.0:
			continue
		if origin.distance_squared_to(point) > radius * radius:
			continue
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, point, 1)).is_empty():
			nearby.append(target)
	nearby.sort_custom(func(left: Node3D, right: Node3D) -> bool:
		return origin.distance_squared_to(left.aim_point()) < origin.distance_squared_to(right.aim_point()))
	nearby.resize(mini(limit, nearby.size()))
	return nearby


static func _damage(player: CharacterBody3D, target: Node3D, origin: Vector3,
		element: String, amount: float, ability: Dictionary) -> void:
	if not is_instance_valid(target) or target.health <= 0.0:
		return
	var point: Vector3 = target.aim_point()
	var hit: Dictionary = target.take_hit({element: amount}, player, point, origin.direction_to(point))
	player.report_enemy_hit(target, point, hit, ability, false, target.level_damage_factor(player) <= 0.5)
