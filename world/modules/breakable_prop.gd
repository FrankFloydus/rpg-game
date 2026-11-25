extends StaticBody3D
## A floor prop that releases painted fragments when struck.

const CombatImpact := preload("res://combat/effects/combat_impact.gd")
const Catalogue := preload("res://assets/audio/sound_catalogue.tres")

signal broken

@export var debris_scene: PackedScene
@export var break_cue := &"crate_break"
@export var impact_surface := &"wood"

@onready var _intact: Node3D = $Intact
@onready var _collider: CollisionShape3D = $Collider

var _broken := false


func aim_point() -> Vector3:
	return _collider.global_position


func break_from(direction: Vector3, point := Vector3.INF, normal := Vector3.ZERO) -> void:
	if _broken:
		return
	if point.is_finite():
		CombatImpact.contact(get_parent() as Node3D, point,
			-direction if normal.is_zero_approx() else normal, impact_surface)
	_disable_intact()
	broken.emit()

	var debris := debris_scene.instantiate() as Node3D
	add_child(debris)
	for piece in debris.get_children():
		if piece is MeshInstance3D:
			_scatter(piece, direction)
	debris.queue_free()

	if DisplayServer.get_name() != "headless":
		_play_break_sound()
	get_tree().create_timer(4.2, false).timeout.connect(queue_free)


func _play_break_sound() -> void:
	var cue := Catalogue.sound_for(break_cue)
	var stream := cue.make_one_shot() if cue != null else null
	if stream == null:
		return
	var sound := AudioStreamPlayer3D.new()
	sound.stream = stream
	sound.volume_db = cue.volume_db
	sound.max_distance = 12.0
	add_child(sound)
	sound.position = _collider.position
	sound.play()


func break_silently() -> void:
	if _broken:
		return
	_disable_intact()
	queue_free()


func _disable_intact() -> void:
	_broken = true
	remove_from_group(&"breakable_props")
	set_deferred("collision_layer", 0)
	_collider.set_deferred("disabled", true)
	_intact.hide()


func _scatter(piece: MeshInstance3D, direction: Vector3) -> void:
	var pose := piece.global_transform
	var shard := RigidBody3D.new()
	shard.name = "Shard"
	shard.collision_layer = 0
	shard.collision_mask = 1
	shard.mass = 0.12
	shard.linear_damp = 0.7
	shard.angular_damp = 1.2
	shard.top_level = true
	add_child(shard, true)
	shard.global_transform = pose.orthonormalized()

	var mesh := MeshInstance3D.new()
	mesh.mesh = piece.mesh
	mesh.transform = shard.global_transform.affine_inverse() * pose
	shard.add_child(mesh)

	var bounds := mesh.transform * mesh.get_aabb()
	var shape := BoxShape3D.new()
	shape.size = bounds.size.max(Vector3.ONE * 0.016)
	var collision := CollisionShape3D.new()
	collision.position = bounds.get_center()
	collision.shape = shape
	shard.add_child(collision)

	var offset := Vector3(pose.origin.x - global_position.x, 0.0, pose.origin.z - global_position.z)
	var outward := (offset * 3.2 + direction * 0.6).limit_length(1.25)
	shard.linear_velocity = outward * randf_range(1.2, 2.0) + Vector3.UP * randf_range(0.85, 1.65)
	shard.angular_velocity = Vector3(randf_range(-7.0, 7.0), randf_range(-7.0, 7.0), randf_range(-7.0, 7.0))
