extends Node3D
## Blends the authored idle, walk, windup and strike poses with the live combat state.

class BoneTrack:
	var index: int
	var rest_position: Vector3
	var rest_rotation: Quaternion
	var rotation: bool
	var tracks := PackedInt32Array()

const CLIPS: Array[StringName] = [&"Idle", &"Walk", &"Windup", &"Strike"]
const WINDUP_PREFIX := "Windup_"
const STRIKE_PREFIX := "Strike_"
const Feedback := preload("res://data/combat_feedback.tres")
const RarityStyle := preload("res://data/enemy_rarity_style.tres")
const RarityShader := preload("res://combat/effects/enemy_rarity_accent.gdshader")

static var _rarity_materials: Dictionary[Material, Dictionary] = {}
static var _hit_overlay: StandardMaterial3D

@export var guard_base_glow: Material
@export var guard_tip_glow: Material

var _clips: Array[Animation] = []
var _attack_clips: Dictionary[StringName, Vector2i] = {}
var _attack_pair := Vector2i(2, 3)
var _motion: Array[BoneTrack] = []
var _skeleton: Skeleton3D
var _surfaces: Array[MeshInstance3D] = []
var _surface_overlays: Array[Material] = []
var _thornback_spike_bases: Array[MeshInstance3D] = []
var _thornback_spike_tips: Array[MeshInstance3D] = []
var _spike_materials: Dictionary[MeshInstance3D, Material] = {}
var _flash_time := 0.0
var _phase := 0.0
var _reaction_bones: Dictionary[int, float] = {}
var _reaction_rest := Transform3D.IDENTITY
var _reaction_direction := Vector3.ZERO
var _reaction_axis := Vector3.ZERO
var _reaction_amount := 0.0
var _reaction_frame := 0.0
var _reaction_time := 0.0


func _ready() -> void:
	set_process(false)


func configure(rarity: String) -> void:
	_bind_motion()
	_reaction_rest = transform
	for child in find_children("*", "MeshInstance3D"):
		var surface := child as MeshInstance3D
		_surfaces.append(surface)
		_surface_overlays.append(surface.material_overlay)
		if rarity in ["magic", "rare"]:
			if surface.material_override is StandardMaterial3D:
				surface.material_override = _accent_material(surface.material_override, rarity)
			elif surface.material_override == null and surface.mesh != null:
				for index in surface.mesh.get_surface_count():
					var material := surface.get_active_material(index)
					if material is StandardMaterial3D:
						surface.set_surface_override_material(index, _accent_material(material, rarity))
		var spike_tag: String = surface.get_meta("guard_spike", "")
		if surface.name == &"GuardSpikeShell":
			spike_tag = "base"
		elif surface.name == &"GuardSpikeTips":
			spike_tag = "tip"
		match spike_tag:
			"base":
				_thornback_spike_bases.append(surface)
				_spike_materials[surface] = surface.material_override
			"tip":
				_thornback_spike_tips.append(surface)
				_spike_materials[surface] = surface.material_override


func _bind_motion() -> void:
	if not _clips.is_empty():
		return
	var rig := get_node_or_null("Rig")
	if rig == null:
		return
	var player := rig.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player == null:
		return
	var animation_root := player.get_node_or_null(player.root_node)
	if animation_root == null:
		return
	var skeletons := rig.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return
	_skeleton = skeletons[0] as Skeleton3D
	var skeleton_path := StringName(animation_root.get_path_to(_skeleton))
	for clip_name in CLIPS:
		var clip := player.get_animation(clip_name) if player.has_animation(clip_name) else null
		_clips.append(clip)
	for clip_name in player.get_animation_list():
		if not clip_name.begins_with(WINDUP_PREFIX):
			continue
		var ability := StringName(clip_name.trim_prefix(WINDUP_PREFIX))
		var release_name := StringName(STRIKE_PREFIX + ability)
		if not player.has_animation(release_name):
			continue
		_attack_clips[ability] = Vector2i(_clips.size(), _clips.size() + 1)
		_clips.append(player.get_animation(clip_name))
		_clips.append(player.get_animation(release_name))
	var channels: Dictionary[Vector2i, BoneTrack] = {}
	for clip_index in _clips.size():
		var clip := _clips[clip_index]
		if clip == null:
			continue
		for track_index in clip.get_track_count():
			var type := clip.track_get_type(track_index)
			if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D]:
				continue
			var path := clip.track_get_path(track_index)
			if path.get_subname_count() != 1 or not clip.track_is_enabled(track_index):
				continue
			if path.get_concatenated_names() != skeleton_path:
				continue
			var bone := _skeleton.find_bone(path.get_subname(0))
			if bone < 0 or clip.track_get_key_count(track_index) == 0:
				continue
			var key := Vector2i(bone, type)
			var channel: BoneTrack = channels.get(key)
			if channel == null:
				channel = BoneTrack.new()
				channel.index = bone
				channel.rest_position = _skeleton.get_bone_rest(bone).origin
				channel.rest_rotation = _skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
				channel.rotation = type == Animation.TYPE_ROTATION_3D
				channel.tracks.resize(_clips.size())
				channel.tracks.fill(-1)
				channels[key] = channel
				_motion.append(channel)
			channel.tracks[clip_index] = track_index
	for channel: BoneTrack in _motion:
		if channel.rotation:
			var bone_name := String(_skeleton.get_bone_name(channel.index)).to_lower()
			if bone_name.begins_with("head") or bone_name.begins_with("neck"):
				_reaction_bones[channel.index] = -0.55
			elif (bone_name.begins_with("chest") or bone_name.begins_with("spine")
					or bone_name in ["body", "thorax", "torso"]):
				_reaction_bones[channel.index] = 0.66


## Use the matching Windup and Strike clips when the model has an authored ability pair.
func select_attack_animation(ability: StringName) -> void:
	_attack_pair = _attack_clips.get(ability, Vector2i(2, 3))


func strike_clip() -> Animation:
	return _clips[_attack_pair.y] if _clips.size() > _attack_pair.y else null


func animate(delta: float, movement: float, windup: float, strike: float) -> void:
	_phase = fposmod(_phase + delta * (2.8 + movement * 7.1) / TAU, 1.0)
	var releasing := strike >= 0.0
	var release_blend := smoothstep(0.0, 0.18, strike)
	var settle := smoothstep(0.78, 1.0, strike)
	var windup_phase := 1.0 if releasing else windup
	for channel in _motion:
		if channel.rotation:
			var bone_rotation := channel.rest_rotation * _rotation_offset(channel, 0, _phase)
			if movement > 0.0:
				bone_rotation *= Quaternion.IDENTITY.slerp(_rotation_offset(channel, 1, _phase), movement)
			if windup_phase > 0.0:
				var motion := _rotation_offset(channel, _attack_pair.x, windup_phase)
				if releasing:
					motion = motion.slerp(_rotation_offset(channel, _attack_pair.y, strike), release_blend)
					motion = motion.slerp(Quaternion.IDENTITY, settle)
				bone_rotation *= motion
			var reaction_weight := _reaction_bones.get(channel.index, 0.0) as float
			if not is_zero_approx(_reaction_frame * reaction_weight):
				var axis := channel.rest_rotation.inverse() * _reaction_axis
				bone_rotation *= Quaternion(axis, _reaction_frame * Feedback.reaction_joint_share * reaction_weight)
			_skeleton.set_bone_pose_rotation(channel.index, bone_rotation.normalized())
		else:
			var bone_position := channel.rest_position + _position_offset(channel, 0, _phase)
			if movement > 0.0:
				bone_position += _position_offset(channel, 1, _phase) * movement
			if windup_phase > 0.0:
				var motion := _position_offset(channel, _attack_pair.x, windup_phase)
				if releasing:
					motion = motion.lerp(_position_offset(channel, _attack_pair.y, strike), release_blend)
					motion *= 1.0 - settle
				bone_position += motion
			_skeleton.set_bone_pose_position(channel.index, bone_position)


func _rotation_offset(channel: BoneTrack, clip_index: int, phase: float) -> Quaternion:
	var track := channel.tracks[clip_index]
	if track < 0:
		return Quaternion.IDENTITY
	var clip := _clips[clip_index]
	return channel.rest_rotation.inverse() * clip.rotation_track_interpolate(track, phase * clip.length)


func _position_offset(channel: BoneTrack, clip_index: int, phase: float) -> Vector3:
	var track := channel.tracks[clip_index]
	if track < 0:
		return Vector3.ZERO
	var clip := _clips[clip_index]
	return clip.position_track_interpolate(track, phase * clip.length) - channel.rest_position


func _process(delta: float) -> void:
	if _flash_time > 0.0:
		_flash_time = maxf(0.0, _flash_time - delta)
		if _flash_time == 0.0:
			for index in _surfaces.size():
				_surfaces[index].material_overlay = _surface_overlays[index]
	if _reaction_time > 0.0:
		_reaction_time = maxf(0.0, _reaction_time - delta)
		var blend: float = Feedback.response_at(1.0 - _reaction_time / Feedback.reaction_duration) * _reaction_amount
		_reaction_frame = deg_to_rad(Feedback.reaction_tilt) * blend
		position = _reaction_rest.origin + _reaction_direction * (Feedback.reaction_travel * blend)
		basis = Basis(_reaction_axis, _reaction_frame) * _reaction_rest.basis
		if _reaction_time <= 0.0:
			_reaction_frame = 0.0
			transform = _reaction_rest
	set_process(_flash_time > 0.0 or _reaction_time > 0.0)


func react_to_hit(world_travel: Vector3, heavy: bool) -> void:
	var local := get_parent_node_3d().global_basis.inverse() * world_travel
	var side := Feedback.direction_weights
	if absf(local.x) > absf(local.z):
		_reaction_direction = Vector3.RIGHT if local.x > 0.0 else Vector3.LEFT
		_reaction_amount = side.z if local.x > 0.0 else side.w
	else:
		_reaction_direction = Vector3.BACK if local.z >= 0.0 else Vector3.FORWARD
		_reaction_amount = side.x if local.z >= 0.0 else side.y
	_reaction_axis = Vector3.UP.cross(_reaction_direction)
	_reaction_amount *= Feedback.charged_reaction_factor if heavy else 1.0
	_reaction_time = Feedback.reaction_duration
	set_process(true)


func flash() -> void:
	if not _hit_overlay:
		_hit_overlay = StandardMaterial3D.new()
		_hit_overlay.roughness = 1.0
		_hit_overlay.metallic_specular = 0.0
		_hit_overlay.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hit_overlay.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hit_overlay.albedo_color = Color(1.0, 0.43, 0.31, 0.16)
	if _flash_time <= 0.0:
		set_process(true)
	_flash_time = 0.085
	for surface in _surfaces:
		surface.material_overlay = _hit_overlay


func overlay_without_hit_flash(surface: MeshInstance3D) -> Material:
	if _hit_overlay != null and surface.material_overlay == _hit_overlay:
		var index := _surfaces.find(surface)
		if index >= 0:
			return _surface_overlays[index]
	return surface.material_overlay


func set_thornback_reflecting(active: bool) -> void:
	for spike in _thornback_spike_bases:
		spike.material_override = guard_base_glow if active and guard_base_glow else _spike_materials[spike]
	for spike in _thornback_spike_tips:
		spike.material_override = guard_tip_glow if active and guard_tip_glow else _spike_materials[spike]


static func _accent_material(source: StandardMaterial3D, rarity: String) -> StandardMaterial3D:
	var variants: Dictionary = _rarity_materials.get(source, {})
	if not variants.has(rarity):
		var variant := source.duplicate() as StandardMaterial3D
		variant.next_pass = RarityStyle.make_layer(rarity, source, RarityShader)
		variants[rarity] = variant
		_rarity_materials[source] = variants
	return variants[rarity]
