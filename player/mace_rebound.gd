@tool
extends RefCounted
## Holds the actual contact pose and recovers to the live ready pose.

const ChargeReturn := preload("res://player/charge_return.gd")
const AttackAnimation := preload("res://combat/attack_animation.gd")
const REBOUND_RISE := 0.062
const REBOUND_DECAY := 0.20
const CATCH_SECONDS := 0.038
const CATCH_RELEASE_SECONDS := 0.072
const CATCH_SURFACE_CLEARANCE := 0.025
const CATCH_HEAD_CLEARANCE := 0.10
const CATCH_MINIMUM_VIEW_SCALE := 0.32
const CHARGED_CATCH_MINIMUM_VIEW_SCALE := 0.14
const BURIED_HEAVY_CATCH_LEAD := 0.016
const HEAVY_LEFT_CATCH_SHAFT := Vector3(0.65, 0.15, -0.75)
const HEAVY_LEFT_CATCH_ARM_BLEND := 0.30
const LATERAL_DIRECTIONS := {
	&"light_left": 1.0,
	&"light_right": -1.0,
	&"heavy_left": 1.0,
	&"heavy_right": -1.0,
}
const SOLID_SURFACES := [&"stone", &"wood", &"metal"]
# Downcuts sink into the stop, while the charged sweeps tuck their head in from the side.
const CATCH_DROP := {
	&"light_down_left": 0.24,
	&"light_down_right": 0.30,
	&"heavy_left": 0.10,
	&"heavy_right": 0.08,
}
# Travel in metres, rotation in radians, and total recovery in seconds.
const PROFILES := {
	&"stone": Vector3(0.13, 0.19, 0.32),
	&"metal": Vector3(0.10, 0.23, 0.27),
	&"wood": Vector3(0.07, 0.12, 0.30),
	&"armor": Vector3(0.10, 0.16, 0.28),
	&"guard": Vector3(0.15, 0.27, 0.34),
	&"mass": Vector3(0.065, 0.10, 0.24),
}

var duration: float
var render_scale := 1.0
var arm_ik_blend := 1.0
var _animator: AnimationPlayer
var _pose: Node3D
var _view: Node3D
var _idle: StringName
var _strength: Vector2
var _direction: Vector3
var _channels: Array[ChargeReturn.Channel]
var _catch_channels: Array[Transform3D] = []
var _catch_head := Vector3.ZERO
var _catch_arm_blend := 1.0
var _lateral := false
var _charged_lateral := false
var _buried_heavy := false
var _surface_point := Vector3.INF
var _surface_normal := Vector3.ZERO


static func uses_guided_stop(attack: StringName) -> bool:
	return CATCH_DROP.has(attack)


func _init(animator: AnimationPlayer, pose: Node3D,
		attack: StringName, impact_seconds: float, idle: StringName, view: Node3D,
		local_travel: Vector3, kind: StringName, heavy: bool, minimum_recovery := 0.0,
		local_normal := Vector3.ZERO, local_point := Vector3.INF) -> void:
	_animator = animator
	_pose = pose
	_idle = idle
	_view = view
	var profile: Vector3 = PROFILES.get(kind, PROFILES[&"stone"])
	_direction = (-local_travel.normalized() + Vector3.BACK * 0.36).normalized()
	_strength = Vector2(profile.x, profile.y) * (1.16 if heavy else 1.0)
	duration = maxf(profile.z, minimum_recovery)
	# A trace or preview may have sampled another frame before reporting impact.
	_seek(attack, impact_seconds)
	_channels = ChargeReturn.capture_channels(animator, [attack, idle])
	var solid := kind in SOLID_SURFACES
	_lateral = solid and attack in LATERAL_DIRECTIONS
	_charged_lateral = _lateral and heavy
	if _charged_lateral and attack == &"heavy_left":
		_catch_arm_blend = HEAVY_LEFT_CATCH_ARM_BLEND
	if solid and local_point.is_finite() and not local_normal.is_zero_approx():
		_surface_point = view.to_global(local_point)
		_surface_normal = (view.global_basis * local_normal).normalized()
	if _lateral or uses_guided_stop(attack):
		_capture_catch(attack, local_normal.normalized())


func _capture_catch(attack: StringName, normal: Vector3) -> void:
	var root := _pose.get_node_or_null("TraceRoot") as Node3D
	var tip := _pose.get_node_or_null("TraceTip") as Node3D
	var timing := AttackAnimation.read(_animator.get_animation(attack)) as AttackAnimation
	if root == null or tip == null or timing == null:
		return
	_catch_head = (root.position + tip.position) * 0.5
	var mount_to_view := _view.global_transform.affine_inverse() * _pose.get_parent_node_3d().global_transform
	var contact_head := mount_to_view * (_pose.transform * _catch_head)
	if _charged_lateral and _surface_point.is_finite():
		var surface_distance := (_view.to_global(contact_head) - _surface_point).dot(_surface_normal)
		_buried_heavy = surface_distance < 0.0
	# Use our authored contact orientation and arm pose, then place the head in
	# a compact catch relative to where it actually met the obstacle.
	_seek(attack, timing.impact)
	var impact_head := mount_to_view * (_pose.transform * _catch_head)
	var to_impact := impact_head - contact_head
	var recoil: Vector3
	if _lateral:
		recoil = Vector3(to_impact.x * 0.85, minf(0.0, to_impact.y) - 0.12,
			maxf(0.0, to_impact.z) + 0.14)
		var side: float = LATERAL_DIRECTIONS[attack]
		recoil.x = side * maxf(0.10, side * (contact_head.x + recoil.x)) - contact_head.x
		# Pull toward the camera along a glancing surface before constraining the
		# remaining travel to its plane. This leaves room for the head to turn inward.
		if normal.z > 0.25:
			var needed := maxf(0.0, CATCH_SURFACE_CLEARANCE - recoil.dot(normal))
			recoil.z += minf(needed / normal.z, 0.18)
		# Lay the shaft diagonally across the lower view. Keeping the Impact
		# shaft pointed nearly straight ahead would pull the grips into the eye.
		var wrist := _pose.get_node_or_null("RightWrist") as Node3D
		if wrist != null:
			var shaft := (mount_to_view.basis * (_pose.basis * (_catch_head - wrist.position))).normalized()
			# A right-to-left heavy crosses the lead arm in front of the chest.
			# Tip the shaft up from its grips so the sleeve exits below the camera.
			var caught_shaft := HEAVY_LEFT_CATCH_SHAFT if attack == &"heavy_left" else Vector3(side * 0.58, -0.10, -0.81)
			var turn := Basis(Quaternion(shaft, caught_shaft.normalized()))
			_pose.basis = mount_to_view.basis.inverse() * turn * mount_to_view.basis * _pose.basis
	else:
		recoil = Vector3(to_impact.x * 0.65, minf(0.0, to_impact.y) - float(CATCH_DROP[attack]),
			maxf(0.0, to_impact.z) + minf(_strength.x, 0.14))
	recoil += normal * maxf(0.0, CATCH_SURFACE_CLEARANCE - recoil.dot(normal))
	var current_head := mount_to_view * (_pose.transform * _catch_head)
	_pose.position += mount_to_view.basis.inverse() * (contact_head + recoil - current_head)
	for channel in _channels:
		_catch_channels.append(channel.read())
		channel.write(channel.initial)


func sample(elapsed: float, idle_time: float, selected_idle := &"") -> void:
	var idle := _idle if selected_idle.is_empty() else selected_idle
	if not _catch_channels.is_empty():
		_sample_catch(elapsed, idle_time, idle)
		return
	var settle := smoothstep(0.042, duration, elapsed)
	if settle > 0.0:
		_seek(idle, fposmod(idle_time, _animator.get_animation(idle).length))
	for channel in _channels:
		var from_contact := channel.initial
		channel.write(from_contact.interpolate_with(channel.read(), settle) if settle > 0.0 else from_contact)

	var recoil := smoothstep(0.0, REBOUND_RISE, elapsed) \
		* (1.0 - smoothstep(REBOUND_RISE, REBOUND_DECAY, elapsed))
	var parent_from_view := _pose.get_parent_node_3d().global_basis.inverse() * _view.global_basis
	var travel := parent_from_view * _direction
	var torque := _pose.basis.y.normalized().cross(travel.normalized())
	_pose.position += travel * (_strength.x * recoil)
	if not torque.is_zero_approx():
		_pose.basis = Basis(torque.normalized(), _strength.y * recoil * torque.length()) * _pose.basis


func _sample_catch(elapsed: float, idle_time: float, idle: StringName) -> void:
	# An already occluded heavy has no readable contact pose. Begin the visible
	# fold while fitting it to the near face on the first impact sample.
	var catch_time := elapsed + BURIED_HEAVY_CATCH_LEAD if _buried_heavy else elapsed
	var catch_weight := smoothstep(0.0, CATCH_SECONDS, catch_time)
	var settle := smoothstep(CATCH_RELEASE_SECONDS, duration, elapsed)
	# Keep more of the authored sleeve shape while the leftward catch turns
	# both grips across the chest, then release it into the regular rig solve.
	arm_ik_blend = lerpf(1.0, _catch_arm_blend, catch_weight * (1.0 - settle))
	if settle > 0.0:
		_seek(idle, fposmod(idle_time, _animator.get_animation(idle).length))
	for index in _channels.size():
		var channel := _channels[index]
		var target := _catch_channels[index]
		var caught := channel.initial.interpolate_with(target, catch_weight)
		if channel.node == _pose and _lateral:
			# Interpolating the shaft rotation alone can swing the distant head
			# back into the wall, even when both endpoint positions are clear.
			var head := (channel.initial * _catch_head).lerp(target * _catch_head, catch_weight)
			caught.origin = head - caught.basis * _catch_head
		channel.write(caught.interpolate_with(channel.read(), settle) if settle > 0.0 else caught)
	render_scale = _catch_render_scale(elapsed) if _surface_point.is_finite() else 1.0


func _catch_render_scale(elapsed: float) -> float:
	var eye := _view.global_position
	var head_reach := (eye - _pose.to_global(_catch_head)).dot(_surface_normal)
	var space := (eye - _surface_point).dot(_surface_normal) - CATCH_HEAD_CLEARANCE
	if head_reach <= 0.0 or space >= head_reach:
		return 1.0
	# The render socket fits about the eye, preserving the projection and grips
	# even when the trace was occluded.
	var entry := 1.0 if _buried_heavy else smoothstep(0.0, CATCH_SECONDS * 0.55, elapsed)
	var weight := entry * (1.0 - smoothstep(duration - CATCH_SECONDS, duration, elapsed))
	# A follow-through can reach farther than the standing clearance allows
	# when the player keeps walking into the wall after a charged impact.
	var minimum := CHARGED_CATCH_MINIMUM_VIEW_SCALE if _charged_lateral else CATCH_MINIMUM_VIEW_SCALE
	return lerpf(1.0, clampf(space / head_reach, minimum, 1.0), weight)


func _seek(clip: StringName, time: float) -> void:
	if _animator.current_animation != clip:
		_animator.play(clip)
	_animator.seek(time, true, true)
