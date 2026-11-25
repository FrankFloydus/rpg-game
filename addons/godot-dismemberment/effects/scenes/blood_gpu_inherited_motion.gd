@tool
extends RefCounted

const WIDTH := 64
const SLOT_COUNT := WIDTH * WIDTH
const HISTORY_SIZE := 16
const PHASE_COUNT := 4096
const GENERATION_COUNT := WIDTH

class Source:
	var slot: int
	var impulse := Vector3.ZERO
	var generation := -1
	var latest_tick := -1
	var stopped := false
	var history := PackedVector3Array()

	func is_ordered() -> bool:
		return generation >= 0

	func particle_token(source_tick: int) -> int:
		if not is_ordered():
			return slot
		# The 24-bit integer is exact in the emission packet's float custom field.
		return -(slot + generation * WIDTH + posmod(source_tick, PHASE_COUNT) * SLOT_COUNT)

	func impulse_at_tick(source_tick: int) -> Variant:
		if source_tick > latest_tick:
			return Vector3.ZERO if stopped else null
		if source_tick < 0 or latest_tick - source_tick >= HISTORY_SIZE:
			return Vector3.ZERO
		return history[source_tick % HISTORY_SIZE]

	func current_impulse() -> Vector3:
		return impulse

var _image: Image
var _texture: ImageTexture
var _expiry := PackedFloat64Array()
var _next_slot := 1
var _elapsed := 0.0
var _dirty := false
var _history_image: Image
var _history_texture: ImageTexture
var _history_expiry := PackedFloat64Array()
var _generations := PackedInt32Array()
var _next_history_slot := 1
var _history_dirty := false

func bind_material(material: Material, ordered := false) -> Material:
	if not material is ShaderMaterial or material.shader == null:
		return material
	var has_latest := false
	var has_history := false
	for parameter in material.shader.get_shader_uniform_list():
		has_latest = has_latest or parameter.name == &"inherited_motion"
		has_history = has_history or parameter.name == &"inherited_motion_history"
	if not has_latest:
		return material
	if _texture == null:
		_image = Image.create_empty(WIDTH, WIDTH, false, Image.FORMAT_RGBAF)
		_texture = ImageTexture.create_from_image(_image)
		_expiry.resize(SLOT_COUNT)
	var bound := material.duplicate() as ShaderMaterial
	bound.set_shader_parameter(&"inherited_motion", _texture)
	if ordered and has_history:
		if _history_texture == null:
			_history_image = Image.create_empty(WIDTH, HISTORY_SIZE + 1, false, Image.FORMAT_RGBAF)
			_history_texture = ImageTexture.create_from_image(_history_image)
			_history_expiry.resize(WIDTH)
			_generations.resize(WIDTH)
		bound.set_shader_parameter(&"inherited_motion_history", _history_texture)
	return bound

func begin(emitter: GPUParticles3D, ordered := false) -> Source:
	if _texture == null or not emitter.process_material is ShaderMaterial \
			or emitter.process_material.get_shader_parameter(&"inherited_motion") != _texture:
		return null
	if ordered and _history_texture != null and \
			emitter.process_material.get_shader_parameter(&"inherited_motion_history") == _history_texture:
		var source := _begin_ordered()
		if source != null:
			return source
	for index in SLOT_COUNT - 1:
		var slot := _next_slot
		_next_slot = slot % (SLOT_COUNT - 1) + 1
		if _expiry[slot] <= _elapsed:
			_expiry[slot] = INF
			var source := Source.new()
			source.slot = slot
			return source
	return null

func _begin_ordered() -> Source:
	for index in WIDTH - 1:
		var slot := _next_history_slot
		_next_history_slot = slot % (WIDTH - 1) + 1
		if _history_expiry[slot] <= _elapsed:
			_history_expiry[slot] = INF
			_generations[slot] = (_generations[slot] + 1) % GENERATION_COUNT
			var source := Source.new()
			source.slot = slot
			source.generation = _generations[slot]
			source.history.resize(HISTORY_SIZE)
			_write_history_header(source)
			return source
	return null

func _write_history_header(source: Source) -> void:
	var head := posmod(source.latest_tick, PHASE_COUNT)
	var stop := posmod(source.latest_tick + 1, PHASE_COUNT)
	_history_image.set_pixel(source.slot, HISTORY_SIZE, Color(head, stop, float(source.stopped), source.generation))
	_history_dirty = true

func update(source: Source, impulse: Vector3, local_impulse: Vector3, source_tick := -1) -> void:
	if source == null:
		return
	if source.is_ordered():
		if source.stopped or source_tick != source.latest_tick + 1:
			return
		source.latest_tick = source_tick
		source.history[source_tick % HISTORY_SIZE] = impulse
		var phase := posmod(source_tick, PHASE_COUNT)
		_history_image.set_pixel(source.slot, phase % HISTORY_SIZE, Color(local_impulse.x, local_impulse.y, local_impulse.z, phase))
		_write_history_header(source)
		return
	source.impulse = impulse
	@warning_ignore("integer_division")
	var point := Vector2i(source.slot % WIDTH, source.slot / WIDTH)
	var pixel := Color(local_impulse.x, local_impulse.y, local_impulse.z, 0.0)
	if not _image.get_pixelv(point).is_equal_approx(pixel):
		_image.set_pixelv(point, pixel)
		_dirty = true

func end(source: Source, tail: float) -> void:
	if source == null:
		return
	if source.is_ordered():
		if not source.stopped:
			source.stopped = true
			_write_history_header(source)
			_history_expiry[source.slot] = _elapsed + tail + HISTORY_SIZE / 60.0
	else:
		update(source, Vector3.ZERO, Vector3.ZERO)
		_expiry[source.slot] = _elapsed + tail

func advance(delta: float) -> void:
	_elapsed += delta
	flush()

func flush() -> void:
	if _dirty:
		_texture.update(_image)
		_dirty = false
	if _history_dirty:
		_history_texture.update(_history_image)
		_history_dirty = false
