extends Node
## Holds inactive standard projectiles for one floor or Training Ground.

const ProjectileScene := preload("res://combat/effects/enemy_projectile.tscn")
const POOL_NAME := &"EnemyProjectilePool"
const MAX_RETAINED := 32

var _available: Array[Node3D] = []


static func take(actors: Node) -> Node3D:
	var pool := actors.get_node_or_null(NodePath(POOL_NAME))
	if pool == null:
		pool = new()
		pool.name = POOL_NAME
		actors.add_child(pool)
	return pool._take_shot()


func _take_shot() -> Node3D:
	var projectile: Node3D = ProjectileScene.instantiate() if _available.is_empty() else _available.pop_back()
	projectile.recycler = _return_shot
	get_parent().add_child(projectile)
	return projectile


func _return_shot(projectile: Node3D) -> void:
	var actors := get_parent()
	if _available.size() >= MAX_RETAINED or actors == null or actors.is_queued_for_deletion():
		projectile.queue_free()
		return
	actors.remove_child(projectile)
	_available.append(projectile)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for projectile in _available:
			projectile.free()
		_available.clear()
