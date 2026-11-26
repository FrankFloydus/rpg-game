extends RefCounted

const StatusCatalog = preload("res://combat/effects/status_catalog.gd")
const PULSE := preload("res://combat/cards/card_pulse.tscn")
const SkeletonCohort := preload("res://combat/cards/allied_skeleton_cohort.gd")
const COLORS := {
	"fire": Color("#ffaa66"), "cold": Color("#aadbf3"),
	"physical": Color("#cb8a80"), "lightning": Color("#d9c3ff"),
}


static func play(id: String, card: Dictionary, player: CharacterBody3D, actors: Node3D) -> void:
	player.combat_event.emit({
		"kind": &"cast_end", "side": &"player", "actor": "Player", "ability_id": id,
		"ability": card.name, "description": card.description, "detail": "Card played",
	})
	if bool(card.get("summon_skeletons", false)):
		# Recasting replaces the current company so the total stays capped at three fighters.
		for child in actors.get_children():
			if child is SkeletonCohort and child.is_active_for(player):
				child.dismiss()
		var allies := SkeletonCohort.new()
		allies.name = "OathboundThree"
		actors.add_child(allies)
		allies.raise_party(player, actors, float(card.summon_seconds))
		_pulse(actors, player.global_position, 1.65, Color("#dcc395"))
		return
	player.card_effects.apply_buffs(card)
	if card.has("heal"):
		player.heal(float(player.stats.max_health) * float(card.heal))
	if card.get("stamina", false):
		player.restore_stamina(player.max_stamina())
	var radius := float(card.get("radius", 0.0))
	var element := String(card.get("element", ""))
	if radius <= 0.0:
		_pulse(actors, player.global_position, 1.25, Color("#d4ab71"))
		return
	_pulse(actors, player.global_position, radius, COLORS.get(element, Color.WHITE))
	var base := (float(player.stats.damage_min) + float(player.stats.damage_max)) * 0.5
	var amount := base * float(card.power) + float(card.get("flat", 0.0))
	var source := player.global_position + Vector3.UP
	var space := player.get_world_3d().direct_space_state
	var condition := StatusCatalog.get_effect(String(card.get("condition", "")))
	var stun_buildup := float(card.get("stun_buildup", 0.0))
	var ability := {"id": id, "name": card.name, "description": card.description}
	var hit := false
	for enemy: Node3D in player.get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or not actors.is_ancestor_of(enemy) or enemy.health <= 0.0:
			continue
		var target: Vector3 = enemy.aim_point()
		if source.distance_squared_to(target) > radius * radius:
			continue
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(source, target, 1)).is_empty():
			continue
		var result: Dictionary = enemy.take_hit({element: amount}, player, target, source.direction_to(target))
		if float(result.dealt) <= 0.0:
			continue
		hit = true
		player.report_enemy_hit(enemy, target, result, ability, false, enemy.level_damage_factor(player) <= 0.5)
		if stun_buildup > 0.0 and enemy.health > 0.0:
			enemy.receive_stun_impact(stun_buildup, player)
		if condition != null and enemy.health > 0.0:
			enemy.receive_combat_effect(condition, float(card.condition_time),
				float(card.condition_power), player, {})
	if hit:
		player.present_card_impact()


static func _pulse(parent: Node3D, point: Vector3, radius: float, tint: Color) -> void:
	var visual := PULSE.instantiate() as MeshInstance3D
	parent.add_child(visual)
	visual.global_position = point + Vector3.UP * 0.035
	visual.scale = Vector3(radius, 1.0, radius)
	visual.set_instance_shader_parameter(&"tint", tint)
	if radius > 2.0:
		var cinders := visual.get_node("Cinders") as GPUParticles3D
		cinders.process_material.set_shader_parameter(&"pigment", tint)
		cinders.emitting = true
	var tween := visual.create_tween()
	tween.tween_method(func(fraction: float) -> void:
		visual.set_instance_shader_parameter(&"age", fraction), 0.0, 1.0, 0.66)
	tween.tween_callback(visual.queue_free)
