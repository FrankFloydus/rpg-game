@tool
class_name BloodProjectedDecalAtlas
extends Resource
## Shared, prebaked texture arrays for a projected blood receiver.

const MAX_MATERIALS := 20

## Material references in the same order as the texture array layers.
@export var materials: Array[BaseMaterial3D]
## Baked color and opacity array with one layer per material.
@export var color: TextureLayered
## Read the color array as linear coverage in its red channel and use a neutral color.
@export var coverage_only := false
## Baked tangent-space normal array with one layer per material.
@export var normal: TextureLayered
## Baked occlusion, roughness, and metallic array with one layer per material.
@export var orm: TextureLayered
## Source darkness per layer. A negative value uses the material's own color.
@export var source_darkness := PackedFloat32Array()
## Reference material tint per layer, for expressing edits relative to source color.
@export var source_tints := PackedColorArray()
## Built-in receiver shader supporting the optional cooked normal array.
@export var cooked_receiver_shader: Shader
## Optional source normal array containing Unreal's filtered mip levels.
@export var cooked_normals: Texture2DArray
## Cooked layer for each authored material. Use -1 to keep its ordinary normal layer.
@export var cooked_normal_layers := PackedInt32Array()
## Optional linear source noise for animated UVs on authored contact decals.
@export var distortion_noise: Texture2D
## Textures used to bake the color, normal, and ORM layer for each material.
@export var source_textures: Array[Texture2D]

func is_valid() -> bool:
	var count := materials.size()
	if count == 0 or count > MAX_MATERIALS or materials.has(null):
		return false
	if source_textures.size() != count * 3 or source_darkness.size() != count:
		return false
	if not source_tints.is_empty() and source_tints.size() != count:
		return false
	for texture in [color, normal, orm]:
		if texture == null or texture.get_layered_type() != TextureLayered.LAYERED_TYPE_2D_ARRAY \
				or texture.get_layers() != count:
			return false
	if cooked_normals == null:
		return cooked_normal_layers.is_empty()
	if cooked_receiver_shader == null or not cooked_normals.has_mipmaps() or cooked_normal_layers.size() != count:
		return false
	for index in count:
		var layer := cooked_normal_layers[index]
		if layer < -1 or layer >= cooked_normals.get_layers() or (layer >= 0 and source_darkness[index] < 0.0):
			return false
	return true

func find_material(material: BaseMaterial3D) -> int:
	var index := materials.find(material)
	if index < 0:
		return -1
	var offset := index * 3
	if source_textures[offset] != material.albedo_texture or source_textures[offset + 1] != material.normal_texture \
			or source_textures[offset + 2] != material.get_texture(BaseMaterial3D.TEXTURE_ORM):
		return -1
	return index

## Find a layer using the three texture references bound on a native decal.
func find_textures(albedo: Texture2D, normal_map: Texture2D, orm_map: Texture2D) -> int:
	for index in materials.size():
		var offset := index * 3
		if source_textures[offset] == albedo and source_textures[offset + 1] == normal_map \
				and source_textures[offset + 2] == orm_map:
			return index
	return -1
