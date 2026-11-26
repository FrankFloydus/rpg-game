extends RefCounted
## Emits contact effects only for real damage or an actual strike on world geometry.

const StoneImpact := preload("res://combat/effects/stone_impact.tscn")
const EngoreRuntime := preload("res://addons/godot-dismemberment/runtime_manifest.tscn")
const Dismemberment := preload("res://combat/effects/impact_dismemberment.gd")
const WeaponRoles := preload("res://combat/weapons/weapon_roles.gd")
const DRY_CREATURES := ["skeleton", "golem", "wraith", "reaper"]
const LAST_IMPACT := &"last_contact_effect_frame"


static func world(context: Node3D, point: Vector3, normal: Vector3, surface := &"stone") -> void:
	if not point.is_finite():
		return
	var parent := context.get_parent() as Node3D
	if parent != null:
		var active_world := parent.get_node_or_null("ActiveWorld")
		if active_world != null and active_world.get_child_count() > 0:
			parent = active_world.get_child(0) as Node3D
	contact(parent, point, normal, surface)


static func contact(parent: Node3D, point: Vector3, normal: Vector3, surface: StringName) -> void:
	if point.is_finite() and is_instance_valid(parent):
		_spawn_stone.call_deferred(parent.get_instance_id(), point, _safe_direction(normal), surface)


static func enemy(target: Node3D, model: Node3D, point: Vector3, direction: Vector3, amount: float,
		lethal: bool, source: Node3D, weapon_contact: Dictionary = {}, overkill := 0.0,
		body_resistance := 1.0) -> void:
	if not point.is_finite() or amount <= 0.0:
		return
	var destination := target.get_parent() as Node3D
	if destination == null:
		return
	var destination_id := destination.get_instance_id()
	var model_id := model.get_instance_id() if is_instance_valid(model) else 0
	var family: String = target.definition().get("family", "")
	var dry := family in DRY_CREATURES
	var travel := _safe_direction(direction)
	var can_sever := lethal and family != "wraith" and WeaponRoles.can_sever(weapon_contact)
	var physics_frame := Engine.get_physics_frames()
	var fresh := int(target.get_meta(LAST_IMPACT, -1)) != physics_frame
	if fresh:
		target.set_meta(LAST_IMPACT, physics_frame)
		if dry:
			_spawn_stone.call_deferred(destination_id, point, -travel)
		else:
			var forward := _blood_direction(source, point, travel)
			var excluded: Array[RID] = []
			if target is CollisionObject3D:
				excluded.append(target.get_rid())
			if source is CollisionObject3D:
				excluded.append(source.get_rid())
			_flesh_hit.call_deferred(model_id, destination_id, point, forward, excluded,
				travel if can_sever else Vector3.ZERO, overkill, body_resistance)
	# A typed damage component may deliver the killing contact after this
	# frame's first contact effect has already been queued.
	if can_sever and (dry or not fresh):
		_sever.call_deferred(model_id, destination_id, point, travel, not dry, overkill, body_resistance)


static func _flesh_hit(model_id: int, parent_id: int, point: Vector3, direction: Vector3,
		excluded: Array[RID], cut_direction: Vector3, overkill: float, body_resistance: float) -> void:
	var parent := instance_from_id(parent_id) as Node3D
	if parent == null or not parent.is_inside_tree():
		return
	var model := instance_from_id(model_id) as Node3D
	if (not cut_direction.is_zero_approx() and is_instance_valid(model)
			and Dismemberment.sever_at(model, parent, point, cut_direction, true, overkill, body_resistance)):
		return
	var gore := parent.get_node_or_null("ContactGore") as Node3D
	if gore == null and ClassDB.class_exists(&"GoreComponent"):
		gore = ClassDB.instantiate(&"GoreComponent") as Node3D
		gore.name = "ContactGore"
		gore.disable_dismemberment = true
		gore.enable_blood_skin_painting = false
		gore.auto_apply_blood_material = false
		parent.add_child(gore)

	if gore != null:
		var mode := ClassDB.class_get_integer_constant(&"GoreComponent", &"BLOOD_BURST_COMPACT")
		gore.spawn_blood_fx(point, direction, &"", false, mode, excluded)


static func _blood_direction(source: Node3D, point: Vector3, fallback: Vector3) -> Vector3:
	if is_instance_valid(source):
		var camera := source.get("camera") as Camera3D
		var origin := camera.global_position if is_instance_valid(camera) else source.global_position
		var direction := origin.direction_to(point)
		if not direction.is_zero_approx():
			return direction
	return fallback


static func _sever(model_id: int, parent_id: int, point: Vector3, direction: Vector3,
		native_blood: bool, overkill: float, body_resistance: float) -> void:
	var parent := instance_from_id(parent_id) as Node3D
	var model := instance_from_id(model_id) as Node3D
	if parent != null and parent.is_inside_tree() and model != null:
		Dismemberment.sever_at(model, parent, point, direction, native_blood, overkill, body_resistance)


static func _spawn_stone(parent_id: int, point: Vector3, normal: Vector3, surface := &"stone") -> void:
	var parent := instance_from_id(parent_id) as Node3D
	if parent != null and parent.is_inside_tree():
		var effect := _place_effect(parent, StoneImpact, point + normal * 0.025, normal)
		effect.play(surface)


static func _place_effect(parent: Node3D, scene: PackedScene, point: Vector3, direction: Vector3) -> Node3D:
	var lateral := direction.cross(Vector3.UP).normalized()
	if lateral.is_zero_approx():
		lateral = Vector3.BACK
	var basis := Basis(direction, lateral.cross(direction), lateral)
	var effect := scene.instantiate() as Node3D
	effect.position = parent.to_local(point)
	effect.basis = parent.global_basis.inverse() * basis
	parent.add_child(effect, true)
	return effect


static func _safe_direction(vector: Vector3) -> Vector3:
	return vector.normalized() if vector.is_finite() and not vector.is_zero_approx() else Vector3.UP
