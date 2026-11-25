@tool
extends EditorScenePostImport
## Give Blender exports the game's matte finish when Godot imports or reimports them.

var _default_material := StandardMaterial3D.new()


func _post_import(scene: Node) -> Object:
	_apply_finish(_default_material)
	_apply_to_meshes(scene)
	return scene


func _apply_to_meshes(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		_apply_finish(node.material_override)
		_apply_finish(node.material_overlay)
		for surface in node.mesh.get_surface_count():
			var material: Material = node.mesh.surface_get_material(surface)
			if material == null:
				node.mesh.surface_set_material(surface, _default_material)
			else:
				_apply_finish(material)
			_apply_finish(node.get_surface_override_material(surface))

	for child in node.get_children():
		_apply_to_meshes(child)


func _apply_finish(material: Material) -> void:
	if material is BaseMaterial3D:
		material.roughness = 1.0
		material.roughness_texture = null
		material.metallic_specular = 0.0
