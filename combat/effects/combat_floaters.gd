extends RefCounted
## Short-lived, world-anchored combat feedback owned by the current encounter.

enum Style { HIT, CRITICAL, PERIODIC, OUTCOME }

const GOLD := Color("#ffd84d")
const LABELS := [
	preload("res://ui/combat_floater.tscn"),
	preload("res://ui/combat_floater_critical.tscn"),
	preload("res://ui/combat_floater_periodic.tscn"),
	preload("res://ui/combat_floater_outcome.tscn"),
]
const FLOAT_GROUP := &"combat_floaters"
const DRIFT_LANES := [0.0, -0.16, 0.16, -0.08, 0.08]
const CRITICAL_IMPACT_SCALE := 3.0
const CRITICAL_IMPACT_TIME := 0.04
const CRITICAL_SETTLE_TIME := 0.20
const CRITICAL_HOLD_TIME := 0.55
const CRITICAL_FADE_TIME := 0.45

static var _drift_index := 0


static func damage(target: Node3D, point: Vector3, amount: int, critical := false,
		periodic := false, glancing := false) -> void:
	if not is_instance_valid(target):
		return
	var parent := target.get_parent() as Node3D
	if amount <= 0:
		if glancing:
			outcome(parent, point, "Glancing")
		return
	var style := Style.PERIODIC if periodic else (Style.CRITICAL if critical else Style.HIT)
	var text := "%d\nGlancing" % amount if glancing else str(amount)
	_spawn(parent, point, text, style)


static func outcome(parent: Node3D, point: Vector3, text: String) -> void:
	if not text.is_empty():
		_spawn(parent, point, text, Style.OUTCOME)


static func _spawn(parent: Node3D, point: Vector3, text: String, style: Style) -> void:
	if not is_instance_valid(parent) or not parent.is_inside_tree() or not point.is_finite():
		return
	var camera := parent.get_viewport().get_camera_3d()
	if not is_instance_valid(camera):
		return
	var to_camera := camera.global_position - point
	if to_camera.dot(camera.global_basis.z) <= 0.05:
		return
	# Keep the first-person weapon from covering the text. Skip targets already hidden by a wall.
	var sight := PhysicsRayQueryParameters3D.create(camera.global_position, point, 1)
	if not camera.get_world_3d().direct_space_state.intersect_ray(sight).is_empty():
		return
	var right := camera.global_basis.x.normalized()
	var up := camera.global_basis.y.normalized()
	var lane := float(DRIFT_LANES[_drift_index])
	_drift_index = (_drift_index + 1) % DRIFT_LANES.size()

	var label := LABELS[style].instantiate() as Label3D
	label.text = text
	var duration := 0.72
	var rise := 0.52
	var offset := Vector3.ZERO
	match style:
		Style.CRITICAL:
			label.scale = Vector3.ONE * CRITICAL_IMPACT_SCALE
		Style.PERIODIC:
			duration = 0.57
			rise = 0.38
			offset = right * lane + up * 0.12
		Style.OUTCOME:
			duration = 0.76
			offset = up * 0.32 + right * lane
	parent.add_child(label, true)
	label.global_position = point + to_camera.normalized() * minf(0.32, to_camera.length() * 0.16) + offset
	if style == Style.CRITICAL:
		_animate_critical(label)
		return

	var fade_start := duration * 0.47
	var drift := label.create_tween().set_parallel(true)
	drift.tween_property(label, "global_position", label.global_position + up * rise + right * lane, duration) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	drift.tween_property(label, "modulate:a", 0.0, duration - fade_start).set_delay(fade_start)
	drift.tween_property(label, "outline_modulate:a", 0.0, duration - fade_start).set_delay(fade_start)
	drift.chain().tween_callback(label.queue_free)


static func _animate_critical(label: Label3D) -> void:
	# Start at peak size on impact, then settle and fade at the hit point.
	var pop := label.create_tween().set_parallel(true)
	pop.tween_interval(CRITICAL_IMPACT_TIME)
	pop.chain().tween_property(label, "scale", Vector3.ONE, CRITICAL_SETTLE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	pop.tween_property(label, "modulate", GOLD, CRITICAL_SETTLE_TIME)
	pop.chain().tween_interval(CRITICAL_HOLD_TIME)
	pop.chain().tween_property(label, "modulate:a", 0.0, CRITICAL_FADE_TIME)
	pop.tween_property(label, "outline_modulate:a", 0.0, CRITICAL_FADE_TIME)
	pop.chain().tween_callback(label.queue_free)
