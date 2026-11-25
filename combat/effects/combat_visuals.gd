extends RefCounted
## Spawns authored presentation and owns the lifetime of target-attached status visuals.

const ONE_SHOT_FALLBACK_LIFETIME := 10.0


static func landed_hit(target: Node3D, ability: AbilityDefinition, offset: Vector3) -> void:
	if ability != null:
		_spawn(target, ability.hit_fx, offset, true)


static func apply_status(target: Node3D, effect: EffectDefinition, state: Dictionary,
		previous: Dictionary, offset: Vector3) -> void:
	var loop := effect.while_active_fx
	if effect.enemy_while_active_fx != null and target.is_in_group(&"enemies"):
		loop = effect.enemy_while_active_fx
	var previous_fx: Variant = previous.get("active_visual")
	var active_fx: Node3D = previous_fx if is_instance_valid(previous_fx) else null
	if previous.get("active_visual_scene") != loop:
		_remove_loop(active_fx)
		active_fx = null
	if not is_instance_valid(active_fx) or active_fx.is_queued_for_deletion():
		active_fx = _spawn(target, loop, offset)
	if active_fx != null:
		state["active_visual"] = active_fx
		state["active_visual_scene"] = loop
	_spawn(target, effect.on_applied_fx, offset, true)


static func end_status(target: Node3D, state: Dictionary, offset: Vector3) -> void:
	_remove_loop(state.get("active_visual"))
	var effect := state.get("effect") as EffectDefinition
	if effect != null:
		_spawn(target, effect.on_end_fx, offset, true)


static func sync_loop(target: Node3D, existing: Node3D, scene: PackedScene, offset: Vector3, enabled: bool) -> Node3D:
	if enabled:
		return existing if is_instance_valid(existing) else _spawn(target, scene, offset)
	_remove_loop(existing)
	return null


static func _remove_loop(visual: Variant) -> void:
	if is_instance_valid(visual):
		visual.hide()
		visual.queue_free()


static func _spawn(target: Node3D, scene: PackedScene, offset: Vector3,
		one_shot := false) -> Node3D:
	if scene == null or not target.is_inside_tree() or not scene.can_instantiate():
		return null
	var instance := scene.instantiate()
	if not instance is Node3D:
		instance.free()
		return null
	var visual := instance as Node3D
	visual.top_level = false
	visual.position += offset
	target.add_child(visual)
	if one_shot:
		var cleanup := Timer.new()
		cleanup.one_shot = true
		visual.add_child(cleanup)
		cleanup.timeout.connect(visual.queue_free)
		cleanup.start(ONE_SHOT_FALLBACK_LIFETIME)
	return visual
