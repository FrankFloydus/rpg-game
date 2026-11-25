@tool
extends EditorProperty

const Schema := preload("res://addons/hearth_workbench/workbench_ability_schema.gd")
const Fields := preload("res://addons/hearth_workbench/workbench_fields.gd")
const Footprint := preload("res://addons/hearth_workbench/workbench_footprint.gd")

var _controls := {}
var _options := {}
var _help := ""
var _unit := ""
var _profile_fields := VBoxContainer.new()
var _footprint: Control
var _shown_keys: Array[String] = []
var _select: OptionButton
var _updating := false
var _fixed_footprint := false


func configure_profile(fixed_footprint: bool) -> void:
	_fixed_footprint = fixed_footprint
	_help = "The attack's footprint and AI start distance. Only fields used by the selected shape or its ability are shown."
	_profile_fields.add_theme_constant_override("separation", 8)
	add_child(_profile_fields)
	set_bottom_editor(_profile_fields)


func configure_choice(options: Dictionary, help: String) -> void:
	_options = options.duplicate()
	_help = help
	_select = _make_select(_options, help)
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
		elif control is CheckBox:
			control.set_pressed_no_signal(bool(current))
		elif control is OptionButton:
			_select_value(control, str(current))
	_updating = false
	if _footprint != null:
		_footprint.show_profile(profile)


func _rebuild_profile(profile: Dictionary) -> void:
	for child in _profile_fields.get_children():
		_profile_fields.remove_child(child)
		child.queue_free()
	_controls.clear()
	_footprint = Footprint.new()
	_profile_fields.add_child(_footprint)
	for key: String in _shown_keys:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		_profile_fields.add_child(row)
		var title := Label.new()
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(title)
		var control: Control
		match key:
			"shape", "floor_warning":
				title.text = "Hit shape" if key == "shape" else "Floor warning"
				title.tooltip_text = _help if key == "shape" else "Draw the move's red ground warning before it lands. Marked enemy attacks cannot be blocked."
				var choice := _make_select(Schema.SHAPES if key == "shape" else Schema.WARNINGS, title.tooltip_text)
				if key == "shape" and _fixed_footprint:
					choice.disabled = true
					title.tooltip_text = "This ability's script owns the shape. Tune its size and timing in the fields below."
				choice.item_selected.connect(func(index: int) -> void: _edit(key, choice.get_item_metadata(index)))
				control = choice
			_ when Schema.FIELDS.has(key):
				var field: Array = Schema.FIELDS[key]
				title.text = field[0]
				title.tooltip_text = field[1]
				if field[3] is bool:
					var flag := CheckBox.new()
					flag.toggled.connect(func(next: bool) -> void: _edit(key, next))
					control = flag
				else:
					var spin := SpinBox.new()
					spin.min_value = 0.0
					spin.max_value = field[5] if field.size() > 5 else 1000.0
					spin.step = field[4]
					spin.suffix = field[2]
					spin.update_on_text_changed = true
					spin.get_line_edit().tooltip_text = title.tooltip_text
					Fields.style_line_edit(spin.get_line_edit())
					spin.value_changed.connect(func(next: float) -> void: _edit(key, next))
					control = spin
			_:
				title.text = key.capitalize()
				title.tooltip_text = "Script-specific data preserved from this resource."
				var unrecognized := Label.new()
				unrecognized.text = str(profile[key])
				control = unrecognized
		control.tooltip_text = title.tooltip_text
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(control)
		_controls[key] = control


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
