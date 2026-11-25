@tool
class_name BloodProjectedDecalReceiver
extends Node3D
## Optional projected decals on a rigid receiver using prebaked texture arrays.

const RECEIVER_METADATA := &"godot_dismemberment_projection_receiver"
const RECEIVER_SHADER_PATH := "res://addons/godot-dismemberment/effects/projection/blood_projected_receiver.gdshader"
const MAX_PROJECTORS := 16

## Body whose physics contacts should use this receiver.
@export var collision_body: PhysicsBody3D:
	set(value):
		collision_body = value
		update_configuration_warnings()
## Single-surface mesh that moves with the body.
@export var receiver_mesh: MeshInstance3D:
	set(value):
		receiver_mesh = value
		update_configuration_warnings()
## Shared array textures and editable decal materials.
@export var atlas: BloodProjectedDecalAtlas:
	set(value):
		atlas = value
		update_configuration_warnings()

@export_group("Surface Finish")
## Shade compatible blood deposits on this mesh with the cutoff and tiled grunge below.
@export var surface_finish_enabled := false:
	set(value):
		surface_finish_enabled = value
		update_configuration_warnings()
		if _material != null:
			_bind_surface_finish()
			set_surface_finish_preview(value)
## Opacity threshold for the dense part of the splatter. A softer contribution keeps fine spray visible.
@export_range(0.0, 1.0, 0.01) var alpha_cutoff := 0.27:
	set(value):
		alpha_cutoff = clampf(value, 0.0, 1.0)
		_bind_surface_finish()
## Repeating grayscale color detail, sampled independently of the decal silhouette.
@export var grunge: Texture2D:
	set(value):
		grunge = value
		_bind_surface_finish()
## Grunge repetitions per metre along the receiving surface.
@export_range(0.0, 16.0, 0.1, "or_greater", "suffix:/m") var grunge_repeats_per_meter := 4.0:
	set(value):
		grunge_repeats_per_meter = maxf(value, 0.0)
		_bind_surface_finish()
## Strength of the separate grunge detail. Zero uses only the atlas color.
@export_range(0.0, 1.0, 0.01) var grunge_strength := 0.45:
	set(value):
		grunge_strength = clampf(value, 0.0, 1.0)
		_bind_surface_finish()

class DecalProjection:
	var inverse: Transform3D
	var world_space: bool
	var slot: int
	var turns: float
	var lifetime: float
	var tangent: float
	var age: float = 0.0
	var native_decal: Decal
	var tracked_native := false
	var footprint: Vector4

var _material: ShaderMaterial
var _previous_override: Material
var _uses_material_override := false
var _bound_atlas: BloodProjectedDecalAtlas
var _bound_body: PhysicsBody3D
var _bound_mesh: MeshInstance3D
var _projections: Array[DecalProjection] = []
var _matrices: Array[Transform3D] = []
var _uniforms_dirty := false
var _last_receiver_transform := Transform3D.IDENTITY
var _finish_preview := true

func _ready() -> void:
	set_process(false)
	if Engine.is_editor_hint() or not _get_configuration_warnings().is_empty():
		return
	if RenderingServer.get_current_rendering_method() != &"forward_plus":
		return
	if collision_body.has_meta(RECEIVER_METADATA):
		return
	var source := receiver_mesh.get_active_material(0)
	_material = source.duplicate() if source is ShaderMaterial else _convert_standard(source, atlas.cooked_receiver_shader if atlas.cooked_normals != null else null)
	if _material == null:
		return
	_uses_material_override = receiver_mesh.material_override != null
	_previous_override = receiver_mesh.material_override if _uses_material_override else receiver_mesh.get_surface_override_material(0)
	_bound_atlas = atlas
	_bound_body = collision_body
	_bound_mesh = receiver_mesh
	_bind_atlas()
	if _uses_material_override:
		receiver_mesh.material_override = _material
	else:
		receiver_mesh.set_surface_override_material(0, _material)
	collision_body.set_meta(RECEIVER_METADATA, get_instance_id())

func _exit_tree() -> void:
	if Engine.is_editor_hint() or _material == null:
		return
	if is_instance_valid(_bound_body) and _bound_body.get_meta(RECEIVER_METADATA, 0) == get_instance_id():
		_bound_body.remove_meta(RECEIVER_METADATA)
	if _has_bound_material():
		if _uses_material_override:
			_bound_mesh.material_override = _previous_override
		else:
			_bound_mesh.set_surface_override_material(0, _previous_override)
	clear_projections()
	_material = null
	_bound_atlas = null
	_bound_body = null
	_bound_mesh = null

func _get_configuration_warnings() -> PackedStringArray:
	if collision_body == null or receiver_mesh == null or receiver_mesh.mesh == null:
		return PackedStringArray(["Assign the collision body and its receiving mesh."])
	var rigid_mesh := collision_body.is_ancestor_of(receiver_mesh)
	if surface_finish_enabled and collision_body is StaticBody3D:
		rigid_mesh = (rigid_mesh or collision_body.get_parent() == receiver_mesh.get_parent()
			or receiver_mesh.is_ancestor_of(collision_body))
	if not rigid_mesh or receiver_mesh.top_level or receiver_mesh.skin != null:
		return PackedStringArray(["The receiving mesh must move with the body and use rigid geometry."])
	if receiver_mesh.mesh.get_surface_count() != 1 or (receiver_mesh.material_override != null and not surface_finish_enabled):
		return PackedStringArray(["Assign a single-surface mesh with a surface material."])
	var material := receiver_mesh.get_active_material(0)
	if not ((material is BaseMaterial3D and _supports_standard(material)) or
			(material is ShaderMaterial and _supports_shader(material))):
		return PackedStringArray(["Assign a supported opaque material or a shader using the blood projection include."])
	if atlas == null or not atlas.is_valid():
		return PackedStringArray(["Assign a valid prebaked blood projection atlas."])
	if atlas.coverage_only and not surface_finish_enabled:
		return PackedStringArray(["Enable Surface Finish to use a coverage-only atlas."])
	return PackedStringArray()

static func _supports_shader(material: ShaderMaterial) -> bool:
	if material.shader == null:
		return false
	if material.shader.resource_path == RECEIVER_SHADER_PATH:
		return true
	return material.shader.code.contains("blood_projected_decals.gdshaderinc") \
		and material.shader.code.contains("blood_apply_projected_decals(")

static func _supports_standard(material: BaseMaterial3D) -> bool:
	if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.cull_mode != BaseMaterial3D.CULL_BACK:
		return false
	if material.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL or material.next_pass != null:
		return false
	if material.vertex_color_use_as_albedo or material.uv1_triplanar or material.uv2_triplanar:
		return false
	for feature in range(BaseMaterial3D.FEATURE_MAX):
		if material.get_feature(feature):
			return false
	for texture in range(BaseMaterial3D.TEXTURE_MAX):
		if texture != BaseMaterial3D.TEXTURE_ALBEDO and texture != BaseMaterial3D.TEXTURE_ORM and material.get_texture(texture) != null:
			return false
	return true

static func _convert_standard(source: BaseMaterial3D, cooked_shader: Shader) -> ShaderMaterial:
	if cooked_shader == null and not ResourceLoader.exists(RECEIVER_SHADER_PATH):
		return null
	var converted := ShaderMaterial.new()
	converted.shader = cooked_shader if cooked_shader != null else load(RECEIVER_SHADER_PATH)
	converted.set_shader_parameter("receiver_tint", source.albedo_color)
	converted.set_shader_parameter("receiver_color", source.albedo_texture)
	converted.set_shader_parameter("receiver_roughness", source.roughness)
	converted.set_shader_parameter("receiver_metallic", source.metallic)
	converted.set_shader_parameter("receiver_specular", source.metallic_specular)
	converted.set_shader_parameter("receiver_uv_scale", source.uv1_scale)
	converted.set_shader_parameter("receiver_uv_offset", source.uv1_offset)
	if source is ORMMaterial3D:
		converted.set_shader_parameter("use_receiver_orm", source.orm_texture != null)
		converted.set_shader_parameter("receiver_orm", source.orm_texture)
	return converted

func project_decal(world_from_unit_cube: Transform3D, material: BaseMaterial3D, turns: float,
		lifetime: float, dissolve_end_tangent: float) -> bool:
	return _add_projection(world_from_unit_cube, material, turns, lifetime, dissolve_end_tangent, false)

## Project a decal at a fixed world transform as this receiver moves through it.
func project_world_decal(world_from_unit_cube: Transform3D, material: BaseMaterial3D, turns: float,
		lifetime: float, dissolve_end_tangent: float) -> bool:
	return _add_projection(world_from_unit_cube, material, turns, lifetime, dissolve_end_tangent, true)

func _add_projection(world_from_unit_cube: Transform3D, material: BaseMaterial3D, turns: float,
		lifetime: float, dissolve_end_tangent: float, world_space: bool) -> bool:
	if _material == null or not is_instance_valid(_bound_mesh) or not is_finite(lifetime) or lifetime <= 0.0:
		return false
	if _bound_atlas.coverage_only:
		return false
	if _projections.size() >= MAX_PROJECTORS or not _has_bound_material():
		return false
	var slot := _bound_atlas.find_material(material)
	if slot < 0 or not world_from_unit_cube.is_finite() or world_from_unit_cube.basis.determinant() == 0.0:
		return false
	if not is_finite(turns) or not is_finite(dissolve_end_tangent) or dissolve_end_tangent < 0.0:
		return false
	var receiver_transform := _bound_mesh.global_transform
	if receiver_transform.basis.determinant() == 0.0:
		return false
	var projection := world_from_unit_cube if world_space else receiver_transform.affine_inverse() * world_from_unit_cube
	if not projection.is_finite() or projection.basis.determinant() == 0.0:
		return false
	var record := DecalProjection.new()
	record.inverse = projection.affine_inverse()
	record.world_space = world_space
	record.slot = slot
	record.turns = turns
	record.lifetime = lifetime
	record.tangent = dissolve_end_tangent
	_projections.append(record)
	_uniforms_dirty = true
	set_process(true)
	return true

func _has_bound_material() -> bool:
	if not is_instance_valid(_bound_mesh) or _material == null:
		return false
	if _uses_material_override:
		return _bound_mesh.material_override == _material
	return _bound_mesh.get_surface_override_material(0) == _material

## Use the native decal's transform, tint and fade to shade its contact on this mesh.
func track_surface_decal(decal: Decal, follow_receiver: bool) -> bool:
	if not surface_finish_enabled or not _has_bound_material() or _projections.size() >= MAX_PROJECTORS:
		return false
	var slot := _bound_atlas.find_textures(decal.texture_albedo, decal.texture_normal, decal.texture_orm)
	if slot < 0:
		return false
	var box := decal.global_transform
	box.basis = box.basis.scaled_local(decal.size)
	var receiver_transform := _bound_mesh.global_transform
	if (not box.is_finite() or is_zero_approx(box.basis.determinant())
			or is_zero_approx(receiver_transform.basis.determinant())):
		return false
	var projection := receiver_transform.affine_inverse() * box if follow_receiver else box
	var record := DecalProjection.new()
	record.inverse = projection.affine_inverse()
	record.world_space = not follow_receiver
	record.slot = slot
	record.native_decal = decal
	record.tracked_native = true
	record.footprint = Vector4(box.basis.x.length(), box.basis.z.length(), decal.upper_fade, decal.lower_fade)
	_projections.append(record)
	_uniforms_dirty = true
	decal.visible = not _finish_preview
	# Upload in the same frame that we hide the engine decal.
	_process(0.0)
	set_process(true)
	return true

## Switch between native decals and surface finish at the current camera pose.
func set_surface_finish_preview(enabled: bool) -> void:
	_finish_preview = enabled
	for record in _projections:
		if record.tracked_native and is_instance_valid(record.native_decal):
			record.native_decal.visible = not enabled
	if _has_bound_material():
		_process(0.0)

## Return the number of native decals currently represented on this receiver.
func get_surface_finish_projection_count() -> int:
	var count := 0
	for record in _projections:
		if record.tracked_native and is_instance_valid(record.native_decal):
			count += 1
	return count

func _process(delta: float) -> void:
	if not _has_bound_material():
		clear_projections()
		return
	var states := PackedVector4Array()
	var tints := PackedVector4Array()
	var footprints := PackedVector4Array()
	var has_world_projection := false
	var index := 0
	while index < _projections.size():
		var record := _projections[index]
		record.age += delta
		if ((record.tracked_native and not is_instance_valid(record.native_decal))
				or (not record.tracked_native and record.age >= record.lifetime)):
			_projections.remove_at(index)
			_uniforms_dirty = true
			continue
		if record.tracked_native:
			var color := record.native_decal.modulate
			var linear := color.srgb_to_linear()
			states.append(Vector4(record.slot, color.a if _finish_preview else 0.0, 0.0, 1.0))
			tints.append(Vector4(linear.r, linear.g, linear.b, 1.0))
		else:
			var t := record.age / record.lifetime
			var dissolve := clampf(t * t * (3.0 - 2.0 * t + record.tangent * (t - 1.0)), 0.0, 1.0)
			states.append(Vector4(record.slot, dissolve, record.turns, 0.0))
			tints.append(Vector4.ZERO)
		footprints.append(record.footprint)
		has_world_projection = has_world_projection or record.world_space
		index += 1
	if has_world_projection and not is_instance_valid(_bound_mesh):
		clear_projections()
		return
	var receiver_transform := _bound_mesh.get_global_transform_interpolated() if has_world_projection else Transform3D.IDENTITY
	if _uniforms_dirty or (has_world_projection and receiver_transform != _last_receiver_transform):
		_matrices.clear()
		for record in _projections:
			_matrices.append(record.inverse * receiver_transform if record.world_space else record.inverse)
		_last_receiver_transform = receiver_transform
		_material.set_shader_parameter("blood_projector_count", _matrices.size())
		if not _matrices.is_empty():
			_material.set_shader_parameter("blood_receiver_to_projector", _matrices)
			_material.set_shader_parameter("blood_projector_tint", tints)
			_material.set_shader_parameter("blood_projector_footprint", footprints)
		_uniforms_dirty = false
	if not states.is_empty():
		_material.set_shader_parameter("blood_projector_state", states)
	else:
		set_process(false)

## Remove all active projections on this receiver.
func clear_projections() -> void:
	for record in _projections:
		if record.tracked_native and is_instance_valid(record.native_decal):
			record.native_decal.show()
	_projections.clear()
	_matrices.clear()
	_uniforms_dirty = false
	if _material != null:
		_material.set_shader_parameter("blood_projector_count", 0)
	set_process(false)

func _bind_atlas() -> void:
	var source_atlas := _bound_atlas
	var tints := PackedVector4Array()
	var parameters := PackedVector4Array()
	var roughness := PackedVector4Array()
	for index in source_atlas.materials.size():
		var source := source_atlas.materials[index]
		var dark := source_atlas.source_darkness[index]
		var tint := source.albedo_color.srgb_to_linear()
		if dark >= 0.0 and not source_atlas.source_tints.is_empty():
			var base := source_atlas.source_tints[index].srgb_to_linear()
			tint.r /= maxf(0.000001, base.r)
			tint.g /= maxf(0.000001, base.g)
			tint.b /= maxf(0.000001, base.b)
		tints.append(Vector4(tint.r, tint.g, tint.b, 1.0))
		var normal_scale := -source.normal_scale if dark >= 0.0 else source.normal_scale
		parameters.append(Vector4(dark, normal_scale, source.metallic, source.metallic_specular))
		roughness.append(Vector4(source.roughness, 1.0, source.albedo_color.a, float(source.normal_enabled)))
	_material.set_shader_parameter("blood_coverage_only", source_atlas.coverage_only)
	_material.set_shader_parameter("blood_decal_coverage" if source_atlas.coverage_only else "blood_decal_color", source_atlas.color)
	_material.set_shader_parameter("blood_decal_normal", source_atlas.normal)
	_material.set_shader_parameter("blood_decal_orm", source_atlas.orm)
	var shader := _material.shader
	if shader.code.contains("#define BLOOD_PROJECTED_COOKED_NORMALS"):
		var layers := PackedInt32Array()
		layers.resize(BloodProjectedDecalAtlas.MAX_MATERIALS)
		layers.fill(-1)
		if source_atlas.cooked_normals != null:
			for index in source_atlas.cooked_normal_layers.size():
				layers[index] = source_atlas.cooked_normal_layers[index]
		_material.set_shader_parameter("blood_decal_cooked_normal", source_atlas.cooked_normals)
		_material.set_shader_parameter("blood_cooked_normal_layers", layers)
	if shader.code.contains("#define BLOOD_PROJECTED_DISTORTION"):
		_material.set_shader_parameter("blood_decal_distortion", source_atlas.distortion_noise)
		_material.set_shader_parameter("blood_decal_distortion_enabled", source_atlas.distortion_noise != null)
	_material.set_shader_parameter("blood_material_tint", tints)
	_material.set_shader_parameter("blood_material_parameters", parameters)
	_material.set_shader_parameter("blood_material_roughness", roughness)
	_bind_surface_finish()

func _bind_surface_finish() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("blood_surface_finish_enabled", surface_finish_enabled)
	_material.set_shader_parameter("blood_alpha_cutoff", alpha_cutoff)
	_material.set_shader_parameter("blood_grunge", grunge)
	_material.set_shader_parameter("blood_grunge_repeats_per_meter", grunge_repeats_per_meter)
	_material.set_shader_parameter("blood_grunge_strength", grunge_strength if grunge != null else 0.0)
