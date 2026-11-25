@tool
extends Node3D

## Restart the CPU particle children in the editor viewport.
@export_tool_button("Play Effect") var preview_effect := _preview

func _preview() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	for child in get_children():
		if child is CPUParticles3D:
			child.restart()
