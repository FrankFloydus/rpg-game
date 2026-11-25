@tool
extends "res://addons/godot-dismemberment/effects/projection/blood_projected_decal_receiver.gd"
## Rebinds an expedition floor when the player leaves and returns through a portal.

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint() or not _has_bound_material():
		return
	for pool in collision_body.find_children("*", "BloodPool", false, false):
		# Native pools bind when they first advance. Parked pools have already done so.
		if pool.get_age() > 0.0:
			var decal := pool.get_node_or_null("BloodDecal") as Decal
			if decal != null:
				track_surface_decal(decal, true)


func _exit_tree() -> void:
	super._exit_tree()
	if not Engine.is_editor_hint():
		request_ready()
