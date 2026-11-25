@tool
class_name BloodGpuEffectScene
extends Node3D
## Standalone effect that plays the GPUParticles3D children authored below it.

const Layer = preload("res://addons/godot-dismemberment/effects/scenes/blood_gpu_emitter_layer.gd")
const CollisionParticles = preload("res://addons/godot-dismemberment/effects/scenes/blood_gpu_collision_particles.gd")
const ContactReceiver = preload("res://addons/godot-dismemberment/effects/scenes/blood_gpu_contact_receiver.gd")
const Schedule = preload("res://addons/godot-dismemberment/effects/scenes/blood_gpu_effect_schedule.gd")

## Unique name used to find this effect in the effect library.
@export var system_name: StringName
## Category used to find an effect by family and intensity.
@export var family: StringName = &"burst"
## Intensity used when the library selects a variant. Particle counts are set on each emitter.
@export_range(0, 3, 1) var intensity := 1
## Start the effect automatically when it enters the running scene.
@export var autoplay := true
## Default launch direction when Play Effect or autoplay supplies no direction.
@export var preview_direction := Vector3.RIGHT
## Replay continuous inherited motion from physics poses, in source-step order.
## Update the source transform before this scene's physics callback. Requires a compatible 60 Hz process material.
@export var physics_owned_source := false
## Physics layers hit by this scene's authored collision emitters during gameplay.
@export_flags_3d_physics var collision_mask := 1
## Play the effect in the editor viewport using Preview Direction.
@export_tool_button("Play Effect") var preview_effect := play
## Stop new emissions and let active particles finish their lifetimes.
@export_tool_button("Stop Emission") var stop_effect := stop

var _schedule := Schedule.new()
var _base_materials: Dictionary[GPUParticles3D, Material] = {}
var _bound_draw_materials: Dictionary[GPUParticles3D, Material] = {}
var _bound_process_materials: Dictionary[GPUParticles3D, Material] = {}
var _bound_motion_materials: Dictionary[GPUParticles3D, Material] = {}
var _bound_motion_order: Dictionary[GPUParticles3D, bool] = {}
var _collision_particles := CollisionParticles.new()
var _contact_proxy: Node3D
var _can_emit := false
var _play_revision := 0
var _preview_emitters: Array[Layer] = []
var _preview_nodes: Dictionary[int, Layer] = {}

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if not Layer.supports_gpu():
		return
	if not Engine.is_editor_hint():
		_prepare_depth.call_deferred()
		for child in get_children():
			var emitter := child as Layer
			if emitter != null and _uses_host_clock(emitter, emitter.get_blood_settings()):
				_prepare_host_emitter(emitter)
	_prepare_renderers()
	if not Engine.is_editor_hint() and autoplay:
		play.call_deferred()

func _prepare_depth() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		var emitter := child as Layer
		if emitter == null or not emitter.use_scene_depth_collision:
			continue
		var layer := emitter.get_blood_settings()
		var depth := Layer.depth_backend(self, emitter, layer, emitter.material_override)
		if depth != null:
			depth.prepare_layer(emitter, layer, emitter.material_override)

## Play from the scene root. A negative duration follows the authored loops until stopped.
func play(direction := Vector3.ZERO, size_scale := 1.0, duration := -1.0) -> int:
	if not is_inside_tree() or not Layer.supports_gpu() or size_scale <= 0.0:
		return 0
	_play_revision += 1
	if Engine.is_editor_hint():
		_play_editor_preview(_play_revision, direction, size_scale, duration)
		return 0
	if not _can_emit:
		_play_after_render.call_deferred(_play_revision, direction, size_scale, duration)
		return 0
	return _play_now(direction, size_scale, duration)

func _prepare_renderers() -> void:
	await RenderingServer.frame_post_draw
	_can_emit = true

func _play_after_render(revision: int, direction: Vector3, size_scale: float, duration: float) -> void:
	while not _can_emit and is_inside_tree() and revision == _play_revision:
		await RenderingServer.frame_post_draw
	if revision == _play_revision and _can_emit and is_inside_tree():
		_play_now(direction, size_scale, duration)

func _play_editor_preview(revision: int, direction: Vector3, size_scale: float, duration: float) -> void:
	_schedule.clear()
	_retire_preview_emitters()
	for child in get_children():
		var authored := child as Layer
		if authored == null:
			continue
		var preview := authored.duplicate(Node.DUPLICATE_SCRIPTS) as Layer
		preview.emitting = false
		add_child(preview, false, Node.INTERNAL_MODE_BACK)
		_preview_emitters.append(preview)
		_preview_nodes[preview.get_instance_id()] = preview
	# A GPUParticles3D must be rendered once before its first manual emission.
	await RenderingServer.frame_post_draw
	if revision == _play_revision and is_inside_tree():
		_play_now(direction, size_scale, duration, _preview_emitters)

func _retire_preview_emitters() -> void:
	var retiring := _preview_emitters
	_preview_emitters = []
	if not is_inside_tree():
		return
	for emitter in retiring:
		# Keep the material and transform of the already emitted particles.
		_retire_preview_when_idle(emitter.get_instance_id())

func _retire_preview_when_idle(id: int) -> void:
	while is_inside_tree():
		await get_tree().create_timer(0.25).timeout
		var emitter: Layer = _preview_nodes.get(id)
		if not is_inside_tree() or not is_instance_valid(emitter):
			return
		if RenderingServer.particles_is_inactive(emitter.get_base()):
			_discard_preview_emitter(emitter)
			return

func _discard_preview_emitter(emitter: Layer) -> void:
	_preview_nodes.erase(emitter.get_instance_id())
	_base_materials.erase(emitter)
	_bound_draw_materials.erase(emitter)
	_bound_process_materials.erase(emitter)
	_bound_motion_materials.erase(emitter)
	_bound_motion_order.erase(emitter)
	emitter.queue_free()

func _play_now(direction: Vector3, size_scale: float, duration: float, editor_emitters: Array[Layer] = []) -> int:
	_schedule.clear()
	var launch := _preview_launch(direction)
	var submitted := 0
	var ordered := physics_owned_source and not Engine.is_editor_hint()
	var receivers: Dictionary[StringName, Array] = {}
	if collision_mask != 0 and not Engine.is_editor_hint():
		receivers = ContactReceiver.read_node_receivers(self)
	var limited_sources := CollisionParticles.tick_limited_sources(receivers)
	var receiver_state := CollisionParticles.FrameBudget.new() if not limited_sources.is_empty() else null
	var emitters: Array[Node] = get_children()
	if Engine.is_editor_hint():
		emitters.assign(editor_emitters)
	for child in emitters:
		var emitter := child as Layer
		if emitter == null:
			continue
		var layer := emitter.get_blood_settings()
		if not layer.enabled or not layer.visible or not layer.contact_source.is_empty():
			continue
		if _uses_host_clock(emitter, layer):
			_prepare_host_emitter(emitter)
			layer[&"source_rays_host_tick"] = _collision_particles.track_host_emitter(
				emitter, maxf(layer.particle_lifetime.x, layer.particle_lifetime.y))
		var pose := Layer.launch_pose(family, launch, size_scale, global_position,
			layer.source_motion, global_basis.y)
		pose.basis = pose.basis.scaled_local(global_basis.get_scale().abs())
		if not layer.source_motion:
			submitted += Layer.emit_layer(emitter, layer, pose)
			continue
		var authored_material: Material = _base_materials.get(emitter, emitter.material_override) if _bound_draw_materials.get(emitter) == emitter.material_override else emitter.material_override
		var depth := Layer.depth_backend(self, emitter, layer, authored_material)
		if depth != null:
			var emitted: int = depth.emit_layer(emitter, layer, pose, size_scale, get_instance_id(), authored_material)
			if emitted > 0:
				submitted += emitted
				continue
		_bind_draw_material(emitter, layer)
		emitter.bind_source_attachment(layer)
		var callback := Callable()
		var id_provider := Callable()
		if not Engine.is_editor_hint() and collision_mask != 0 and (layer.collision_events or layer.collision_kill):
			_prepare_contact_proxy()
			if _contact_proxy != null:
				callback = _submit_contacts.bind(receivers, receiver_state, size_scale)
				if layer.collision_kill:
					_bind_collision_material(emitter)
					id_provider = _collision_particles.allocate
		if layer.continuous_inherit_velocity != 0.0:
			if _bound_motion_materials.get(emitter) != emitter.process_material or (ordered and not _bound_motion_order.get(emitter, false)):
				var previous := emitter.process_material
				emitter.process_material = _schedule.bind_inherited_motion(previous, ordered)
				_bound_motion_materials[emitter] = emitter.process_material
				_bound_motion_order[emitter] = ordered
				if _bound_process_materials.get(emitter) == previous:
					_bound_process_materials[emitter] = emitter.process_material
		var provider := _current_launch_pose.bind(direction, size_scale)
		var ordered_budget := receiver_state if limited_sources.size() == 1 and limited_sources[0] == layer.emitter_name else null
		submitted += _schedule.begin(emitter, layer, pose, duration, callback, provider, 0, id_provider, ordered, ordered_budget, size_scale)
	set_process(not _schedule.is_empty() or _collision_particles.has_host_emitters())
	set_physics_process(_schedule.has_physics_sources() or _collision_particles.has_host_emitters())
	return submitted

func _preview_launch(direction: Vector3) -> Vector3:
	var forward := direction if not direction.is_zero_approx() else global_basis * preview_direction
	return -forward if family == &"hit" else forward

func _current_launch_pose(direction: Vector3, size_scale: float) -> Dictionary:
	var launch := _preview_launch(direction)
	var pose := Layer.launch_pose(family, launch, size_scale, global_position, true, global_basis.y)
	pose.basis = pose.basis.scaled_local(global_basis.get_scale().abs())
	return {&"pose": pose}

func _bind_draw_material(emitter: GPUParticles3D, layer: Dictionary) -> void:
	if not _bound_draw_materials.has(emitter) or emitter.material_override != _bound_draw_materials[emitter]:
		_base_materials[emitter] = emitter.material_override
	emitter.material_override = Layer.bind_visual_curves(_base_materials[emitter], layer)
	_bound_draw_materials[emitter] = emitter.material_override

func _bind_collision_material(emitter: GPUParticles3D) -> void:
	if _bound_process_materials.get(emitter) == emitter.process_material:
		return
	emitter.process_material = _collision_particles.bind_material(emitter.process_material)
	_bound_process_materials[emitter] = emitter.process_material

func _prepare_host_emitter(emitter: GPUParticles3D) -> void:
	# Changing fixed FPS frees the renderer's particle buffers, even at the same value.
	if emitter.fixed_fps != 0:
		emitter.fixed_fps = 0
	emitter.interpolate = false
	emitter.fract_delta = false
	_bind_collision_material(emitter)

func _uses_host_clock(emitter: GPUParticles3D, layer: Dictionary) -> bool:
	return Layer.supports_host_clock(layer, emitter.process_material, emitter.local_coords,
		emitter.speed_scale, emitter.preprocess)

func _prepare_contact_proxy() -> void:
	if _contact_proxy != null:
		_contact_proxy.set(&"allowed_surface_types_for_blood_decals", collision_mask)
		return
	if not ClassDB.class_has_method(&"GoreComponent", &"dispatch_blood_effect_contacts"):
		return
	_contact_proxy = ClassDB.instantiate(&"GoreComponent") as Node3D
	_contact_proxy.set(&"enable_blood_particles", false)
	_contact_proxy.set(&"allowed_surface_types_for_blood_decals", collision_mask)
	add_child(_contact_proxy, false, Node.INTERNAL_MODE_BACK)

func _submit_contacts(samples: Array[Dictionary], receivers: Dictionary,
		receiver_state: CollisionParticles.FrameBudget, size_scale: float) -> void:
	if not is_instance_valid(_contact_proxy):
		return
	for sample in samples:
		sample[&"family"] = family
		sample[&"scale"] = size_scale
		sample[&"receiver_state"] = receiver_state
		sample[&"receivers"] = receivers.get(sample.layer, [])
	_contact_proxy.call(&"dispatch_blood_effect_contacts", self, samples)

func retire_collided_particle(id: int) -> void:
	_collision_particles.retire(id)
	set_process(true)

func emit_contact_layer(layer_id: StringName, position: Vector3, normal: Vector3,
		size_scale: float, _scene: PackedScene = null) -> bool:
	for child in get_children():
		var emitter := child as Layer
		if emitter != null and emitter.emitter_name == layer_id:
			var layer := emitter.get_blood_settings()
			var pose := Layer.launch_pose(family, normal, size_scale, position, layer.source_motion)
			_bind_draw_material(emitter, layer)
			return Layer.emit_layer(emitter, layer, pose) > 0
	return false

func _process(delta: float) -> void:
	_schedule.advance(delta)
	_collision_particles.advance(delta)
	if _schedule.is_empty() and not _collision_particles.has_host_emitters():
		set_process(false)

func _physics_process(delta: float) -> void:
	_schedule.advance_physics(delta)
	_collision_particles.advance_host_physics(delta)
	if not _schedule.has_physics_sources() and not _collision_particles.has_host_emitters():
		set_physics_process(false)

## Stops spawning new particles. Previously spawned particles finish their lifetimes.
func stop() -> void:
	_play_revision += 1
	_schedule.clear()
	_retire_preview_emitters()
	set_process(_collision_particles.has_host_emitters())
	set_physics_process(_collision_particles.has_host_emitters())

func _exit_tree() -> void:
	Layer.clear_depth_owner(self)
	_play_revision += 1
	_schedule.clear()
	if Engine.is_editor_hint():
		_preview_emitters.clear()
		for emitter in _preview_nodes.values():
			if is_instance_valid(emitter):
				_discard_preview_emitter(emitter)
		_preview_nodes.clear()
