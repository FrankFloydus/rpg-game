@tool
extends EditorProperty

const Graph := preload("res://addons/hearth_workbench/workbench_curve_editor.tscn")
const GraphEditor := preload("res://addons/hearth_workbench/workbench_curve_editor.gd")

var _open: Button
var _panel: VBoxContainer
var _picker: EditorResourcePicker
var _editor: GraphEditor
var _read_only := false


func configure(axis_x: String, axis_y: String, help: String) -> void:
	_open = Button.new()
	_open.name = &"OpenCurve"
	_open.toggle_mode = true
	_open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_open.tooltip_text = help
	_open.accessibility_name = "Edit " + axis_y.to_lower() + " curve"
	_open.accessibility_description = help
	_open.toggled.connect(_toggle)
	add_child(_open)
	add_focusable(_open)

	_panel = VBoxContainer.new()
	_panel.hide()
	_panel.add_theme_constant_override("separation", 8)
	add_child(_panel)
	set_bottom_editor(_panel)
	_editor = Graph.instantiate() as GraphEditor
	_editor.configure(axis_x, axis_y, help)
	_editor.curve_committed.connect(_replace)
	_panel.add_child(_editor)
	add_focusable(_editor.graph_control())
	for control: Control in _editor.coordinate_controls():
		add_focusable(control)

	_picker = EditorResourcePicker.new()
	_picker.name = &"CurveSource"
	_picker.base_type = "Curve"
	_picker.tooltip_text = "Assign, create, or clear a Curve resource. Open its resource to configure axis bounds and bake resolution."
	_picker.accessibility_name = "Curve resource options"
	_picker.accessibility_description = _picker.tooltip_text
	_picker.resource_changed.connect(func(resource: Resource) -> void: _replace(resource as Curve))
	_picker.resource_selected.connect(func(resource: Resource, inspect: bool) -> void:
		if inspect:
			EditorInterface.inspect_object(resource))
	_panel.add_child(_picker)
	add_focusable(_picker)


func _update_property() -> void:
	var object := get_edited_object()
	if object == null:
		return
	var curve := object.get(get_edited_property()) as Curve
	_picker.edited_resource = curve
	_present(curve)


func _present(curve: Curve) -> void:
	var external := curve != null and not curve.is_built_in()
	_open.text = "Set up curve" if curve == null else ("Curve · %d points" % curve.point_count)
	_editor.visible = curve != null
	_editor.show_curve(curve)
	_editor.set_read_only(_read_only or external)
	_picker.editable = not _read_only


func _set_read_only(read_only: bool) -> void:
	_read_only = read_only
	if _picker != null:
		_present(_picker.edited_resource as Curve)


func _toggle(expanded: bool) -> void:
	_panel.visible = expanded
	update_minimum_size()


func _replace(curve: Curve) -> void:
	if _read_only:
		return
	_picker.edited_resource = curve
	_present(curve)
	emit_changed(get_edited_property(), curve)
