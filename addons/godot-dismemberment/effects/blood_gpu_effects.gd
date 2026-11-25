extends Node3D
## Pools particle emitters by their authored renderer settings.

const EffectLibrary = preload("res://addons/godot-dismemberment/effects/scenes/blood_gpu_effect_library.gd")
const EmitterLayer = preload("res://addons/godot-dismemberment/effects/scenes/blood_gpu_emitter_layer.gd")
const CollisionParticles = preload("res://addons/godot-dismemberment/effects/scenes/blood_gpu_collision_particles.gd")
const ContactReceiver = preload("res://addons/godot-dismemberment/effects/scenes/blood_gpu_contact_receiver.gd")
const EffectSchedule = preload("res://addons/godot-dismemberment/effects/scenes/blood_gpu_effect_schedule.gd")
const Materials = preload("res://addons/godot-dismemberment/effects/blood_gpu_materials.gd")
const LIFETIME := 2.25
const TIERS := {"low": 0, "med": 1, "mid": 1, "sample": 1, "high": 2, "extreme": 3}

const EFFECT_KEYS := {
	"amputated": &"amputated", "amputatedlimbs": &"amputated",
	"amputatedhead": &"amputated_head", "artery": &"artery",
	"brainburst": &"brain_burst", "burst": &"burst", "bloodburst": &"burst",
	"dripping": &"dripping", "drippingsplash": &"dripping_splash",
	"dynamic": &"dynamic", "drippingdynamic": &"dynamic", "dynamicdripping": &"dynamic",
	"hit": &"hit", "bullethit": &"hit", "slash": &"slash",
	"splash": &"splash", "bloodsplash": &"splash", "splatter": &"splatter",
	"sphericaldecalsplatter": &"spherical_splatter", "sphericalsplatter": &"spherical_splatter", "stab": &"stab",
}

class PoseSample extends RefCounted:
	var source: Callable
	var render_frame := -1
	var physics_frame := -1
	var physics_owned := false
	var render_sample := {}
	var physics_sample := {}

	func get_pose() -> Dictionary:
		if physics_owned and Engine.is_in_physics_frame():
			var current_frame := Engine.get_physics_frames()
			if physics_frame != current_frame:
				physics_frame = current_frame
				physics_sample = source.call() if source.is_valid() else {}
			return physics_sample
		var current_frame := Engine.get_process_frames()
		if render_frame != current_frame:
			render_frame = current_frame
			render_sample = source.call() if source.is_valid() else {}
		return render_sample

## Catalog used to resolve effect requests by name, family, and intensity.
@export var effect_library: EffectLibrary = preload("res://addons/godot-dismemberment/effects/scenes/realistic_blood_library.tres")
## Optional default draw and process materials for the shared emitters.
@export var effect_materials: Materials

var _schedule := EffectSchedule.new()
var _collision_samples: Array[Dictionary] = []
var _cold_emitters: Dictionary[GPUParticles3D, bool] = {}
var _pending_launches: Array[Dictionary] = []
var _warmed_scenes: Dictionary[PackedScene, bool] = {}
var _warmed_libraries: Dictionary[EffectLibrary, Array] = {}
var _effect_count := 0
var _particle_count := 0
var _one_shot_effect: StringName
var _one_shot_direction := Vector3.ZERO
var _one_shot_scale := 1.0
var _one_shot_intensity := 1
var _one_shot_selection: Resource
var _scene_data: Dictionary[PackedScene, Dictionary] = {}
var _node_defaults: Dictionary
var _renderer_defaults: Array[Dictionary] = []
var _variant_emitters: Array[GPUParticles3D] = []
var _variant_settings: Array[Dictionary] = []
var _reservations: Dictionary[GPUParticles3D, Array] = {}
var _attached_sources: Dictionary[GPUParticles3D, Callable] = {}
var _elapsed := 0.0
var _collision_particles := CollisionParticles.new()
var _next_reservation_expiry := INF
@onready var _emitters: Array[GPUParticles3D] = [$Mist, $Sheets, $Drops, $Clots]

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	var draw_materials: Array[Material] = []
	if effect_materials != null:
		draw_materials = [effect_materials.mist_material, effect_materials.sheets_material,
			effect_materials.drops_material, effect_materials.clots_material]
	var particle_defaults := GPUParticles3D.new()
	_node_defaults = EmitterLayer.read_renderer_settings(particle_defaults)
	particle_defaults.free()
	for channel in _emitters.size():
		var emitter := _emitters[channel]
		_mark_emitter_cold(emitter)
		_renderer_defaults.append(EmitterLayer.read_renderer_settings(emitter))
		if effect_materials != null:
			if effect_materials.process_material != null:
				emitter.process_material = effect_materials.process_material
			if draw_materials[channel] != null:
				emitter.material_override = draw_materials[channel]
	if not _one_shot_effect.is_empty() or _one_shot_selection is PackedScene:
		_emit_one_shot.call_deferred()

## Resolves catalog IDs and family aliases, also before _ready.
func classify_effect(effect: StringName, selection: Resource = null) -> StringName:
	var scene := _resolve_effect(effect, 1, selection)
	var data := _get_scene_data(scene)
	return data.get(&"family", &"")

## Accepts a world-space request and an optional library or individual preset.
## Hit directions are incoming. Other effects take the outgoing direction.
## Set physics_owned_source for an authoritative pose provider updated before this pool's physics callback.
## Providers on unsupported materials or renderer settings continue sampling on the render clock.
## Providers may set sprite_scale to override the explicit scale for layers with world sprite sizing.
func emit_effect(effect: StringName, location: Vector3, direction: Vector3, scale: float,
		intensity: int = 1, selection: Resource = null, duration := 0.0, source_id := 0,
		collision_callback := Callable(), pose_provider := Callable(), physics_owned_source := false) -> bool:
	_collision_samples.clear()
	if _emitters.is_empty() or not EmitterLayer.supports_gpu() or not location.is_finite() \
			or not direction.is_finite() or not is_finite(scale) or scale <= 0.0:
		return false
	var scene := _resolve_effect(effect, intensity, selection)
	var data := _get_scene_data(scene)
	if data.is_empty():
		return false

	var shared_provider := Callable()
	var ordered := physics_owned_source and pose_provider.is_valid()
	if pose_provider.is_valid():
		var pose_sample := PoseSample.new()
		pose_sample.source = pose_provider
		pose_sample.physics_owned = ordered
		# The closure keeps the shared sample alive until the last layer stops.
		shared_provider = func() -> Dictionary: return pose_sample.get_pose()
	var accepted := false
	var submitted := 0
	var limited_sources := CollisionParticles.tick_limited_sources(data.get(&"receivers", {}))
	var receiver_state := CollisionParticles.FrameBudget.new() if not limited_sources.is_empty() else null
	for layer: Dictionary in data.layers:
		if not layer.enabled or not layer.visible or layer.channel >= _emitters.size() \
				or not layer.contact_source.is_empty() or not EmitterLayer.has_spawns(layer, duration, pose_provider.is_valid()):
			continue
		var pose := EmitterLayer.launch_pose(data.family, direction, scale, location, layer.source_motion)
		var reservation: Variant = {} if shared_provider.is_valid() else null
		var emitter := _get_emitter(layer, duration, source_id, true, shared_provider.is_valid(), reservation, ordered)
		var layer_provider := Callable()
		if shared_provider.is_valid():
			layer_provider = _sample_reserved_source.bind(shared_provider, reservation)
			if reservation.has(&"attachment_span"):
				layer_provider = _sample_attached_source.bind(emitter, layer_provider, pose, reservation)
		var callback := Callable()
		var id_provider := Callable()
		if layer.collision_events or layer.collision_kill:
			callback = _collect_samples.bind(data, scene, scale, receiver_state, collision_callback)
			if layer.collision_kill:
				id_provider = _collision_particles.allocate
		var ordered_budget := receiver_state if collision_callback.is_valid() and limited_sources.size() == 1 \
				and limited_sources[0] == layer.emitter_name else null
		var launch := _submit_layer.bind(emitter, layer, pose, duration, source_id, callback, layer_provider, id_provider,
			ordered, ordered_budget, scale)
		submitted += _launch_when_ready(emitter, source_id, launch)
		accepted = true

	if not accepted:
		return false
	set_process(true)
	set_physics_process(_schedule.has_physics_sources() or _collision_particles.has_host_emitters())
	_particle_count += submitted
	_effect_count += 1
	return true

func _sample_reserved_source(provider: Callable, reservation: Dictionary) -> Dictionary:
	var pose: Dictionary = provider.call()
	if pose.is_empty():
		_release_reservation(reservation)
	return pose

func _sample_attached_source(emitter: GPUParticles3D, provider: Callable, fallback: Transform3D,
		reservation: Dictionary) -> Dictionary:
	var first_sample: bool = not reservation.has(&"attachment_started")
	var source: Dictionary = provider.call()
	var entries: Array = _reservations.get(emitter, [])
	if entries.is_empty() or not is_same(entries[0], reservation):
		return {}
	var value: Variant = source.get(&"pose", fallback)
	if source.is_empty() or not value is Transform3D or not value.is_finite() or value.basis.determinant() == 0.0:
		_attached_sources.erase(emitter)
		if first_sample:
			_reservations.erase(emitter)
		else:
			_release_reservation(reservation)
		return {}
	var pose: Transform3D = value
	if emitter.global_transform != pose:
		var basis_changed := emitter.global_basis != pose.basis
		emitter.global_transform = pose
		if basis_changed:
			EmitterLayer.set_smoke_draw_basis(emitter)
			if reservation.get(&"gravity_tracks_world", false):
				EmitterLayer.set_smoke_gravity_basis(emitter)
	if first_sample:
		# A culled emitter can retain GPU state after its reservation expires.
		# Reset it before it can render at a different source's transform.
		if emitter.has_meta(&"used_attached_source"):
			RenderingServer.particles_restart(emitter.get_base())
		else:
			emitter.set_meta(&"used_attached_source", true)
		reservation[&"attachment_started"] = true
		reservation.expiry = _elapsed + reservation.attachment_span + reservation.tail
		_next_reservation_expiry = minf(_next_reservation_expiry, reservation.expiry)
		_attached_sources[emitter] = _sample_attached_source.bind(emitter, provider, fallback, reservation)
	return source

func _submit_layer(emitter: GPUParticles3D, layer: Dictionary, pose: Transform3D, duration: float,
		source_id: int, callback: Callable, pose_provider: Callable, id_provider: Callable, ordered := false,
		receiver_budget: CollisionParticles.FrameBudget = null, sprite_scale := 0.0) -> int:
	if emitter.fixed_fps == 0 and EmitterLayer.supports_host_clock(
			layer, emitter.process_material, emitter.local_coords, emitter.speed_scale, emitter.preprocess):
		layer = layer.duplicate()
		layer[&"source_rays_host_tick"] = _collision_particles.track_host_emitter(
			emitter, maxf(layer.particle_lifetime.x, layer.particle_lifetime.y))
	if layer.source_motion and (layer.stream_rate > 0.0 or layer.spawn_delay > 0.0 \
			or (duration != 0.0 and layer.loop_duration > 0.0) or pose_provider.is_valid()):
		return _schedule.begin(emitter, layer, pose, duration, callback, pose_provider, source_id, id_provider, ordered, receiver_budget, sprite_scale)
	var authored_material: Material = layer.renderer.get(&"material_override", emitter.material_override)
	var depth := EmitterLayer.depth_backend(self, emitter, layer, authored_material)
	if depth != null:
		var emitted: int = depth.emit_layer(emitter, layer, pose, sprite_scale, get_instance_id(), authored_material)
		if emitted > 0:
			return emitted
	var samples: Array[Dictionary] = []
	var submitted := EmitterLayer.emit_layer(emitter, layer, pose, samples, callback.is_valid(), Vector3.ZERO, id_provider, sprite_scale)
	if not samples.is_empty():
		callback.call(samples)
	return submitted

func _mark_emitter_cold(emitter: GPUParticles3D) -> void:
	if _cold_emitters.is_empty() and not RenderingServer.frame_post_draw.is_connected(_release_cold_emitters):
		RenderingServer.frame_post_draw.connect(_release_cold_emitters, CONNECT_ONE_SHOT)
	_cold_emitters[emitter] = true

func _launch_when_ready(emitter: GPUParticles3D, source_id: int, launch: Callable) -> int:
	if _cold_emitters.has(emitter):
		_pending_launches.append({&"source": source_id, &"launch": launch})
		return 0
	return launch.call()

func _release_cold_emitters() -> void:
	_cold_emitters.clear()
	var launches := _pending_launches
	_pending_launches = []
	for pending: Dictionary in launches:
		var launch: Callable = pending.launch
		_particle_count += int(launch.call())
	if not _schedule.is_empty() or not _reservations.is_empty() or _collision_particles.has_host_emitters():
		set_process(true)
	set_physics_process(_schedule.has_physics_sources() or _collision_particles.has_host_emitters())

## Build the common renderer variants before the first gameplay emission.
func prepare_library(selection: Resource = null, action_scenes: Array = []) -> void:
	if selection is PackedScene:
		_prepare_scene(selection)
	var library := (selection if selection != null else effect_library) as EffectLibrary
	if library != null and (not _warmed_libraries.has(library) or _warmed_libraries[library] != library.scenes):
		_warmed_libraries[library] = library.scenes.duplicate()
		for family: StringName in [&"hit", &"burst", &"amputated", &"amputated_head", &"slash"]:
			for intensity in range(4):
				_prepare_scene(_resolve_effect(family, intensity, selection))
	for scene in action_scenes:
		if scene is PackedScene:
			_prepare_scene(scene)

func _prepare_scene(scene: PackedScene) -> void:
	if scene == null or _warmed_scenes.has(scene):
		return
	_warmed_scenes[scene] = true
	var data := _get_scene_data(scene)
	for layer: Dictionary in data.get(&"layers", []):
		if layer.enabled and layer.visible and layer.channel < _emitters.size():
			var emitter := _get_emitter(layer, 0.0, 0, false)
			var material: Material = layer.renderer.get(&"material_override", emitter.material_override)
			var depth := EmitterLayer.depth_backend(self, emitter, layer, material)
			if depth != null:
				depth.prepare_layer(emitter, layer, material)

## Reserves renderer capacity for concurrent requests, without emitting or retaining the reservations.
## Returns true when a render frame is needed before publishing the batch.
func prepare_effect_batch(requests: Array[Dictionary], duration: float) -> bool:
	const WARMUP_SOURCE := -1
	for request in requests:
		var scene := _resolve_effect(request.effect, request.intensity, request.selection)
		var data := _get_scene_data(scene)
		for layer: Dictionary in data.get(&"layers", []):
			if layer.enabled and layer.visible and layer.channel < _emitters.size() \
					and layer.contact_source.is_empty() and EmitterLayer.has_spawns(layer, duration, true):
				_get_emitter(layer, duration, WARMUP_SOURCE, true, true)
	for emitter: GPUParticles3D in _reservations.keys():
		var reservations: Array = _reservations[emitter]
		while not reservations.is_empty() and reservations.back().source == WARMUP_SOURCE:
			reservations.pop_back()
		if reservations.is_empty():
			_reservations.erase(emitter)
	return not _cold_emitters.is_empty()

func _process(delta: float) -> void:
	_elapsed += delta
	for emitter: GPUParticles3D in _attached_sources.keys():
		if _attached_sources.has(emitter) and _reservations[emitter][0].expiry > _elapsed:
			_attached_sources[emitter].call()
	_particle_count += _schedule.advance(delta)
	if _elapsed >= _next_reservation_expiry:
		_prune_reservations()
	_collision_particles.advance(delta)
	if _schedule.is_empty() and _reservations.is_empty() and not _collision_particles.has_host_emitters():
		set_process(false)

func _physics_process(delta: float) -> void:
	_particle_count += _schedule.advance_physics(delta)
	_collision_particles.advance_host_physics(delta)
	if not _schedule.has_physics_sources() and not _collision_particles.has_host_emitters():
		set_physics_process(false)

func stop_source(source_id: int) -> void:
	if source_id == 0:
		return
	_schedule.clear(source_id)
	set_physics_process(_schedule.has_physics_sources() or _collision_particles.has_host_emitters())
	for index in range(_pending_launches.size() - 1, -1, -1):
		if _pending_launches[index].source == source_id:
			_pending_launches.remove_at(index)
	for emitter: GPUParticles3D in _reservations.keys():
		var reservations: Array = _reservations[emitter]
		for reservation: Dictionary in reservations:
			if reservation.source == source_id:
				if reservation.has(&"attachment_span"):
					_attached_sources.erase(emitter)
					if not reservation.has(&"attachment_started"):
						_reservations.erase(emitter)
						break
				_release_reservation(reservation)

func _release_reservation(reservation: Dictionary) -> void:
	reservation.expiry = minf(reservation.expiry, _elapsed + reservation.tail)
	_next_reservation_expiry = minf(_next_reservation_expiry, reservation.expiry)

func _prune_reservations() -> void:
	_next_reservation_expiry = INF
	for emitter: GPUParticles3D in _reservations.keys():
		var reservations: Array = _reservations[emitter]
		for index in range(reservations.size() - 1, -1, -1):
			var reservation: Dictionary = reservations[index]
			if reservation.expiry <= _elapsed:
				reservations.remove_at(index)
			else:
				_next_reservation_expiry = minf(_next_reservation_expiry, reservation.expiry)
		if reservations.is_empty():
			_reservations.erase(emitter)
			_attached_sources.erase(emitter)

func _collect_samples(samples: Array[Dictionary], data: Dictionary, scene: PackedScene, scale: float,
		receiver_state: CollisionParticles.FrameBudget, callback: Callable) -> void:
	for sample in samples:
		sample[&"family"] = data.family
		sample[&"scene"] = scene
		sample[&"scale"] = scale
		sample[&"receiver_state"] = receiver_state
		sample[&"receivers"] = data.get(&"receivers", {}).get(sample.layer, [])
	if callback.is_valid():
		callback.call(samples)
	else:
		_collision_samples.append_array(samples)

func take_collision_samples() -> Array[Dictionary]:
	var result := _collision_samples.duplicate()
	_collision_samples.clear()
	return result

func emit_contact_layer(layer_id: StringName, position: Vector3, normal: Vector3,
		size_scale: float, scene: PackedScene) -> bool:
	var data := _get_scene_data(scene)
	for layer: Dictionary in data.get(&"layers", []):
		if layer.emitter_name != layer_id or not layer.enabled or not layer.visible \
				or layer.channel >= _emitters.size():
			continue
		var pose := EmitterLayer.launch_pose(data.family, normal, size_scale, position, layer.source_motion)
		var emitter := _get_emitter(layer, 0.0, 0)
		set_process(true)
		var launch := _submit_layer.bind(emitter, layer, pose, 0.0, 0, Callable(), Callable(), Callable())
		_particle_count += _launch_when_ready(emitter, 0, launch)
		return true
	return false

## Configures a temporary scene before adding it to a tree.
func configure_one_shot(effect: StringName, direction: Vector3, scale: float,
		intensity: int = 1, selection: Resource = null) -> bool:
	if is_node_ready() or not EmitterLayer.supports_gpu() \
			or _get_scene_data(_resolve_effect(effect, intensity, selection)).is_empty() \
			or not direction.is_finite() or not is_finite(scale) or scale <= 0.0:
		return false
	_one_shot_effect = effect
	_one_shot_direction = direction
	_one_shot_scale = scale
	_one_shot_intensity = intensity
	_one_shot_selection = selection
	return true

func clear() -> void:
	EmitterLayer.clear_depth_owner(self)
	_schedule.clear()
	_collision_particles.clear_host_emitters()
	_pending_launches.clear()
	_collision_samples.clear()
	_reservations.clear()
	_attached_sources.clear()
	_next_reservation_expiry = INF
	set_process(false)
	set_physics_process(false)
	for emitter in _emitters + _variant_emitters:
		emitter.restart()
		emitter.emitting = false
	_effect_count = 0
	_particle_count = 0

func _exit_tree() -> void:
	EmitterLayer.clear_depth_owner(self)
	_schedule.clear()
	_attached_sources.clear()

## Accepted requests since creation or clear.
func get_effect_count() -> int:
	return _effect_count

## Submitted particles since creation or clear. GPU buffers cap live occupancy.
func get_particle_count() -> int:
	return _particle_count

func _emit_one_shot() -> void:
	if not emit_effect(_one_shot_effect, global_position, _one_shot_direction,
			_one_shot_scale, _one_shot_intensity, _one_shot_selection):
		queue_free()
		return
	var cleanup_delay := LIFETIME
	var data := _get_scene_data(_resolve_effect(_one_shot_effect, _one_shot_intensity, _one_shot_selection))
	for layer: Dictionary in data.get(&"layers", []):
		cleanup_delay = maxf(cleanup_delay, EmitterLayer.duration_for_layer(layer))
	get_tree().create_timer(cleanup_delay, false).timeout.connect(queue_free)

func _resolve_effect(effect: StringName, intensity: int, selection: Resource) -> PackedScene:
	if selection is PackedScene:
		return selection
	var library := effect_library
	if selection is EffectLibrary:
		library = selection
	elif selection != null:
		return null
	if library == null:
		return null

	var exact := library.find_system(String(effect))
	if exact != null:
		return exact

	var words := String(effect).strip_edges().to_lower().replace("-", "_").replace(" ", "_").trim_prefix("ns_")
	exact = library.find_system("ns_" + words)
	if exact != null:
		return exact

	var suffix := words.get_slice("_", words.get_slice_count("_") - 1)
	var tier := clampi(intensity, 0, 3)
	if TIERS.has(suffix):
		tier = TIERS[suffix]
		words = words.trim_suffix("_" + suffix)
	var key := words.replace("_", "")
	if key == "splatter":
		var omni := library.find_system("ns_splatter_omni_01_decal")
		if omni != null:
			return omni
	var family: StringName = EFFECT_KEYS.get(key, &"")
	if key.begins_with("splatterdirectional") or key.begins_with("splatteromni"):
		family = &"splatter"
	return library.find_family(family, tier) if not family.is_empty() else null

func _get_scene_data(scene: PackedScene) -> Dictionary:
	if scene == null:
		return {}
	if not _scene_data.has(scene):
		var metadata := EffectLibrary.read_scene_metadata(scene)
		if not metadata.is_empty():
			if scene.get_state().get_base_scene_state() != null:
				_read_inherited_scene_data(scene, metadata)
			else:
				metadata.layers = EmitterLayer.read_scene_layers(scene)
				metadata.receivers = ContactReceiver.read_scene_receivers(scene)
		_scene_data[scene] = metadata
	return _scene_data[scene]

func _read_inherited_scene_data(scene: PackedScene, metadata: Dictionary) -> void:
	# An off-tree instance resolves inherited overrides without starting the effect.
	var instance := scene.instantiate()
	var layers: Array[Dictionary] = []
	for child in instance.get_children():
		var emitter := child as EmitterLayer
		if emitter != null:
			var layer := emitter.get_blood_settings()
			layer.renderer = EmitterLayer.read_renderer_settings(emitter)
			layers.append(layer)
	metadata.layers = layers
	metadata.receivers = ContactReceiver.read_node_receivers(instance)
	instance.free()

func _get_emitter(layer: Dictionary, duration: float, source_id: int, reserve := true,
		moving_source := false, reservation: Variant = null, ordered := false) -> GPUParticles3D:
	var channel: int = layer.channel
	var renderer: Dictionary = layer.renderer
	var standard := _emitters[channel]
	var settings := {}
	for property in EmitterLayer.RENDER_PROPERTIES:
		var value = renderer.get(property, _node_defaults.get(property))
		var default = _renderer_defaults[channel].get(property)
		if value != default and not _equivalent_quad(value, default):
			settings[property] = value
	var draw: Material = settings.get(&"material_override", standard.material_override)
	var process: Material = settings.get(&"process_material", standard.process_material)
	if EmitterLayer.supports_host_clock(layer, process, bool(renderer.get(&"local_coords", standard.local_coords)),
			float(renderer.get(&"speed_scale", standard.speed_scale)), float(renderer.get(&"preprocess", standard.preprocess))):
		settings[&"host_clock"] = true
		settings[&"fixed_fps"] = 0
		settings[&"interpolate"] = false
		settings[&"fract_delta"] = false
	var local_follow := moving_source and EmitterLayer.supports_source_attachment(layer, draw, process) \
		and float(renderer.get(&"speed_scale", standard.speed_scale)) > 0.0
	if local_follow:
		settings[&"local_coords"] = true
		settings[&"follow_source_transform"] = true
		if layer.gravity_tracks_world:
			settings[&"gravity_tracks_world"] = true
	var curve_settings := EmitterLayer.visual_curve_settings(layer)
	if not curve_settings.is_empty() and draw is ShaderMaterial and draw.get_shader_parameter(&"source_graph") == true:
		settings[&"sprite_curves"] = curve_settings
	if EmitterLayer.needs_anisotropic_normal_binding(draw):
		settings[&"anisotropic_normal_binding"] = draw.get_shader_parameter(&"source_normal_map")
	if layer.collision_kill:
		settings[&"collision_retirement"] = true
	if layer.continuous_inherit_velocity != 0.0:
		settings[&"inherited_motion"] = true
		if ordered:
			settings[&"ordered_motion"] = true
	var maximum_lifetime := maxf(layer.particle_lifetime.x, layer.particle_lifetime.y)
	var capacity := EmitterLayer.particle_count_for_layer(layer)
	if layer.source_motion:
		if maximum_lifetime > float(renderer.get(&"lifetime", standard.lifetime)):
			settings[&"lifetime"] = maximum_lifetime + 0.1
		if layer.loop_duration > 0.0 and duration != 0.0:
			var occupancy_span := maximum_lifetime
			if duration > 0.0:
				occupancy_span = minf(occupancy_span, duration)
			capacity = (1 + int(ceil(occupancy_span / layer.loop_duration))) * int(layer.particle_count)
			capacity += int(ceil(occupancy_span * layer.stream_rate)) + int(layer.stream_rate > 0.0)
		if layer.stream_spacing > 0.0 and moving_source:
			if layer.stream_max_speed > 0.0:
				var movement_span := minf(maximum_lifetime, duration) if duration > 0.0 else maximum_lifetime
				capacity += ceili((movement_span + EffectSchedule.SOURCE_FRAME) * layer.stream_max_speed / layer.stream_spacing)
			else:
				capacity += ceili(layer.stream_max_movement / layer.stream_spacing)
	var configured_amount: int = renderer.get(&"amount", standard.amount)
	if capacity > configured_amount:
		settings[&"amount"] = capacity
	if settings.is_empty() and (not reserve or _reserve_emitter(standard, capacity, layer, duration, source_id, reservation)):
		return standard

	# Godot accepts a manual emit request only while a buffer slot is free.
	# Allocate another emitter with the same settings if a previous burst or
	# continuous spray has reserved the available slots.
	settings[&"channel"] = channel
	for index in _variant_settings.size():
		if _variant_settings[index] == settings:
			var candidate := _variant_emitters[index]
			if not reserve or _reserve_emitter(candidate, capacity, layer, duration, source_id, reservation, local_follow):
				return candidate
	var variant := standard.duplicate() as GPUParticles3D
	for property in EmitterLayer.RENDER_PROPERTIES:
		if settings.has(property) and EmitterLayer.renderer_property_available(variant, property):
			variant.set(property, settings[property])
	if settings.has(&"sprite_curves") or settings.has(&"anisotropic_normal_binding"):
		variant.material_override = EmitterLayer.bind_visual_curves(draw, layer)
	if layer.collision_kill:
		variant.process_material = _collision_particles.bind_material(variant.process_material)
	if settings.has(&"inherited_motion"):
		variant.process_material = _schedule.bind_inherited_motion(variant.process_material, settings.has(&"ordered_motion"))
	if settings.has(&"gravity_tracks_world"):
		variant.process_material = variant.process_material.duplicate()
	variant.name = standard.name + "Variant" + str(_variant_emitters.size() + 1)
	add_child(variant)
	if local_follow:
		variant.top_level = true
	_mark_emitter_cold(variant)
	_variant_settings.append(settings)
	_variant_emitters.append(variant)
	if reserve:
		_reserve_emitter(variant, capacity, layer, duration, source_id, reservation, local_follow)
	return variant

func _reserve_emitter(emitter: GPUParticles3D, count: int, layer: Dictionary,
		duration: float, source_id: int, reservation: Variant, local_follow := false) -> bool:
	var reservations: Array = _reservations.get(emitter, [])
	if local_follow and not reservations.is_empty():
		return false
	var occupied := 0
	for occupied_entry: Dictionary in reservations:
		occupied += int(occupied_entry.count)
	if occupied + count > emitter.amount:
		return false

	var tail := maxf(layer.particle_lifetime.x, layer.particle_lifetime.y) + 0.05
	var span := maxf(layer.spawn_delay, layer.stream_delay + layer.emission_window)
	if layer.loop_duration > 0.0 and duration != 0.0:
		span = duration if duration > 0.0 else INF
	var expiry := _elapsed + span + tail
	var entry: Dictionary = reservation if reservation != null else {}
	if local_follow:
		tail = maxf(layer.particle_lifetime.x, layer.particle_lifetime.y) / emitter.speed_scale + 0.1
		# A cold emitter can wait through a render stall before its first submission.
		entry[&"attachment_span"] = span + EffectSchedule.SOURCE_FRAME
		entry[&"gravity_tracks_world"] = layer.gravity_tracks_world
		expiry = INF if reservation != null else _elapsed + entry.attachment_span + tail
	entry.source = source_id
	entry.count = count
	entry.expiry = expiry
	entry.tail = tail
	reservations.append(entry)
	_reservations[emitter] = reservations
	_next_reservation_expiry = minf(_next_reservation_expiry, expiry)
	return true

func retire_collided_particle(id: int) -> void:
	_collision_particles.retire(id)
	set_process(true)

static func _equivalent_quad(a: Variant, b: Variant) -> bool:
	return a is QuadMesh and b is QuadMesh and a.size == b.size and a.orientation == b.orientation \
		and a.subdivide_width == b.subdivide_width and a.subdivide_depth == b.subdivide_depth \
		and a.center_offset == b.center_offset and a.flip_faces == b.flip_faces and a.material == b.material




