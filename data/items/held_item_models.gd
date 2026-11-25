extends RefCounted
## Geometry for an authored base, shared by first-person equipment and ground loot.

const Gear := preload("res://data/items/bases.gd")
const DIRECTORY := "res://player/weapons/models/bases/"

static var _scenes: Dictionary[String, PackedScene] = {}


static func scene_for(base_id: String, type: String) -> PackedScene:
	if base_id.is_empty():
		return null
	for base: Dictionary in Gear.BASES:
		if base.get("id") != base_id or base.get("type") != type:
			continue
		if _scenes.has(base_id):
			return _scenes[base_id]
		var path := DIRECTORY.path_join(base_id + ".glb")
		if ResourceLoader.exists(path, "PackedScene"):
			var scene := ResourceLoader.load(path, "PackedScene") as PackedScene
			if scene != null:
				_scenes[base_id] = scene
			return scene
		break
	return null
