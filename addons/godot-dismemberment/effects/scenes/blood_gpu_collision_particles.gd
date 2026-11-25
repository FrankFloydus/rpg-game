@tool
extends RefCounted
## Retires specific GPU particles when their corresponding physics probe hits.

const TEXTURE_WIDTH := 256
const SLOT_COUNT := TEXTURE_WIDTH * TEXTURE_WIDTH
const MAX_PARTICLE_ID := 16777215

static func tick_limited_sources(receivers: Dictionary) -> Array[StringName]:
	var sources: Array[StringName] = []
	for source: StringName in receivers:
		for receiver: Dictionary in receivers[source]:
			if int(receiver.get(&"max_per_tick", 0)) > 0 and not StringName(receiver.get(&"target_layer", &"")).is_empty():
				sources.append(source)
				break
	return sources

class FrameBudget extends RefCounted:
	var _counts: Dictionary[StringName, Dictionary] = {}
	var _pending: Dictionary[int, Array] = {}
	var _closed_tick := -1

	func track_probe(id: int, first_tick: int, last_tick: int) -> void:
		if _pending.has(id):
			_pending[id][0] = first_tick
		else:
			_pending[id] = [first_tick, last_tick]

	func retire_probe(id: int) -> void:
		_pending.erase(id)

	func close_through(tick: int) -> void:
		_closed_tick = maxi(_closed_tick, tick)
		if _counts.is_empty():
			return
		var intervals := _pending.values()
		intervals.sort_custom(func(left: Array, right: Array) -> bool: return left[0] < right[0])
		for counts: Dictionary in _counts.values():
			var keys := counts.keys()
			keys.sort()
			var index := 0
			var covered_until := -1
			for event_tick: int in keys:
				if event_tick > _closed_tick:
					break
				while index < intervals.size() and intervals[index][0] <= event_tick:
					covered_until = maxi(covered_until, intervals[index][1])
					index += 1
				if event_tick > covered_until:
					counts.erase(event_tick)

	func allow(target_layer: StringName, source_tick: int, limit: int) -> bool:
		if not _counts.has(target_layer):
			_counts[target_layer] = {}
		var counts: Dictionary = _counts[target_layer]
		var count: int = counts.get(source_tick, 0)
		if count >= limit:
			return false
		counts[source_tick] = count + 1
		return true

var _image: Image
var _texture: ImageTexture
var _dirty := false
var _next_id := 1
var _slot_expiry := PackedFloat64Array()
var _elapsed := 0.0
var _host_emitters: Dictionary[GPUParticles3D, float] = {}
var _host_epoch := -1
var _host_deltas := PackedFloat32Array()
var _host_dirty := false

func track_host_emitter(emitter: GPUParticles3D, lifetime: float) -> int:
	if _host_deltas.is_empty():
		_host_deltas.resize(16)
	if not _host_emitters.has(emitter):
		var material := emitter.process_material as ShaderMaterial
		material.set_shader_parameter(&"source_host_epoch", -1)
	_host_emitters[emitter] = maxf(_host_emitters.get(emitter, 0.0), lifetime + 0.1)
	return Engine.get_physics_frames() + 1

func has_host_emitters() -> bool:
	return not _host_emitters.is_empty()

func clear_host_emitters() -> void:
	_host_emitters.clear()
	_host_deltas.clear()
	_host_epoch = -1
	_host_dirty = false

func advance_host_physics(delta: float) -> void:
	if _host_emitters.is_empty() or not is_finite(delta) or delta <= 0.0:
		return
	_host_epoch = Engine.get_physics_frames() & 65535
	_host_deltas[_host_epoch & 15] = delta
	for emitter: GPUParticles3D in _host_emitters:
		_host_emitters[emitter] -= delta
	_host_dirty = true

func bind_material(material: Material) -> Material:
	if not material is ShaderMaterial:
		return material
	_prepare_texture()
	var process_material := material.duplicate() as ShaderMaterial
	process_material.set_shader_parameter(&"contact_particle_mask", _texture)
	return process_material

func allocate(duration: float) -> int:
	_prepare_texture()
	for index in SLOT_COUNT:
		var id := _next_id
		_next_id = id + 1 if id < MAX_PARTICLE_ID else 1
		var slot := id % SLOT_COUNT
		if _slot_expiry[slot] <= _elapsed:
			_slot_expiry[slot] = _elapsed + duration + 0.1
			return id
	push_error("Blood particle collision IDs exhausted")
	return 0

func retire(id: int) -> void:
	if id <= 0 or _texture == null:
		return
	var slot := id % SLOT_COUNT
	@warning_ignore("integer_division")
	_image.set_pixel(slot % TEXTURE_WIDTH, slot / TEXTURE_WIDTH, Color(float(id), 0.0, 0.0))
	_dirty = true

func advance(delta: float) -> void:
	_elapsed += delta
	if _dirty:
		_texture.update(_image)
		_dirty = false
	if not _host_dirty:
		return
	# Publish only after the collision retirements for these physics ticks.
	for emitter: GPUParticles3D in _host_emitters.keys():
		if is_instance_valid(emitter):
			var material := emitter.process_material as ShaderMaterial
			if material != null:
				material.set_shader_parameter(&"source_host_deltas", _host_deltas)
				material.set_shader_parameter(&"source_host_epoch", _host_epoch)
			if emitter.is_visible_in_tree():
				RenderingServer.particles_request_process(emitter.get_base())
		if not is_instance_valid(emitter) or _host_emitters[emitter] < -0.001:
			_host_emitters.erase(emitter)
	_host_dirty = false

func _prepare_texture() -> void:
	if _texture != null:
		return
	_image = Image.create_empty(TEXTURE_WIDTH, TEXTURE_WIDTH, false, Image.FORMAT_RF)
	_texture = ImageTexture.create_from_image(_image)
	_slot_expiry.resize(SLOT_COUNT)
