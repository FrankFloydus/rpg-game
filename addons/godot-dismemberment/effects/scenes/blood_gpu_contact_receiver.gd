@tool
extends Node3D
## Receives the first collision from one of the effect's authored particle layers.

const SCRIPT_PATH := "res://addons/godot-dismemberment/effects/scenes/blood_gpu_contact_receiver.gd"
const DEFAULTS := {
	&"enabled": true, &"source_layer": &"Spots", &"target_layer": &"",
	&"reference_material": &"", &"material": null, &"use_decal_library": false,
	&"size_range": Vector2(0.2, 0.9), &"depth": 0.3, &"lifetime_range": Vector2(5.0, 6.0),
	&"orientation": 0, &"rotation_range": Vector2(0.0, TAU),
	&"follow_collision_body": true,
	&"dissolve_end_tangent": 3.109849, &"max_per_tick": 0,
}

## Allow this receiver to respond to collisions from its source layer.
@export var enabled: bool = DEFAULTS.enabled
## Name of the emitter whose particle collision triggers this receiver.
@export var source_layer: StringName = DEFAULTS.source_layer
## Optional effect layer to spawn at contact. Leave empty to project the decal material.
@export var target_layer: StringName = DEFAULTS.target_layer
## Identifier of the equivalent Niagara material for reference during authoring.
@export var reference_material: StringName = DEFAULTS.reference_material
## Material projected on impact when Target Layer is empty and no library decal is selected.
@export var material: BaseMaterial3D = DEFAULTS.material
## Pick a decal from the GoreComponent's library based on the receiving surface and impact.
@export var use_decal_library: bool = DEFAULTS.use_decal_library
## Minimum and maximum projected footprint in metres.
@export var size_range: Vector2 = DEFAULTS.size_range
## Full depth of the decal's projection volume, in metres.
@export_range(0.001, 2.0, 0.001, "or_greater", "suffix:m") var depth: float = DEFAULTS.depth
## Minimum and maximum time a decal remains active in seconds.
@export var lifetime_range: Vector2 = DEFAULTS.lifetime_range
## Niagara uses the shortest rotation from +X to the inward contact direction.
@export_enum("World Up", "Along Impact", "Niagara") var orientation: int = DEFAULTS.orientation
## Attach the decal to the hit body. Disable this to keep the projection at its world-space impact transform.
@export var follow_collision_body: bool = DEFAULTS.follow_collision_body
## Optional yaw around the surface normal, in radians.
@export var rotation_range: Vector2 = DEFAULTS.rotation_range
## End tangent of the normalized dissolve threshold curve.
@export_range(0.0, 5.0, 0.001) var dissolve_end_tangent: float = DEFAULTS.dissolve_end_tangent
## Zero allows every contact in a source simulation tick.
@export_range(0, 64, 1, "or_greater") var max_per_tick: int = DEFAULTS.max_per_tick

func get_receiver_settings() -> Dictionary:
	var settings := {}
	for field: StringName in DEFAULTS:
		settings[field] = get(field)
	return settings

static func read_node_receivers(root: Node) -> Dictionary[StringName, Array]:
	var receivers: Dictionary[StringName, Array] = {}
	for child in root.get_children():
		var script: Script = child.get_script()
		if script != null and script.resource_path == SCRIPT_PATH and child.enabled:
			_add_receiver(receivers, child.get_receiver_settings())
	return receivers

static func _add_receiver(receivers: Dictionary[StringName, Array], receiver: Dictionary) -> void:
	var source: StringName = receiver.source_layer
	if not receivers.has(source):
		receivers[source] = []
	receivers[source].append(receiver)

static func read_scene_receivers(scene: PackedScene) -> Dictionary[StringName, Array]:
	var receivers: Dictionary[StringName, Array] = {}
	var state := scene.get_state()
	for index in range(1, state.get_node_count()):
		if state.get_node_path(index, true) != NodePath("."):
			continue
		var receiver := DEFAULTS.duplicate()
		var is_receiver := false
		for property_index in state.get_node_property_count(index):
			var field := state.get_node_property_name(index, property_index)
			var value = state.get_node_property_value(index, property_index)
			if field == &"script" and value is Script and value.resource_path == SCRIPT_PATH:
				is_receiver = true
			elif receiver.has(field):
				receiver[field] = value
		if is_receiver and receiver.enabled:
			_add_receiver(receivers, receiver)
	return receivers
