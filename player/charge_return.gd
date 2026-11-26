@tool
extends RefCounted
## Retraces a released wind-up, then blends its animated hands and arms into the live idle pose.


class Channel:
	var node: Node3D
	var bone := -1
	var initial: Transform3D
	var _idle_blend_started := false
	var _last_charge_rotation: Quaternion
	var _last_idle_rotation: Quaternion

	func read() -> Transform3D:
		if bone >= 0:
			return (node as Skeleton3D).get_bone_pose(bone)
		return node.transform

	func write(pose: Transform3D) -> void:
		if bone >= 0:
			(node as Skeleton3D).set_bone_pose(bone, pose)
		else:
			node.transform = pose

	func blend_to_idle(charge_pose: Transform3D, idle_pose: Transform3D, blend: float) -> Transform3D:
		var charge_rotation := charge_pose.basis.get_rotation_quaternion()
		var idle_rotation := idle_pose.basis.get_rotation_quaternion()
		# Choose the shortest side once. Keep each stream in its previous quaternion
		# hemisphere so the moving charge pose cannot switch paths midway through the return.
		if _idle_blend_started and charge_rotation.dot(_last_charge_rotation) < 0.0:
			charge_rotation = -charge_rotation
		var idle_reference := _last_idle_rotation if _idle_blend_started else charge_rotation
		if idle_rotation.dot(idle_reference) < 0.0:
			idle_rotation = -idle_rotation
		_idle_blend_started = true
		_last_charge_rotation = charge_rotation
		_last_idle_rotation = idle_rotation
		var rotation := charge_rotation.slerpni(idle_rotation, blend)
		var scale := charge_pose.basis.get_scale().lerp(idle_pose.basis.get_scale(), blend)
		return Transform3D(Basis(rotation).scaled_local(scale), charge_pose.origin.lerp(idle_pose.origin, blend))


var _animator: AnimationPlayer
var _charge: StringName
var _idle: StringName
var _starting_phase: float
var _retrace_fraction: float
var _channels: Array[Channel] = []


func _init(animator: AnimationPlayer, phase: float, retrace_fraction := 1.0, idle := &"idle") -> void:
	_animator = animator
	_charge = animator.current_animation
	_idle = idle
	_starting_phase = phase
	_retrace_fraction = retrace_fraction
	_channels = capture_channels(animator, [_charge, _idle])


static func capture_channels(animator: AnimationPlayer, clips: Array[StringName]) -> Array[Channel]:
	var channels: Array[Channel] = []
	var paths := {}
	var root := animator.get_node(animator.root_node)
	for clip in clips:
		var animation := animator.get_animation(clip)
		for track in animation.get_track_count():
			if animation.track_get_type(track) not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D,
					Animation.TYPE_SCALE_3D]:
				continue
			var path := animation.track_get_path(track)
			if paths.has(path):
				continue
			paths[path] = true
			var node := root.get_node_or_null(NodePath(path.get_concatenated_names())) as Node3D
			if node == null:
				continue
			var channel := Channel.new()
			channel.node = node
			if path.get_subname_count() > 0:
				var skeleton := node as Skeleton3D
				channel.bone = skeleton.find_bone(path.get_subname(0)) if skeleton != null else -1
				if channel.bone < 0:
					continue
			channel.initial = channel.read()
			channels.append(channel)
	return channels


func sample(progress: float, idle_time: float) -> void:
	var idle_length := _animator.get_animation(_idle).length
	idle_time = fposmod(idle_time, idle_length)
	if progress >= 1.0:
		_seek(_idle, idle_time)
		return
	var phase := _starting_phase * (1.0 - _retrace_fraction * smoothstep(0.0, 0.88, progress))
	_seek(_charge, phase * _animator.get_animation(_charge).length)
	var leave_capture := smoothstep(0.0, 0.32, progress)
	var idle_blend := smoothstep(0.35, 1.0, progress)
	if idle_blend <= 0.0:
		for channel in _channels:
			channel.write(channel.initial.interpolate_with(channel.read(), leave_capture))
		return
	var charge_poses: Array[Transform3D] = []
	for channel in _channels:
		charge_poses.append(channel.initial.interpolate_with(channel.read(), leave_capture))
	_seek(_idle, idle_time)
	for index in _channels.size():
		var channel := _channels[index]
		var idle_pose := channel.read()
		var pose := channel.blend_to_idle(charge_poses[index], idle_pose, idle_blend) if _retrace_fraction < 1.0 \
			else charge_poses[index].interpolate_with(idle_pose, idle_blend)
		channel.write(pose)


func _seek(clip: StringName, time: float) -> void:
	if _animator.current_animation != clip:
		_animator.play(clip)
	_animator.seek(time, true, true)
