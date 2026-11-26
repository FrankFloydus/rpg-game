@tool
extends SubViewportContainer
## Replays an authored strike and the draft hit feedback in an isolated first-person viewport.

const STONE := preload("res://assets/rework/courtyard_stone.png")
const HitShake := preload("res://data/weapon_hit_shake.gd")
const Timeline := preload("res://combat/attack_animation.gd")
const Rebound := preload("res://player/mace_rebound.gd")
const ChargeReturn := preload("res://player/charge_return.gd")
const ArmRig := preload("res://player/weapons/preview_two_hand_rig.gd")
const WeaponRoles := preload("res://combat/weapons/weapon_roles.gd")
const WeaponView := preload("res://player/weapon_view.gd")
const IDLE_GAP := 0.60
const TRACE_SAMPLE_STEP := 1.0 / 120.0
const DEFAULT_CONTACT := Vector3(0.0, -0.04, -1.66)
const GENERIC_STOP_SECONDS := 0.19
const STATIC_SURFACES := [&"stone", &"metal", &"wood"]
const SURFACES := {
	&"body": [Color("#704035"), 0.0, 0.80],
	&"breakable": [Color("#8d5737"), 0.0, 0.85],
	&"stone": [Color("#a49a87"), 0.0, 0.92],
	&"metal": [Color("#8997a7"), 0.72, 0.30],
	&"wood": [Color("#74503a"), 0.0, 0.85],
	&"armor": [Color("#718794"), 0.55, 0.42],
	&"guard": [Color("#93815a"), 0.45, 0.47],
	&"mass": [Color("#74777a"), 0.1, 0.82],
}

enum Response { DEFAULT, STOP, THROUGH }

var _scene: PackedScene
var _weapon_type := ""
var _profiles: Resource
var _material := &"body"
var _response := Response.DEFAULT
var _charged := false
var _looping := true
var _playing := true
var _editor_scale := 1.0

var _stage: SubViewport
var _camera: Camera3D
var _weapon: Node3D
var _weapon_mount := Transform3D.IDENTITY
var _pose: Node3D
var _trace_root: Marker3D
var _trace_tip: Marker3D
var _camera_motion: Node3D
var _arm_rig: ArmRig
var _animation_player: AnimationPlayer
var _target: Node3D
var _pedestal: MeshInstance3D
var _target_material: StandardMaterial3D
var _selected_clip := &""
var _clip := &""
var _clip_length := 0.0
var _impact_time := 0.27
var _duration := 0.0
var _clock := 0.0
var _travel := Vector3.FORWARD
var _contact_point := DEFAULT_CONTACT
var _contact_normal := Vector3.BACK
var _kick := Vector4.ZERO
var _pulse := HitShake.Pulse.STANDARD
var _rebound: Rebound
var _stop_channels: Array[ChargeReturn.Channel] = []
var _minimum_recovery := 0.0
var _stops_weapon := false


func configure(scene: PackedScene, weapon_type: String, profiles: Resource) -> void:
	_scene = scene
	_weapon_type = weapon_type
	_profiles = profiles
	name = "HitShakePreview"
	if is_node_ready():
		_update_visibility()


static func attack_choices(scene: PackedScene) -> Dictionary[StringName, String]:
	var choices: Dictionary[StringName, String] = {}
	var weapon := scene.instantiate()
	var animator := weapon.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if animator != null:
		for candidate in animator.get_animation_list():
			var name := String(candidate)
			if not HitShake.is_attack_motion(StringName(candidate)):
				continue
			var label := animator.get_animation(candidate).resource_name
			if name.begins_with("dual_"):
				var dual_label := name.replace("_3", " finisher").capitalize()
				choices[StringName(candidate)] = dual_label + " · Main hand"
				if name != "dual_light_3":
					choices[HitShake.motion_id(StringName(candidate), true)] = dual_label + " · Off hand"
			else:
				choices[StringName(candidate)] = name.capitalize() if label.is_empty() else label
	weapon.free()
	return choices


static func can_choose_response(material: StringName) -> bool:
	return material == &"breakable" or material in STATIC_SURFACES


static func stops_weapon(weapon_type: String, material: StringName, clip: StringName,
		response := Response.DEFAULT) -> bool:
	if clip.is_empty() or material == &"body":
		return false
	if can_choose_response(material) and response != Response.DEFAULT:
		return response == Response.STOP
	return weapon_type == "mace_2h" and material != &"breakable"


func set_feedback(material: StringName, charged: bool, clip := &"", response := Response.DEFAULT) -> void:
	var changed_clip := _charged != charged or _selected_clip != clip
	_material = material
	_response = response if can_choose_response(material) else Response.DEFAULT
	_charged = charged
	_selected_clip = clip
	if _stage != null:
		if changed_clip:
			_select_clip()
		_style_target()
		_configure_contact()
		replay()


func set_looping(enabled: bool) -> void:
	_looping = enabled
	if enabled and not _playing:
		_clock = 0.0
		_playing = true
		_update_processing()


func replay() -> void:
	# Input changes show the edited impact immediately. Later loops include the windup.
	_clock = _impact_time
	_playing = true
	_rebound = null
	_stop_channels.clear()
	_apply_frame()
	_update_processing()


func _ready() -> void:
	_editor_scale = EditorInterface.get_editor_scale() if Engine.is_editor_hint() else 1.0
	_update_frame_size()
	resized.connect(_update_frame_size)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(_update_visibility)
	_update_visibility()


func _update_frame_size() -> void:
	custom_minimum_size.y = roundf(clampf(size.x * 0.37, 148.0 * _editor_scale, 170.0 * _editor_scale))


func _update_visibility() -> void:
	if is_visible_in_tree() and _stage == null and _scene != null:
		_build_stage()
	if _stage != null:
		_stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS if is_visible_in_tree() \
			else SubViewport.UPDATE_DISABLED
	_update_processing()


func _update_processing() -> void:
	set_process(_stage != null and is_visible_in_tree() and _playing)


func _build_stage() -> void:
	_stage = SubViewport.new()
	_stage.name = "HitShakeViewport"
	_stage.own_world_3d = true
	add_child(_stage)
	_build_room()
	_camera = Camera3D.new()
	_camera.name = "PreviewCamera"
	_camera.fov = 60.0
	_camera.near = 0.045
	_stage.add_child(_camera)
	_camera.current = true
	_add_reticle()

	_weapon = _scene.instantiate() as Node3D
	_weapon_mount = _weapon.transform
	_arm_rig = _weapon.get_node_or_null("PreviewArmRig") as ArmRig
	_prepare_weapon(_weapon)
	_camera.add_child(_weapon)
	_pose = _weapon.get_node_or_null("Pose") as Node3D
	_trace_root = _weapon.get_node_or_null("Pose/TraceRoot") as Marker3D
	_trace_tip = _weapon.get_node_or_null("Pose/TraceTip") as Marker3D
	_camera_motion = _weapon.get_node_or_null("CameraMotion") as Node3D
	_animation_player = _weapon.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _animation_player != null:
		_animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_animation_player.speed_scale = 0.0
	_select_clip()
	_style_target()
	_configure_contact()
	_apply_frame()


func _prepare_weapon(node: Node) -> void:
	if node == _arm_rig:
		node.set_meta(&"workbench_hit_shake_preview", true)
	else:
		node.set_script(null)
	for connection: Dictionary in node.get_incoming_connections():
		connection.signal.disconnect(connection.callable)
	if node is Timer or node is AnimationPlayer or node is CollisionObject3D:
		node.process_mode = Node.PROCESS_MODE_DISABLED
	for child in node.get_children():
		_prepare_weapon(child)


func _select_clip() -> void:
	_clip = &""
	_clip_length = 0.0
	_impact_time = 0.27
	_travel = Vector3.FORWARD
	_contact_point = DEFAULT_CONTACT
	_minimum_recovery = 0.0
	if _animation_player == null:
		return
	var source := HitShake.source_clip(_selected_clip)
	var mirrored := source != _selected_clip
	_weapon.transform = WeaponView.DUAL_OFFHAND_MOUNT if mirrored else _weapon_mount
	var prefix := "heavy" if _charged else "light"
	var preferred := StringName(prefix + "_left")
	if not source.is_empty() and HitShake.is_charged_motion(source) == _charged and _animation_player.has_animation(source):
		_clip = source
	elif _animation_player.has_animation(preferred):
		_clip = preferred
	else:
		for candidate: StringName in _animation_player.get_animation_list():
			if String(candidate).begins_with(prefix):
				_clip = candidate
				break
	if _clip == &"":
		if _animation_player.has_animation(&"idle"):
			_sample_weapon(&"idle", 0.0)
		return
	var animation := _animation_player.get_animation(_clip)
	_clip_length = animation.length
	var timeline := Timeline.read(animation) as Timeline
	_impact_time = timeline.impact if timeline != null else _clip_length * 0.4
	if timeline == null and animation.has_marker(Timeline.IMPACT):
		_impact_time = animation.get_marker_time(Timeline.IMPACT)
	if _weapon_type == "mace_2h" and not _charged and timeline != null:
		var link_time := maxf(timeline.trace_end, timeline.input_buffer)
		_minimum_recovery = maxf(0.0, link_time - _impact_time) * WeaponRoles.commitment_timing(_weapon_type, false) + 0.10

	if _trace_root == null or _trace_tip == null:
		return
	var before := _sample_trace(maxf(0.0, _impact_time - TRACE_SAMPLE_STEP))
	var after := _sample_trace(minf(_clip_length, _impact_time + TRACE_SAMPLE_STEP))
	_contact_point = _sample_trace(_impact_time)
	var direction := (after - before).normalized()
	_travel = Vector3.FORWARD if direction.is_zero_approx() else direction


func _sample_trace(seconds: float) -> Vector3:
	_sample_weapon(_clip, seconds)
	return _camera.to_local((_trace_root.global_position + _trace_tip.global_position) * 0.5)


func _configure_contact() -> void:
	_stops_weapon = stops_weapon(_weapon_type, _material, _clip, _response)
	_contact_normal = Vector3.ZERO if _material == &"body" else (Vector3.BACK - _travel).normalized()
	var point_side := _contact_point.normalized().x
	_kick = _profiles.kick_degrees(_weapon_type, _material, _charged, _travel, _contact_normal,
		point_side, 1, false, _selected_clip)
	if _response == Response.THROUGH and (_material in STATIC_SURFACES or not _charged):
		_kick = Vector4.ZERO
	_pulse = HitShake.pulse_for(_weapon_type, _material, _selected_clip)
	_duration = _kick.w
	var facing := Vector3.BACK if _contact_normal.is_zero_approx() else _contact_normal
	var up := Vector3.UP if absf(facing.y) < 0.96 else Vector3.FORWARD
	_target.transform = Transform3D(Basis.looking_at(-facing, up), _contact_point - facing * 0.065)
	var bottom := -1.46
	var top := _target.position.y - absf(_target.basis.y.y) * 0.395
	var height := maxf(0.08, top - bottom)
	_pedestal.position = Vector3(_target.position.x, bottom + height * 0.5, _target.position.z)
	(_pedestal.mesh as BoxMesh).size.y = height


func _sample_weapon(clip: StringName, seconds: float) -> void:
	if _animation_player.current_animation != clip:
		_animation_player.play(clip)
	_animation_player.seek(seconds, true, true)


func _process(delta: float) -> void:
	_clock += delta
	var finish_time := _clip_length
	if _stops_weapon:
		if _rebound != null:
			finish_time = _impact_time + _rebound.duration
		elif _weapon_type != "mace_2h":
			finish_time = _impact_time + GENERIC_STOP_SECONDS
	var cycle_end := maxf(finish_time, _impact_time + _duration) + IDLE_GAP
	if _clock >= cycle_end:
		if _looping:
			_clock = fposmod(_clock, cycle_end)
			_rebound = null
			_stop_channels.clear()
		else:
			_clock = cycle_end
			_playing = false
			_update_processing()
	_apply_frame()


func _apply_frame() -> void:
	if _camera == null:
		return
	var elapsed := _clock - _impact_time
	if _stops_weapon and elapsed >= 0.0:
		if _weapon_type == "mace_2h":
			if _rebound == null:
				_rebound = Rebound.new(_animation_player, _pose, _clip,
					_impact_time, &"idle", _weapon, _travel, _material, _charged, _minimum_recovery,
					_weapon.basis.inverse() * _contact_normal)
			_rebound.sample(minf(elapsed, _rebound.duration), _clock)
		else:
			_sample_generic_stop(elapsed)
	elif not _clip.is_empty():
		_rebound = null
		_stop_channels.clear()
		_sample_weapon(_clip, minf(_clock, _clip_length))
	if _arm_rig != null:
		_arm_rig.apply_to_grip(_pose, _rebound.arm_ik_blend if _rebound != null else 1.0)
	var swing_basis := Basis.IDENTITY if _camera_motion == null else Basis(_camera_motion.quaternion)
	var shake := Vector3.ZERO
	if elapsed >= 0.0 and elapsed < _duration:
		shake = HitShake.pulse_offset(Vector3.ZERO, Vector3(_kick.x, _kick.y, _kick.z) * (PI / 180.0),
			elapsed, _duration, _pulse)
	_camera.basis = Basis.from_euler(shake, _camera.rotation_order) * swing_basis
	_target_material.emission_energy_multiplier = 0.32 * (1.0 - smoothstep(0.015, 0.15, elapsed)) \
		if elapsed >= 0.0 else 0.0


func _sample_generic_stop(elapsed: float) -> void:
	if _stop_channels.is_empty():
		_sample_weapon(_clip, _impact_time)
		_stop_channels = ChargeReturn.capture_channels(_animation_player, [_clip, &"idle"])
	if not _animation_player.has_animation(&"idle"):
		return
	var idle_length := _animation_player.get_animation(&"idle").length
	_sample_weapon(&"idle", fposmod(_clock, idle_length))
	var blend := smoothstep(0.0, GENERIC_STOP_SECONDS, elapsed)
	for channel in _stop_channels:
		channel.write(channel.initial.interpolate_with(channel.read(), blend))


func _style_target() -> void:
	var surface: Array = SURFACES.get(_material, SURFACES[&"stone"])
	_target_material.albedo_color = surface[0]
	_target_material.metallic = surface[1]
	_target_material.roughness = surface[2]
	_target_material.albedo_texture = STONE if _material == &"stone" or _material == &"mass" else null


func _build_room() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#3b454e")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#c1d1df")
	environment.ambient_light_energy = 0.80
	var world := WorldEnvironment.new()
	world.environment = environment
	_stage.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, -38.0, 0.0)
	key.light_color = Color("#ffe0b1")
	key.light_energy = 1.15
	_stage.add_child(key)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.44, 0.53, 0.37)
	fill.light_color = Color("#ffe7ce")
	fill.light_energy = 2.25
	fill.light_specular = 0.12
	fill.omni_range = 4.0
	_stage.add_child(fill)

	var stone := StandardMaterial3D.new()
	stone.albedo_texture = STONE
	stone.roughness = 0.94
	stone.uv1_scale = Vector3(6.0, 2.0, 1.0)
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color("#575951")
	trim.roughness = 0.80
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color("#b69b6b")
	brass.metallic = 0.28
	_box(Vector3(28.0, 0.15, 7.0), Vector3(0.0, -1.55, -3.30), stone)
	_box(Vector3(32.0, 6.20, 0.18), Vector3(0.0, 1.38, -5.0), stone)
	_box(Vector3(31.9, 0.065, 0.14), Vector3(0.0, -0.42, -4.88), trim)
	_box(Vector3(31.9, 0.065, 0.14), Vector3(0.0, 0.70, -4.88), trim)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.26, 3.44, 0.30), Vector3(side * 1.45, 0.15, -4.68), trim)
		_box(Vector3(0.55, 0.11, 0.34), Vector3(side * 1.45, -0.31, -4.59), brass)
		_box(Vector3(0.09, 0.035, 3.15), Vector3(side * 0.67, -1.45, -2.57), brass)

	_target_material = StandardMaterial3D.new()
	_target_material.emission_enabled = true
	_target_material.emission = Color("#f6b963")
	_target_material.emission_energy_multiplier = 0.0
	_target = Node3D.new()
	_stage.add_child(_target)
	_box(Vector3(0.65, 0.79, 0.13), Vector3.ZERO, _target_material, _target)
	_box(Vector3(0.77, 0.91, 0.11), Vector3(0.0, 0.0, -0.11), trim, _target)
	_pedestal = _box(Vector3(0.16, 1.02, 0.19), Vector3.ZERO, trim)
	for side in [-1.0, 1.0]:
		_box(Vector3(0.033, 0.75, 0.020), Vector3(side * 0.293, 0.0, 0.072), brass, _target)
		_box(Vector3(0.56, 0.033, 0.020), Vector3(0.0, side * 0.359, 0.072), brass, _target)


func _box(dimensions: Vector3, position: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = material
	piece.position = position
	if parent == null:
		_stage.add_child(piece)
	else:
		parent.add_child(piece)
	return piece


func _add_reticle() -> void:
	var reticle := Control.new()
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(reticle)
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	for size_in_pixels in [Vector2(9.0, 1.0), Vector2(1.0, 9.0)]:
		var stroke := ColorRect.new()
		stroke.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stroke.color = Color("#f6e5becc")
		stroke.size = size_in_pixels
		stroke.position = -size_in_pixels * 0.5
		reticle.add_child(stroke)
