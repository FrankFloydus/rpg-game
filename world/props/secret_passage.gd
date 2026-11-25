extends Node3D
## A one-use concealed opening. The expedition owns the persistent opened IDs.

const LIFT_DISTANCE := 4.31
const LIFT_DURATION := 0.90
const MASON_DUST := preload("res://world/props/mason_wall_dust.tscn")
const ExplorationRules := preload("res://data/legendary_exploration_rules.tres")

var payload := {"kind": "secret_passage", "id": "", "opened": false}
var margin := 0.67
var text := "Shift the cracked wall"
var tint := Color("#d6c6ad")
var interaction_point: Vector3:
	get:
		# Stop the existing interaction ray just in front of the slab collider.
		return Vector3.UP * 1.48 + global_basis.z.normalized() * 0.20

var _wall_tint := Color.WHITE
var _wall_texture: Texture2D
var _wall_repeat := 0.0
var _clue_tween: Tween
var _dust: Node3D

@onready var _slab: Node3D = $Slab
@onready var _collider: CollisionShape3D = $Slab/WallBody/Collision
@onready var _face: MeshInstance3D = $Slab/CrackedFace


func configure(id: String, already_open: bool, wall_tint := Color.WHITE, wall_texture: Texture2D = null,
		repeats_per_metre := 0.0) -> void:
	payload.id = id
	payload.opened = already_open
	_wall_tint = wall_tint
	_wall_texture = wall_texture
	_wall_repeat = repeats_per_metre


func _ready() -> void:
	var face_material := _face.material_override as ShaderMaterial
	face_material.set_shader_parameter("stone_tint", _wall_tint)
	var edge_material := $Slab/StoneCore.material_override as StandardMaterial3D
	edge_material.albedo_color = _wall_tint
	if _wall_texture != null:
		face_material.set_shader_parameter(&"stone_albedo", _wall_texture)
		edge_material.albedo_texture = _wall_texture
	if _wall_repeat > 0.0:
		face_material.set_shader_parameter(&"stone_repeats_per_metre", _wall_repeat)
		edge_material.uv1_triplanar = true
		edge_material.uv1_world_triplanar = true
		edge_material.uv1_scale = Vector3.ONE * _wall_repeat
	if payload.opened:
		_finish_open()


func pick_available() -> bool:
	return not payload.opened


func clue_approach() -> Vector3:
	return to_global(Vector3(0, 0.035, 0.64))


func play_mason_clue() -> bool:
	if not is_node_ready() or not pick_available() or is_instance_valid(_dust):
		return false
	_dust = MASON_DUST.instantiate() as Node3D
	_dust.position = Vector3(0.11, 2.01, 0.085)
	_slab.add_child(_dust)
	var duration: float = ExplorationRules.mason_clue_seconds
	_clue_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	_clue_tween.tween_method(_set_clue_strength, 0.0, 1.0, duration * 0.17)
	_clue_tween.tween_interval(duration * 0.24)
	_clue_tween.tween_method(_set_clue_strength, 1.0, 0.0, duration * 0.59).set_trans(Tween.TRANS_SINE)
	return true


func _set_clue_strength(value: float) -> void:
	_face.set_instance_shader_parameter(&"clue_strength", value)


func open(animate := true) -> bool:
	if not pick_available():
		return false
	payload.opened = true
	if not is_node_ready():
		return true
	if _clue_tween != null:
		_clue_tween.kill()
		_set_clue_strength(0.0)
		if is_instance_valid(_dust):
			_dust.queue_free()
	if not animate:
		_finish_open()
		return true
	var lift := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	lift.tween_property(_slab, "position:y", LIFT_DISTANCE, LIFT_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	lift.tween_callback(_finish_open)
	return true


func _finish_open() -> void:
	_slab.hide()
	_collider.set_deferred("disabled", true)
