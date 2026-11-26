@tool
extends EditorProperty

const Schema := preload("res://addons/hearth_workbench/workbench_ability_schema.gd")
const Fields := preload("res://addons/hearth_workbench/workbench_fields.gd")
const Footprint := preload("res://addons/hearth_workbench/workbench_footprint.gd")

var _controls := {}
var _options := {}
var _profile_fields := VBoxContainer.new()
var _footprint: Control
var _shown_keys: Array[String] = []
var _select: OptionButton
var _updating := false
var _fixed_footprint := false


func configure_profile(fixed_footprint: bool) -> void:
	_fixed_footprint = fixed_footprint
	_profile_fields.add_theme_constant_override("separation", _scaled(14.0))
	add_child(_profile_fields)
	set_bottom_editor(_profile_fields)


func configure_choice(options: Dictionary, help: String) -> void:
	_options = options.duplicate()
	_select = _make_select(_options, help)
	Fields.describe_control(_select, "", help)
	_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_select.item_selected.connect(func(index: int) -> void:
		emit_changed(get_edited_property(), _select.get_item_metadata(index)))
	add_child(_select)
	add_focusable(_select)


func _update_property() -> void:
	var object := get_edited_object()
	if object == null:
		return
	var value: Variant = object.get(get_edited_property())
	if _select != null:
		_select.accessibility_name = str(get_edited_property()).get_file().capitalize()
		_select_value(_select, str(value))
		return
	if value is Dictionary:
		_update_profile(value)


func _update_profile(profile: Dictionary) -> void:
	var keys := Schema.keys(profile)
	if keys != _shown_keys:
		_shown_keys = keys
		_rebuild_profile(profile)
	_updating = true
	for key: String in keys:
		var control: Control = _controls.get(key)
		var current: Variant = profile.get(key, _default_value(key))
		if control is SpinBox:
			control.set_value_no_signal(float(current))
		elif control is CheckButton:
			control.set_pressed_no_signal(bool(current))
		elif control is OptionButton:
			_select_value(control, str(current))
		elif control is Label:
			control.text = str(current)
			Fields.describe_control(control, key.capitalize(), _script_data_help(control.text))
	_updating = false
	if _footprint != null:
		_footprint.show_profile(profile)


func _rebuild_profile(profile: Dictionary) -> void:
	for child in _profile_fields.get_children():
		_profile_fields.remove_child(child)
		child.queue_free()
	_controls.clear()
	var shape_fields: Array = Schema.SHAPE_FIELDS.get(str(profile.get("shape", "")), [])
	var targeting: Array[String] = []
	var shape: Array[String] = []
	var ability: Array[String] = []
	var other: Array[String] = []
	for key: String in _shown_keys:
		if key in ["shape", "start", "floor_warning"]:
			targeting.append(key)
		elif key in shape_fields:
			shape.append(key)
		elif Schema.FIELDS.has(key):
			ability.append(key)
		else:
			other.append(key)
	_add_group("Targeting", targeting, profile)
	_footprint = Footprint.new()
	_profile_fields.add_child(_footprint)
	_add_group("Shape dimensions", shape, profile)
	_add_group("Ability behavior", ability, profile)
	_add_group("Script data", other, profile)


func _add_group(heading: String, keys: Array[String], profile: Dictionary) -> void:
	if keys.is_empty():
		return
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", _scaled(8.0))
	var header := Label.new()
	header.text = heading
	header.add_theme_font_size_override("font_size", _scaled(14.0))
	_profile_fields.add_child(group)
	group.add_child(header)
	for key: String in keys:
		_add_profile_field(group, key, profile)


func _add_profile_field(group: VBoxContainer, key: String, profile: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _scaled(12.0))
	group.add_child(row)
	var title := key.capitalize()
	var help := Schema.field_help(key)
	var control: Control
	match key:
		"shape", "floor_warning":
			var shape_choice := key == "shape"
			title = "Hit shape" if shape_choice else "Floor warning"
			var fixed := shape_choice and _fixed_footprint
			if fixed:
				help = "This ability defines the shape. Adjust the shape's dimensions in the fields below."
			var choice := _make_select(Schema.SHAPES if shape_choice else Schema.WARNINGS, help)
			choice.disabled = fixed
			choice.item_selected.connect(func(index: int) -> void: _edit(key, choice.get_item_metadata(index)))
			control = choice
		_ when Schema.FIELDS.has(key):
			var field: Array = Schema.FIELDS[key]
			title = field[0]
			if field[3] is bool:
				var flag := CheckButton.new()
				flag.toggled.connect(func(next: bool) -> void: _edit(key, next))
				control = flag
			else:
				var spin := SpinBox.new()
				spin.min_value = 0.0
				spin.max_value = field[5] if field.size() > 5 else 1000.0
				spin.step = field[4]
				spin.suffix = field[2]
				spin.update_on_text_changed = true
				Fields.describe_control(spin.get_line_edit(), title, help)
				Fields.style_line_edit(spin.get_line_edit())
				spin.value_changed.connect(func(next: float) -> void: _edit(key, next))
				control = spin
		_:
			var unrecognized := Label.new()
			unrecognized.text = str(profile[key])
			unrecognized.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			unrecognized.mouse_filter = Control.MOUSE_FILTER_PASS
			help = _script_data_help(unrecognized.text)
			control = unrecognized
	var label := Fields.property_label(title, help)
	label.custom_minimum_size.x = _scaled(92.0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	Fields.describe_control(control, title, help)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if control is SpinBox or control is CheckButton:
		control.custom_minimum_size.x = _scaled(108.0) if control is SpinBox else 0.0
		control.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	row.add_child(control)
	_controls[key] = control


func _script_data_help(value: String) -> String:
	return "%s\nRead-only field preserved for the ability's script." % value


func _edit(key: String, value: Variant) -> void:
	if _updating:
		return
	var current: Dictionary = get_edited_object().get(get_edited_property())
	var next := current.duplicate(true)
	if value is String and value.is_empty():
		next.erase(key)
	else:
		next[key] = value
	if key == "shape":
		for old_key: String in Schema.SHAPE_FIELDS.get(str(current.get("shape", "")), []):
			if old_key not in Schema.SHAPE_FIELDS.get(value, []):
				next.erase(old_key)
		for new_key: String in Schema.SHAPE_FIELDS.get(value, []):
			if not next.has(new_key):
				next[new_key] = _default_value(new_key)
	emit_changed(get_edited_property(), next)
	if key == "shape":
		_update_profile.call_deferred(next)
	elif _footprint != null:
		_footprint.show_profile(next)


func _default_value(key: String) -> Variant:
	return Schema.FIELDS[key][3] if Schema.FIELDS.has(key) else ""


func _make_select(options: Dictionary, help: String) -> OptionButton:
	var button := OptionButton.new()
	button.tooltip_text = help
	button.fit_to_longest_item = false
	for value: String in options:
		button.add_item(options[value])
		button.set_item_metadata(button.item_count - 1, value)
	return button


func _select_value(choice: OptionButton, value: String) -> void:
	for index in choice.item_count:
		if choice.get_item_metadata(index) == value:
			choice.select(index)
			return
	choice.add_item(value.capitalize())
	choice.set_item_metadata(choice.item_count - 1, value)
	choice.select(choice.item_count - 1)


func _scaled(amount: float) -> int:
	return roundi(amount * EditorInterface.get_editor_scale())
