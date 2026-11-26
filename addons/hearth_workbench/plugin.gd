@tool
extends EditorPlugin

const Workbench := preload("res://addons/hearth_workbench/workbench_window.gd")
const Inspector := preload("res://addons/hearth_workbench/workbench_inspector.gd")

var _button: Button
var _workbench: Window
var _inspector: EditorInspectorPlugin


func _enter_tree() -> void:
	_inspector = Inspector.new()
	_inspector.open_effect = func(effect: EffectDefinition) -> void: _open_effect.call_deferred(effect)
	_inspector.open_bob_style = func(style: Resource) -> void: _open_bob_style.call_deferred(style)
	add_inspector_plugin(_inspector)
	_button = Button.new()
	_button.text = "Workbench"
	_button.tooltip_text = "Open the Hearth Below data workbench"
	_button.pressed.connect(open_workbench)
	add_control_to_container(CONTAINER_TOOLBAR, _button)
	add_tool_menu_item("Hearth Workbench", open_workbench)


func _exit_tree() -> void:
	remove_inspector_plugin(_inspector)
	remove_tool_menu_item("Hearth Workbench")
	remove_control_from_container(CONTAINER_TOOLBAR, _button)
	_button.queue_free()
	if is_instance_valid(_workbench):
		_workbench.queue_free()


func open_workbench() -> void:
	if not is_instance_valid(_workbench):
		_workbench = Workbench.new()
		_workbench.hide()
		EditorInterface.get_base_control().add_child(_workbench)
		_workbench.popup_centered_clamped(Vector2i(1120, 730), 0.9)
	else:
		_workbench.show()
		_workbench.grab_focus()


func _open_effect(effect: EffectDefinition) -> void:
	if is_instance_valid(_workbench) and _workbench.visible:
		if effect.resource_path.ends_with(".tres") and _workbench.open_effect_reference(effect.resource_path):
			return
		_workbench.hide()
	EditorInterface.inspect_object(effect)


func _open_bob_style(style: Resource) -> void:
	if is_instance_valid(_workbench) and _workbench.visible:
		if style.resource_path.ends_with(".tres") and _workbench.open_source_reference("Weapon bob styles", style.resource_path):
			return
		_workbench.hide()
	EditorInterface.inspect_object(style)

