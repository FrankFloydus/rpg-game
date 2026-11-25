@tool
extends EditorProperty

const Preview := preload("res://addons/hearth_workbench/workbench_preview.gd")

var _picker: EditorResourcePicker
var _preview_panel: VBoxContainer
var _current: Resource
var _open_reference: Callable


func configure(type: String, help: String, open_reference := Callable()) -> void:
	_open_reference = open_reference
	_picker = EditorResourcePicker.new()
	_picker.base_type = type
	_picker.tooltip_text = help
	_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_picker.resource_changed.connect(func(resource: Resource) -> void:
		emit_changed(get_edited_property(), resource)
		_update_preview(resource))
	_picker.resource_selected.connect(func(resource: Resource, inspect: bool) -> void:
		if _open_reference.is_valid():
			_open_reference.call(resource)
		elif inspect:
			EditorInterface.inspect_object(resource))
	add_child(_picker)
	add_focusable(_picker)
	_preview_panel = VBoxContainer.new()
	add_child(_preview_panel)
	set_bottom_editor(_preview_panel)


func _update_property() -> void:
	var object := get_edited_object()
	if object == null:
		return
	var value := object.get(get_edited_property()) as Resource
	_picker.edited_resource = value
	_update_preview(value)


func _update_preview(value: Resource) -> void:
	if _current == value:
		return
	_current = value
	for child in _preview_panel.get_children():
		_preview_panel.remove_child(child)
		child.queue_free()
	if value == null:
		return
	if _open_reference.is_valid():
		var open := Button.new()
		open.text = "Open shared bob style"
		open.tooltip_text = "Edit this preset in its own record. Other weapons that reference the same file use the edit."
		open.pressed.connect(func() -> void: _open_reference.call(value))
		_preview_panel.add_child(open)
		return
	var viewer := Preview.new()
	if value is Texture2D:
		viewer.add_icon(value, "Assigned icon")
	elif value is PackedScene:
		viewer.offer_scene(value, "Preview effect", true)
	_preview_panel.add_child(viewer)
