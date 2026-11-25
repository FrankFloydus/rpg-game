@tool
class_name BloodGpuEffectLibrary
extends Resource
## Searchable list of editable PackedScene effect scenes.

const EffectScene = preload("res://addons/godot-dismemberment/effects/scenes/blood_gpu_effect_scene.gd")

## Editable effect scenes indexed by their System Name, Family, and Intensity.
@export var scenes: Array[PackedScene] = []

var _index: Array[Dictionary] = []
var _indexed_scenes: Array[PackedScene] = []

static func read_scene_metadata(scene: PackedScene) -> Dictionary:
	if scene == null:
		return {}
	var state := scene.get_state()
	if state.get_node_count() == 0:
		return {}
	var metadata := {&"system_name": state.get_node_name(0), &"family": &"burst", &"intensity": 1}
	return metadata if _read_root_properties(state, metadata) == EffectScene else {}

static func _read_root_properties(state: SceneState, metadata: Dictionary) -> Script:
	var base := state.get_base_scene_state()
	var script: Script = _read_root_properties(base, metadata) if base != null else null
	for index in state.get_node_property_count(0):
		var name := state.get_node_property_name(0, index)
		var value = state.get_node_property_value(0, index)
		if name == &"script":
			script = value as Script
		elif metadata.has(name):
			metadata[name] = value
	return script

func find_system(system_name: String) -> PackedScene:
	var key := system_name.strip_edges().to_lower()
	if key.is_empty():
		return null
	_ensure_index()
	for entry in _index:
		if entry.key == key:
			return entry.scene
	return null

func find_family(family: StringName, intensity: int) -> PackedScene:
	_ensure_index()
	var closest: PackedScene
	var nearest := 1 << 30
	for entry in _index:
		if entry.family != family:
			continue
		var distance := absi(entry.intensity - intensity)
		if distance < nearest:
			closest = entry.scene
			nearest = distance
			if distance == 0:
				break
	return closest

func _ensure_index() -> void:
	if not Engine.is_editor_hint() and _indexed_scenes == scenes:
		return
	_indexed_scenes = scenes.duplicate()
	_index.clear()
	for scene in scenes:
		var metadata := read_scene_metadata(scene)
		if metadata.is_empty():
			continue
		metadata.scene = scene
		metadata.key = String(metadata.system_name).strip_edges().to_lower()
		_index.append(metadata)
