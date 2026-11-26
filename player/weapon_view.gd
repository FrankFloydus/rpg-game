extends Node3D
## Assembles the equipped scenes and synchronizes authored poses to combat timing.

const ChargeReturn = preload("res://player/charge_return.gd")
const MaceRebound := preload("res://player/mace_rebound.gd")
const PreviewArmRig = preload("res://player/weapons/preview_two_hand_rig.gd")
const WeaponRoles = preload("res://combat/weapons/weapon_roles.gd")
const HeldModels := preload("res://data/items/held_item_models.gd")
const WEAPON_SCENES := {
	"unarmed": preload("res://player/weapons/unarmed.tscn"),
	"sword_1h": preload("res://player/weapons/sword_1h.tscn"),
	"dagger_1h": preload("res://player/weapons/dagger_1h.tscn"),
	"mace_1h": preload("res://player/weapons/mace_1h.tscn"),
	"axe_1h": preload("res://player/weapons/axe_1h.tscn"),
	"sword_2h": preload("res://player/weapons/sword_2h.tscn"),
	"mace_2h": preload("res://player/weapons/mace_2h.tscn"),
	"axe_2h": preload("res://player/weapons/axe_2h.tscn"),
	"staff": preload("res://player/weapons/staff.tscn"),
	"shield": preload("res://player/weapons/shield.tscn"),
	"focus": preload("res://player/weapons/focus.tscn"),
	"orb": preload("res://player/weapons/orb.tscn"),
}
const GEM_COLORS := {
	"magic": Color("#73a9db"),
	"rare": Color("#e2ba68"),
	"legendary": Color("#ee7551"),
}
const SHIELD_GRIP := Vector3(-0.070, -0.199, -0.016)
const SHIELD_VIEW_SCALE := {
	"riveted_buckler": 1.34,
	"wrought_heater": 1.30,
	"sealed_tower_shield": 1.28,
}
const GUARD_TRANSITION := 0.085
const MACE_GUARD_RAISE_BLEND := 0.05
const MACE_GUARD_HIT_BLEND := 0.035
const MACE_GUARD_RECOIL_PEAK := &"Recoil Peak"
const MACE_GUARD_CLIPS := [&"guard", &"guard_raise", &"guard_hit", &"guard_break"]
const ATTACK_TRANSITION := 0.038
const MACE_LINKED_CHARGE_TRANSITION := 0.20
const DUAL_OFFHAND_MOUNT := Transform3D(Basis(Vector3.LEFT, Vector3.UP, Vector3.BACK),
	Vector3(0.0, -0.078, 0.045))
const BODY_RECOIL_FACTOR := 0.30
const LIGHT_CLIPS := [&"light", &"light_2", &"light_3"]
const HEAVY_CLIPS := [&"heavy", &"heavy_2", &"heavy_3"]
const MACE_LIGHT_CLIPS := [&"light_right", &"light_left", &"light_down_left", &"light_down_right"]
const MACE_HEAVY_CLIPS := [&"heavy_right", &"heavy_left"]
const MACE_ATTACK_CLIPS := MACE_LIGHT_CLIPS + MACE_HEAVY_CLIPS
const MACE_CHARGE_BY_RELEASE := {
	&"heavy_right": &"charge_right",
	&"heavy_left": &"charge_left",
}
const HEAVY_READY_MARKER := &"Heavy Ready"
const CHARGE_CLIPS := [&"charge", &"charge_2", &"charge_3"]
const DUAL_LIGHT_CLIPS := [&"dual_light", &"dual_light_2", &"dual_light_3"]
const DUAL_HEAVY_CLIPS := [&"dual_heavy", &"dual_heavy_2", &"dual_heavy_3"]
const DUAL_CHARGE_CLIPS := [&"dual_charge", &"dual_charge_2", &"dual_charge_3"]
const CHARGE_RETURN_SECONDS := {
	"unarmed": 0.16, "dagger_1h": 0.17, "sword_1h": 0.29, "axe_1h": 0.33, "mace_1h": 0.24,
	"sword_2h": 0.30, "axe_2h": 0.49, "mace_2h": 0.52, "staff": 0.24,
}
# Wide wind-ups relax from the held pose before blending into ready.
const CHARGE_RETURN_RETRACE := {"sword_1h": 0.28, "axe_1h": 0.20, "axe_2h": 0.16, "mace_2h": 0.30}
const WEIGHTS := {
	"unarmed": 0.55, "dagger_1h": 0.59, "sword_1h": 0.72, "axe_1h": 0.86, "mace_1h": 0.90,
	"sword_2h": 0.96, "axe_2h": 1.12, "mace_2h": 1.18, "staff": 0.60,
}

class Sleeve:
	var skeleton: Skeleton3D
	var joint: int
	var parent_inverse: Transform3D
	var shoulder: Vector3


@onready var _main_socket: Node3D = $MainHand
@onready var _offhand_socket: Node3D = $OffHand
@onready var _main_origin := _main_socket.position
@onready var _offhand_origin := _offhand_socket.position
@onready var _main_angle := _main_socket.rotation
@onready var _offhand_angle := _offhand_socket.rotation
@onready var _main_scale := _main_socket.scale
@onready var _offhand_scale := _offhand_socket.scale
@onready var _sway := get_node_or_null("WeaponSway")
@onready var _view_camera := get_parent() as FirstPersonCameraEffects

var _main_animation: AnimationPlayer
var _offhand_animation: AnimationPlayer
var _main_pose: Node3D
var _offhand_pose: Node3D
var _main_cast_origin: Node3D
var _camera_motion_marker: Node3D
var _preview_arm_rig: PreviewArmRig
var _trace_root: Marker3D
var _trace_tip: Marker3D
var _secondary_trace_root: Marker3D
var _secondary_trace_tip: Marker3D
var _dual := false
var _driven_swing := false
var _swing_clip := &"light"
var _driven_phase := 0.0
var _previous_driven_phase := 0.0
var _display_phase := 0.0
var _main_previous := Transform3D.IDENTITY
var _offhand_previous := Transform3D.IDENTITY
var _transition_duration := 1.0
var _transition_remaining := 0.0
var _main_transition_channels: Array[ChargeReturn.Channel] = []
var _offhand_handoff_remaining := 0.0
var _guarding := false
var _guard_motion := &""
var _guard_motion_time := 0.0
var _charge := 0.0
var _previous_charge := 0.0
var _rendered_charge_phase := 0.0
var _main_charge_return: ChargeReturn
var _offhand_charge_return: ChargeReturn
var _charge_return_duration := 0.0
var _charge_return_elapsed := 0.0
var _charge_clip := &"charge"
var _elapsed := 0.0
var _duration := 0.0
var _contact := 0.0
var _heavy := false
var _pose_time := 0.0
var _weight := 1.0
var _type := ""
var _secondary := ""
var _impact_pause := 0.0
var _impact_recoil := 0.0
var _mace_rebound: MaceRebound
var _mace_rebound_duration: float:
	get:
		return _mace_rebound.duration if _mace_rebound != null else 0.0
var _mace_rebound_elapsed := 0.0
var _sleeves: Array[Sleeve] = []


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func rebuild(type: String, rarity: String, secondary: String, secondary_rarity := "normal",
		primary_base_id := "", secondary_base_id := "") -> void:
	if is_instance_valid(_view_camera):
		_view_camera.clear_weapon_motion()
	_type = type
	_secondary = secondary
	_dual = WeaponRoles.can_dual_wield(type, secondary)
	_weight = float(WEIGHTS.get(type, WEIGHTS["unarmed"]))
	_sleeves.clear()
	var main_scene: PackedScene = WEAPON_SCENES.get(type, WEAPON_SCENES["unarmed"])
	var main_item := _replace_model(_main_socket, main_scene, type, rarity,
		HeldModels.scene_for(primary_base_id, type))
	_main_pose = main_item.get_node("Pose")
	_main_cast_origin = _main_pose.find_child("CastOrigin", true, false) as Node3D
	_camera_motion_marker = main_item.get_node_or_null("CameraMotion") as Node3D
	_preview_arm_rig = main_item.get_node_or_null("PreviewArmRig") as PreviewArmRig
	_main_animation = main_item.get_node("AnimationPlayer")
	# Only the explicit pose and trace samples should write this rig. An automatic
	# mixer tick would reapply the last sampled clip over a blended pose.
	_main_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_main_animation.speed_scale = 0.0
	_trace_root = _main_pose.get_node_or_null("TraceRoot") as Marker3D
	_trace_tip = _main_pose.get_node_or_null("TraceTip") as Marker3D

	var offhand_scene: PackedScene = WEAPON_SCENES.get(secondary)
	var offhand_item := _replace_model(_offhand_socket, offhand_scene, secondary, secondary_rarity,
		HeldModels.scene_for(secondary_base_id, secondary))
	_secondary_trace_root = null
	_secondary_trace_tip = null
	if offhand_item != null:
		_offhand_pose = offhand_item.get_node("Pose")
		_offhand_animation = offhand_item.get_node("AnimationPlayer")
		_offhand_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_offhand_animation.speed_scale = 0.0
		if _dual:
			# Mirror the rig, hand, and weapon together. A small vertical offset
			# gives the two blades separate lanes when crossing in front of the eye.
			offhand_item.transform = DUAL_OFFHAND_MOUNT
			_secondary_trace_root = _offhand_pose.get_node_or_null("TraceRoot") as Marker3D
			_secondary_trace_tip = _offhand_pose.get_node_or_null("TraceTip") as Marker3D
			var right_wrist := _offhand_pose.get_node_or_null("RightWrist") as Marker3D
			if right_wrist != null:
				var left_wrist := Marker3D.new()
				left_wrist.name = "LeftWrist"
				left_wrist.position = right_wrist.position
				_offhand_pose.add_child(left_wrist)
	else:
		_offhand_pose = null
		_offhand_animation = null
	_transition_remaining = 0.0
	_main_transition_channels.clear()
	_guarding = false
	_charge = 0.0
	cancel_swing()
	if is_instance_valid(_sway):
		_sway.invalidate_equipment()


func _replace_model(socket: Node3D, scene: PackedScene, type: String, rarity: String,
		base_model: PackedScene) -> Node3D:
	for child in socket.get_children():
		socket.remove_child(child)
		child.queue_free()
	if scene == null:
		return null
	var item := scene.instantiate() as Node3D
	if base_model != null:
		_install_base_geometry(item, base_model, type)
	socket.add_child(item)
	_link_sleeves(item)
	if GEM_COLORS.has(rarity):
		var tint: Color = GEM_COLORS[rarity]
		for gem: MeshInstance3D in item.find_children("*", "MeshInstance3D", true, false):
			if gem.mesh == null or not gem.visible or not String(gem.name).begins_with("Gem"):
				continue
			for surface in gem.mesh.get_surface_count():
				var base_material := gem.get_active_material(surface) as StandardMaterial3D
				if base_material == null:
					continue
				var material := base_material.duplicate() as StandardMaterial3D
				material.albedo_color = material.albedo_color.lerp(tint, 0.72)
				material.emission = tint
				gem.set_surface_override_material(surface, material)
	return item


func _install_base_geometry(item: Node3D, scene: PackedScene, type: String) -> void:
	var mount := item.get_node_or_null("Pose/ForgedModel") as Node3D
	if mount == null:
		return
	var geometry := scene.instantiate() as Node3D
	geometry.name = "BaseGeometry"
	var base_id := scene.resource_path.get_file().get_basename()
	if SHIELD_VIEW_SCALE.has(base_id):
		var view_scale := float(SHIELD_VIEW_SCALE[base_id])
		geometry.scale *= view_scale
		geometry.position += SHIELD_GRIP * (1.0 - view_scale)
	elif type in ["mace_1h", "mace_2h"]:
		# A quarter-turn presents the striking face without moving the shaft or hands.
		geometry.rotate_y(PI * 0.5)
	# The family scene also contains the skinned forearms and authored wrist sockets.
	for piece: MeshInstance3D in mount.find_children("*", "MeshInstance3D", true, false):
		if piece.skin == null and not "forearm" in piece.name.to_lower():
			piece.hide()
	mount.add_child(geometry)


func _link_sleeves(item: Node3D) -> void:
	if item.has_meta(&"authored_sleeves"):
		return
	for candidate in item.find_children("*", "Skeleton3D", true, false):
		var skeleton := candidate as Skeleton3D
		for side in [-1.0, 1.0]:
			var joint := skeleton.find_bone("Right Elbow" if side > 0.0 else "Left Elbow")
			if joint == -1:
				continue
			var sleeve := Sleeve.new()
			sleeve.skeleton = skeleton
			sleeve.joint = joint
			sleeve.shoulder = Vector3(side * 0.49, -0.70, -0.26)
			var parent := skeleton.get_bone_parent(joint)
			sleeve.parent_inverse = skeleton.get_bone_global_rest(parent).affine_inverse()
			_sleeves.append(sleeve)


func set_combat_pose(guarding: bool, charge: float, stage := 1, strike_clip := &"") -> void:
	if guarding != _guarding:
		_guarding = guarding
		_clear_mace_rebound()
		if guarding and _is_mace_guard(&"guard_raise"):
			_start_mace_guard_motion(&"guard_raise", MACE_GUARD_RAISE_BLEND)
		else:
			_guard_motion = &""
			_begin_transition(GUARD_TRANSITION)
	elif charge > 0.0 and _charge <= 0.0:
		# Input can start the next charge on the tick the previous strike finishes.
		var rebounding := _mace_rebound_duration > 0.0
		var linking_mace_charge := _type == "mace_2h" and (_driven_swing or rebounding)
		_guard_motion = &""
		_clear_mace_rebound()
		_driven_swing = false
		_elapsed = _duration
		_impact_pause = 0.0
		if linking_mace_charge or _main_charge_return != null or _mace_idle_is_playing() or _mace_guard_is_playing():
			_begin_transition(MACE_LINKED_CHARGE_TRANSITION if linking_mace_charge else ATTACK_TRANSITION)
			if linking_mace_charge:
				_main_transition_channels = ChargeReturn.capture_channels(_main_animation,
					[_charge_clip_name(stage, strike_clip)])
	_previous_charge = _charge if _charge > 0.0 else charge
	_charge = clampf(charge, 0.0, 1.0)
	if _charge > 0.0:
		_charge_clip = _charge_clip_name(stage, strike_clip)


func react_to_guard_hit(broken: bool) -> void:
	var clip := &"guard_break" if broken else &"guard_hit"
	if not _is_mace_guard(clip):
		return
	var start_time := 0.0
	if not broken and _guard_motion == clip:
		var reaction := _main_animation.get_animation(clip)
		if reaction.has_marker(MACE_GUARD_RECOIL_PEAK):
			# A fresh impact drives toward the kick even if the weapon is already recoiling.
			start_time = reaction.get_marker_time(MACE_GUARD_RECOIL_PEAK)
	_start_mace_guard_motion(clip, MACE_GUARD_HIT_BLEND, start_time)


func _start_mace_guard_motion(clip: StringName, blend: float, start_time := 0.0) -> void:
	_guard_motion = clip
	_guard_motion_time = start_time
	_begin_transition(blend)
	_main_transition_channels = ChargeReturn.capture_channels(_main_animation, [clip])


func swing(heavy: bool, duration: float, contact: float, clip := &"", immediate := false) -> void:
	_clear_mace_rebound()
	_guard_motion = &""
	_driven_swing = false
	_swing_clip = clip if not clip.is_empty() else attack_clip_name(heavy)
	_duration = maxf(0.15, duration)
	_contact = clampf(contact, 0.002, _duration - 0.002)
	_elapsed = 0.0
	_heavy = heavy
	_impact_pause = 0.0
	_impact_recoil = 0.0
	_begin_transition(0.0 if immediate else ATTACK_TRANSITION)


func cancel_swing(recover_charge := false) -> void:
	_clear_mace_rebound()
	_guard_motion = &""
	_driven_swing = false
	_elapsed = _duration
	_impact_pause = 0.0
	_impact_recoil = 0.0
	_charge = 0.0
	_offhand_handoff_remaining = 0.0
	if recover_charge and _rendered_charge_phase > 0.0:
		_begin_charge_return()
	else:
		_clear_charge_return()
	_rendered_charge_phase = 0.0


func rendered_charge_fraction() -> float:
	return _rendered_charge_phase


func attack_clip_name(heavy: bool, stage := 1) -> StringName:
	if _dual:
		if heavy and stage == 3 and "mace_1h" in [_type, _secondary]:
			return &"dual_clash"
		return (DUAL_HEAVY_CLIPS if heavy else DUAL_LIGHT_CLIPS)[stage - 1]
	if _type == "mace_2h":
		var index := clampi(stage - 1, 0, MACE_LIGHT_CLIPS.size() - 1)
		if heavy and index >= MACE_HEAVY_CLIPS.size():
			# The two descending lights lead to the heavy with the same direction.
			index = 1 if index == 2 else 0
		return (MACE_HEAVY_CLIPS if heavy else MACE_LIGHT_CLIPS)[index]
	return _available_stage_clip(HEAVY_CLIPS if heavy else LIGHT_CLIPS, stage)


func is_mace_attack(clip: StringName) -> bool:
	return _type == "mace_2h" and clip in MACE_ATTACK_CLIPS


func _is_mace_motion(clip: StringName) -> bool:
	return _type == "mace_2h" and (clip in MACE_ATTACK_CLIPS or MACE_CHARGE_BY_RELEASE.find_key(clip) != null)


func attack_animation(heavy: bool, stage := 1, clip := &"") -> Animation:
	if clip.is_empty():
		clip = attack_clip_name(heavy, stage)
	var use_secondary := _dual and stage == 2
	var animator := _offhand_animation if use_secondary else _main_animation
	return animator.get_animation(clip_for_hand(clip, use_secondary))


func charge_animation(stage: int, strike_clip := &"") -> Animation:
	var use_secondary := _dual and stage == 2
	var animator := _offhand_animation if use_secondary else _main_animation
	return animator.get_animation(clip_for_hand(_charge_clip_name(stage, strike_clip), use_secondary))


func manual_charge_release_phase(charge_clip: Animation, strike_clip: StringName) -> float:
	if MACE_CHARGE_BY_RELEASE.has(strike_clip) and charge_clip.has_marker(HEAVY_READY_MARKER):
		return clampf(charge_clip.get_marker_time(HEAVY_READY_MARKER) / charge_clip.length, 0.0, 1.0)
	return INF


func _charge_clip_name(stage: int, strike_clip: StringName) -> StringName:
	# Use the release selected at cast start to choose its matching windup.
	if _type == "mace_2h":
		var release := strike_clip if MACE_CHARGE_BY_RELEASE.has(strike_clip) else attack_clip_name(true, stage)
		return MACE_CHARGE_BY_RELEASE[release]
	if not _dual:
		return _available_stage_clip(CHARGE_CLIPS, stage)
	if stage == 3 and "mace_1h" in [_type, _secondary]:
		return &"dual_clash_charge"
	return DUAL_CHARGE_CLIPS[stage - 1]


func clip_for_hand(clip: StringName, offhand: bool) -> StringName:
	if not _dual:
		return clip
	match clip:
		&"dual_light":
			return &"dual_support" if offhand else clip
		&"dual_light_2":
			return &"dual_light" if offhand else &"dual_support"
		&"dual_light_3":
			return &"dual_support" if offhand else clip
		&"dual_heavy":
			return &"dual_support_heavy" if offhand else clip
		&"dual_heavy_2":
			return &"dual_heavy" if offhand else &"dual_support_heavy"
		&"dual_charge":
			return &"dual_support_charge" if offhand else clip
		&"dual_charge_2":
			return &"dual_charge" if offhand else &"dual_support_charge"
		&"dual_charge_3", &"dual_clash_charge":
			return &"dual_charge_3" if offhand else clip
	return clip


func _available_stage_clip(clips: Array, stage: int) -> StringName:
	var preferred: StringName = clips[stage - 1] if stage > 0 and stage <= clips.size() else clips[0]
	return preferred if _main_animation.has_animation(preferred) else clips[0]


func has_trace_sockets(offhand := false) -> bool:
	if offhand:
		return is_instance_valid(_secondary_trace_root) and is_instance_valid(_secondary_trace_tip)
	return is_instance_valid(_trace_root) and is_instance_valid(_trace_tip)


func start_driven_swing(clip: StringName, heavy: bool, phase: float, immediate := false, charge_blend := 0.0) -> void:
	_clear_mace_rebound()
	_guard_motion = &""
	_driven_swing = true
	_swing_clip = clip
	_heavy = heavy
	_elapsed = _duration
	_impact_pause = 0.0
	_impact_recoil = 0.0
	_driven_phase = phase
	_previous_driven_phase = phase
	_display_phase = phase
	var transition := charge_blend if charge_blend > 0.0 else ATTACK_TRANSITION
	_begin_transition(0.0 if immediate else transition)
	if charge_blend > 0.0 and not immediate:
		_main_transition_channels = ChargeReturn.capture_channels(_main_animation, [clip])
	if immediate and _dual and clip == &"dual_light_3":
		_offhand_handoff_remaining = GUARD_TRANSITION


func set_swing_phase(phase: float) -> void:
	if _mace_rebound_duration > 0.0:
		return
	_previous_driven_phase = _driven_phase
	_driven_phase = phase
	if phase >= 1.0:
		_driven_swing = false


func sample_blade(clip: StringName, clip_time: float, aim: Transform3D,
		offhand := false, normalized := false, include_contact_geometry := false) -> PackedVector3Array:
	var animator := _offhand_animation if offhand else _main_animation
	var source := clip_for_hand(clip, offhand)
	if animator.current_animation != source:
		animator.play(source)
	var time := clip_time * animator.get_animation(source).length if normalized else clip_time
	animator.seek(time, true, true)
	# Sample the real guide points with the authored rest socket. Recoil and
	# camera shake are presentation and must not swing the collision a second time.
	var socket := _offhand_socket if offhand else _main_socket
	var origin := _offhand_origin if offhand else _main_origin
	var angle := _offhand_angle if offhand else _main_angle
	var socket_scale := _offhand_scale if offhand else _main_scale
	var heel := _secondary_trace_root if offhand else _trace_root
	var tip := _secondary_trace_tip if offhand else _trace_tip
	var rest := Transform3D(Basis.from_euler(angle).scaled_local(socket_scale), origin)
	var from_current_socket := socket.global_transform.affine_inverse()
	var world_socket := aim * transform * rest * from_current_socket
	var head_start := world_socket * heel.global_position
	var head_end := world_socket * tip.global_position
	if not include_contact_geometry:
		return PackedVector3Array([head_start, head_end])
	var pose := _offhand_pose if offhand else _main_pose
	var damage_root := pose.get_node_or_null("DamageRoot") as Marker3D
	var damage_tip := pose.get_node_or_null("DamageTip") as Marker3D
	var start := world_socket * damage_root.global_position if damage_root != null else head_start
	var end := world_socket * damage_tip.global_position if damage_tip != null else head_end
	var roll_reference := (world_socket.basis * pose.global_basis.z).normalized()
	return PackedVector3Array([start, end, head_start, head_end, roll_reference])


func stop_driven_swing(phase: float) -> void:
	# Capture the contact pose before releasing it into the existing recovery blend.
	_update_pose(_main_animation, _main_pose, _main_previous, clip_for_hand(_swing_clip, false), phase, 1.0)
	if _dual:
		_update_pose(_offhand_animation, _offhand_pose, _offhand_previous, clip_for_hand(_swing_clip, true), phase, 1.0)
	_driven_swing = false
	_elapsed = _duration
	_begin_transition(0.19)
	react_to_impact(true)


func start_mace_rebound(phase: float, local_travel: Vector3, kind: StringName, minimum_recovery := 0.0,
		world_normal := Vector3.ZERO, terrain_point := Vector3.INF) -> void:
	if not _driven_swing or _type != "mace_2h":
		return
	_mace_rebound_elapsed = 0.0
	_driven_swing = false
	_display_phase = phase
	_impact_pause = 0.0
	_impact_recoil = 0.0
	_begin_transition(0.0)
	var impact_seconds := phase * _main_animation.get_animation(_swing_clip).length
	var local_point := to_local(terrain_point) if terrain_point.is_finite() else Vector3.INF
	# Build the catch in the same authored space as the trace. The socket may
	# still carry last frame's rendered clearance scale and sway.
	var rendered_socket := _main_socket.transform
	_main_socket.transform = Transform3D(Basis.from_euler(_main_angle).scaled_local(_main_scale), _main_origin)
	_mace_rebound = MaceRebound.new(_main_animation, _main_pose, _swing_clip, impact_seconds,
		&"idle", self, local_travel, kind, _heavy, minimum_recovery, global_basis.inverse() * world_normal, local_point)
	_main_socket.transform = rendered_socket


func _clear_mace_rebound() -> void:
	_mace_rebound = null


func _sample_mace_rebound(delta: float) -> StringName:
	_mace_rebound.sample(_mace_rebound_elapsed, _pose_time, &"idle")
	var display_clip := _swing_clip if _is_mace_motion(_swing_clip) else &"idle"
	if _mace_rebound_elapsed >= _mace_rebound_duration:
		_clear_mace_rebound()
	else:
		_mace_rebound_elapsed = minf(_mace_rebound_duration, _mace_rebound_elapsed + delta)
	return display_clip


func react_to_impact(hard_surface: bool, phase := -1.0) -> void:
	var heft := strike_heft(_heavy)
	var recoil_strength := (0.51 + heft * 0.72) * (1.20 if hard_surface else 1.0)
	if _driven_swing and not hard_surface and WeaponRoles.family(_type) != &"":
		# Body hits keep the cutting arc continuous. Camera and hit effects convey the larger impact.
		_impact_recoil = maxf(_impact_recoil, recoil_strength * BODY_RECOIL_FACTOR)
		return
	_impact_recoil = maxf(_impact_recoil, recoil_strength)
	if _driven_swing:
		if phase >= 0.0:
			_display_phase = phase
		_impact_pause = maxf(_impact_pause, 0.018 + heft * 0.060 + (0.018 if hard_surface else 0.0))
		return
	if _elapsed < _duration and _elapsed < _contact + 0.035:
		_elapsed = _contact
		# Pause only the held model. Combat, movement, input, and camera keep updating.
		var hold := 0.018 + heft * 0.060 + (0.018 if hard_surface else 0.0)
		_impact_pause = maxf(_impact_pause, hold)


func strike_heft(charged: bool, offhand := false) -> float:
	var weight := float(WEIGHTS.get(_secondary, _weight)) if offhand else _weight
	return clampf(inverse_lerp(0.55, 1.18, weight), 0.0, 1.0) + (0.24 if charged else 0.0)


func staff_origin(fallback: Vector3) -> Vector3:
	if _type != "staff" or not is_instance_valid(_main_pose):
		return fallback
	if is_instance_valid(_main_cast_origin):
		return _main_cast_origin.global_position
	return _main_pose.to_global(Vector3(0.035, 1.01, -0.015))


func _begin_transition(seconds: float, entering_mace_idle := false) -> void:
	_clear_charge_return()
	_main_transition_channels.clear()
	if seconds > 0.0 and (entering_mace_idle or _mace_idle_is_playing() or _mace_guard_is_playing()):
		_main_transition_channels = ChargeReturn.capture_channels(_main_animation, [&"idle"])
	_transition_duration = seconds
	_transition_remaining = seconds
	# A shield has a separate support animation, so it can settle while the weapon cuts to light.
	_offhand_handoff_remaining = GUARD_TRANSITION if seconds <= 0.0 and not _dual else 0.0
	if is_instance_valid(_main_pose):
		_main_previous = _main_pose.transform
	if is_instance_valid(_offhand_pose):
		_offhand_previous = _offhand_pose.transform


func _begin_charge_return() -> void:
	var full_duration := float(CHARGE_RETURN_SECONDS.get(_type, CHARGE_RETURN_SECONDS["unarmed"]))
	_charge_return_duration = lerpf(full_duration * 0.65, full_duration, _rendered_charge_phase)
	_charge_return_elapsed = 0.0
	var retrace_fraction := float(CHARGE_RETURN_RETRACE.get(_type, 1.0))
	_main_charge_return = ChargeReturn.new(_main_animation, _rendered_charge_phase, retrace_fraction)
	if is_instance_valid(_offhand_animation):
		_offhand_charge_return = ChargeReturn.new(_offhand_animation, _rendered_charge_phase)


func _clear_charge_return() -> void:
	_main_charge_return = null
	_offhand_charge_return = null


func _advance_charge_return(delta: float) -> bool:
	if _main_charge_return == null:
		return false
	_charge_return_elapsed = minf(_charge_return_elapsed + delta, _charge_return_duration)
	var progress := _charge_return_elapsed / _charge_return_duration
	_main_charge_return.sample(progress, _pose_time)
	if _offhand_charge_return != null:
		_offhand_charge_return.sample(progress, _pose_time)
	if progress >= 1.0:
		_clear_charge_return()
	return true


func _mace_idle_is_playing() -> bool:
	return _type == "mace_2h" and is_instance_valid(_main_animation) and _main_animation.current_animation == &"idle"


func _mace_guard_is_playing() -> bool:
	return is_instance_valid(_main_animation) and _is_mace_guard(_main_animation.current_animation)


func _is_mace_guard(clip: StringName) -> bool:
	return _type == "mace_2h" and _secondary != "shield" and clip in MACE_GUARD_CLIPS


func _update_camera_motion(clip: StringName, recovering_charge: bool, delta: float) -> void:
	if not is_instance_valid(_view_camera):
		return
	var use_marker := _is_mace_motion(clip) or _is_mace_guard(clip)
	if recovering_charge:
		# The mace return samples the animated camera through its neutral idle key.
		use_marker = _is_mace_motion(_charge_clip) \
			and _main_animation.current_animation in [_charge_clip, &"idle"]
	if use_marker and is_instance_valid(_camera_motion_marker):
		_view_camera.set_weapon_motion(_camera_motion_marker.quaternion)
	else:
		_view_camera.settle_weapon_motion(delta)


func _update_preview_arms(clip: StringName, blend: float) -> void:
	if not is_instance_valid(_preview_arm_rig):
		return
	if _is_mace_motion(clip) or _is_mace_guard(clip):
		_preview_arm_rig.apply_to_grip(_main_pose, blend)
	elif not _preview_arm_rig.transform.is_equal_approx(Transform3D.IDENTITY):
		_preview_arm_rig.transform = Transform3D.IDENTITY


func _process(delta: float) -> void:
	if not is_instance_valid(_main_animation):
		return
	var rebounding := _mace_rebound_duration > 0.0
	_pose_time += delta
	var held := minf(delta, _impact_pause)
	_impact_pause = maxf(0.0, _impact_pause - held)
	_elapsed = minf(_elapsed + delta - held, _duration)
	var physics_fraction := Engine.get_physics_interpolation_fraction()
	if held <= 0.0 and not rebounding:
		_display_phase = lerpf(_previous_driven_phase, _driven_phase, physics_fraction)
	_transition_remaining = maxf(_transition_remaining - delta, 0.0)
	_offhand_handoff_remaining = maxf(_offhand_handoff_remaining - delta, 0.0)
	var heft := strike_heft(_heavy)
	var recoil := Vector3(0.009 + heft * 0.024, -0.023 - heft * 0.055,
		0.066 + heft * 0.112) * _impact_recoil
	var wrist := Vector3(-0.053, 0.037, -0.106) * _impact_recoil * (0.70 + heft * 0.37)
	_impact_recoil = move_toward(_impact_recoil, 0.0, delta * (10.6 - heft * 4.2))
	_main_socket.position = _main_origin + recoil
	_offhand_socket.position = _offhand_origin + recoil * 0.64
	_main_socket.rotation = _main_angle + wrist
	_offhand_socket.rotation = _offhand_angle + wrist * 0.42
	_main_socket.scale = _main_scale
	_offhand_socket.scale = _offhand_scale

	var clip := &"idle"
	var time := _pose_time
	_rendered_charge_phase = 0.0
	if _guarding:
		clip = &"guard"
	elif _driven_swing:
		clip = _swing_clip
		time = _display_phase
	elif _elapsed < _duration:
		clip = _swing_clip
		time = _swing_phase()
	elif _charge > 0.0:
		clip = _charge_clip
		time = lerpf(_previous_charge, _charge, physics_fraction)
		_rendered_charge_phase = time
	var main_clip := &"idle" if _guarding and _secondary == "shield" else clip_for_hand(clip, false)
	var main_time := time
	if not _guard_motion.is_empty():
		main_clip = _guard_motion
		var guard_length := _main_animation.get_animation(main_clip).length
		main_time = _guard_motion_time / guard_length
		if _guard_motion_time >= guard_length:
			_guard_motion = &""
		else:
			_guard_motion_time = minf(_guard_motion_time + delta, guard_length)
	var recovering_charge := _advance_charge_return(delta)
	var arm_blend := 1.0
	var rebound_scale := 1.0
	if rebounding:
		var rebound := _mace_rebound
		main_clip = _sample_mace_rebound(delta)
		rebound_scale = rebound.render_scale
		arm_blend = rebound.arm_ik_blend
	elif not recovering_charge:
		if _type == "mace_2h" and main_clip == &"idle" and not _mace_idle_is_playing():
			_begin_transition(GUARD_TRANSITION, true)
		var blend := 1.0 if _transition_remaining <= 0.0 else 1.0 - _transition_remaining / _transition_duration
		if blend >= 1.0:
			_main_transition_channels.clear()
		var main_blend := blend if _main_transition_channels.is_empty() else 1.0
		_update_pose(_main_animation, _main_pose, _main_previous, main_clip, main_time, main_blend)
		var eased_blend := smoothstep(0.0, 1.0, blend)
		for channel in _main_transition_channels:
			channel.write(channel.initial.interpolate_with(channel.read(), eased_blend))
		if not _main_transition_channels.is_empty():
			arm_blend = eased_blend
		var offhand_blend := minf(blend, 1.0 - _offhand_handoff_remaining / GUARD_TRANSITION)
		_update_pose(_offhand_animation, _offhand_pose, _offhand_previous, clip_for_hand(clip, true), time, offhand_blend)
	else:
		# ChargeReturn releases its capture of the already solved arms over the first 32%.
		arm_blend = smoothstep(0.0, 0.32, _charge_return_elapsed / _charge_return_duration)
	_update_preview_arms(_charge_clip if recovering_charge else main_clip, arm_blend)
	# Only the displayed pose publishes camera motion. A blade trace may seek the same marker.
	_update_camera_motion(main_clip, recovering_charge, delta)
	if is_instance_valid(_sway):
		_sway.apply_sockets(_main_socket, _offhand_socket, _main_pose, _offhand_pose, rebound_scale)
	# Put each sleeve's far joint against the character as the authored grip moves.
	for sleeve in _sleeves:
		var shoulder := sleeve.skeleton.to_local(to_global(sleeve.shoulder))
		sleeve.skeleton.set_bone_pose_position(sleeve.joint, sleeve.parent_inverse * shoulder)


func _swing_phase() -> float:
	if _elapsed < _contact:
		return 0.5 * _elapsed / _contact
	var recoil_phase := (_elapsed - _contact) / (_duration - _contact)
	# Give large weapons a decisive follow-through and a slower return to the ready stance.
	return 0.5 + 0.5 * pow(recoil_phase, 1.0 - strike_heft(_heavy) * 0.26)


func _update_pose(animator: AnimationPlayer, pose: Node3D, start: Transform3D,
		clip: StringName, time: float, blend: float) -> void:
	if not is_instance_valid(animator):
		return
	if not animator.has_animation(clip):
		# Offhand items reuse their support pose on follow-up strikes.
		clip = StringName(String(clip).trim_suffix("_2").trim_suffix("_3"))
	if animator.current_animation != clip:
		animator.play(clip)
	var length := animator.get_animation(clip).length
	var seek_time := fposmod(time, length) if clip in [&"idle", &"guard"] else time * length
	animator.seek(seek_time, true, true)
	if blend < 1.0:
		pose.transform = start.interpolate_with(pose.transform, smoothstep(0.0, 1.0, blend))
