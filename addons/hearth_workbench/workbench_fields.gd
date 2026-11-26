@tool
extends VBoxContainer
## Uses familiar Godot controls to edit individual records inside the runtime tables.

const Validation := preload("res://addons/hearth_workbench/workbench_validation.gd")
const AbilitySchema := preload("res://addons/hearth_workbench/workbench_ability_schema.gd")
const PropertyHelp := preload("res://addons/hearth_workbench/workbench_property_help.gd")
const AffixRecords := preload("res://data/items/affix_records.tres")
const CurveGraph := preload("res://addons/hearth_workbench/workbench_curve_editor.tscn")
const CurveEditor := preload("res://addons/hearth_workbench/workbench_curve_editor.gd")
const PowerGraphs := preload("res://addons/hearth_workbench/workbench_power_curves.tscn")
const PowerCurves := preload("res://addons/hearth_workbench/workbench_power_curves.gd")
const Progression := preload("res://systems/character_progression.gd")
const TITLES := {
	"stats": "Stats", "implicit": "Implicit stats", "level": "Minimum level", "weight": "Roll weight",
	"id": "Record ID", "base_id": "Base item", "side": "Affix side", "slots": "Eligible slots",
	"size": "Footprint", "legendary_card_eligibility": "Legendary card eligibility",
	"minimum": "Minimum rarity",
	"name": "Name",
	"multiplier": "Roll multiplier", "damage_min": "Minimum physical damage", "damage_max": "Maximum physical damage",
	"max_health": "Maximum life", "xp": "XP",
	"flat": "Flat damage", "power": "Weapon damage multiplier", "heal": "Maximum Life restored",
	"protection": "Damage reduction", "protection_time": "Protection duration",
	"strike_bonus": "Bonus per attack", "strike_time": "Strike bonus duration", "strikes": "Number of attacks",
	"timed_bonus": "Timed damage bonus", "timed_duration": "Damage bonus duration",
	"drop_weight": "Drop weight", "vendor_max_depth": "Stock level cap",
	"vendor_price_per_depth": "Price increase per stock level",
	"affix_id": "Crafted affix",
	"affix_tier": "Fixed stat tier",
}
const MELEE_TITLES := {
	"reach_target": "Target reach", "reach_assist": "Reach assist cap",
	"width": "Sweep width", "height": "Sweep height", "length_scale": "Base length multiplier",
	"damage": "Damage cleave budget", "stagger": "Stagger cleave budget",
	"slides_armor": "Slide through armor", "heavy": "Charged",
}
const MELEE_FIELD_ORDER := ["light", "heavy", "reach_assist", "reach_target", "width", "height",
	"length_scale", "damage", "stagger", "slides_armor"]
const RARITY := ["normal", "magic", "rare", "legendary"]
const BASIC_FIELDS := ["id", "name", "type", "slot", "level", "rarity", "minimum_depth", "description", "play_sound"]
const UNITS := {
	"size": "cells", "radius": "m", "protection_time": "s", "strike_time": "s",
	"timed_duration": "s", "power": "×", "multiplier": "×",
	"reach_target": "m", "reach_assist": "m", "length_scale": "×",
}

var _kind: StringName
var _types: PackedStringArray
var _base_ids: PackedStringArray
var _record_choices: Dictionary
var _rarity_chances: Dictionary[String, SpinBox] = {}


func build(value: Variant, write: Callable, kind: StringName, record_key: String,
		types: PackedStringArray, base_ids: PackedStringArray, record_choices := {}) -> void:
	_kind = kind
	_types = types
	_base_ids = base_ids
	_record_choices = record_choices
	add_theme_constant_override("separation", roundi(_scaled(12.0)))
	if value is Dictionary:
		_build_dictionary(self, value, write)
	elif value is PackedStringArray and kind in [&"rare_prefixes", &"rare_suffixes"]:
		_build_name_pool(value, write)
	else:
		_add_field(self, record_key, value, write, "")


func _build_name_pool(words: PackedStringArray, write: Callable) -> void:
	var label := Label.new()
	label.text = "One name entry per line"
	label.tooltip_text = "Each nonempty line enters this pool. The game picks one at random when it names an item."
	add_child(label)
	var text := TextEdit.new()
	text.text = "\n".join(words)
	text.tooltip_text = label.tooltip_text
	text.custom_minimum_size.y = _scaled(265.0)
	text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	describe_control(text, "Name pool", label.tooltip_text)
	var background := _input_background()
	if background != null:
		text.add_theme_stylebox_override("normal", background)
	add_child(text)
	text.text_changed.connect(func() -> void:
		var next := PackedStringArray()
		for line: String in text.text.split("\n", false):
			var entry := line.strip_edges()
			if not entry.is_empty():
				next.append(entry)
		write.call(next))


func _build_dictionary(parent: VBoxContainer, values: Dictionary, write: Callable, scope := "") -> void:
	var ordered: Array[String] = []
	for key: String in BASIC_FIELDS:
		if values.has(key) or (key == "play_sound" and _kind == &"cards" and scope.is_empty()):
			ordered.append(key)
	for key: String in values:
		if key not in BASIC_FIELDS and not values[key] is Dictionary:
			ordered.append(key)
	for key: String in values:
		if values[key] is Dictionary and key != "stat_ranges":
			ordered.append(key)
	if values.get("stat_ranges") is Dictionary:
		ordered.append("stat_ranges")
	if scope.is_empty() and _kind in [&"prefixes", &"suffixes"] and not values.has("slots"):
		ordered.append("slots")
	if _kind == &"families":
		ordered.sort_custom(func(a: String, b: String) -> bool:
			return MELEE_FIELD_ORDER.find(a) < MELEE_FIELD_ORDER.find(b))
	for key: String in ordered:
		var child_write := func(next: Variant) -> void:
			if (key == "play_sound" and next == null) or (key == "slots" and next.is_empty()):
				values.erase(key)
			else:
				values[key] = next
			if _kind == &"item_profiles" and key == "minimum":
				_update_rarity_chances(String(next))
			write.call(values)
		if key == "stat_ranges" and _kind == &"legendaries":
			_build_legendary_ranges(parent, values.get("stats", {}), values[key], child_write)
		else:
			var value: Variant = values.get(key, [] if key == "slots" else null)
			_add_field(parent, key, value, child_write, scope)
	if _kind == &"item_profiles":
		_update_rarity_chances(String(values.get("minimum", "normal")))


func _build_legendary_ranges(parent: VBoxContainer, stats: Dictionary, stored: Dictionary, write: Callable) -> void:
	_section(parent, "Fixed Stat Roll Ranges", "stat_ranges")
	var ranges: Dictionary[String, Vector2] = {}
	for stat: String in stored:
		if stored[stat] is Vector2:
			ranges[stat] = stored[stat]
	for stat: String in stats:
		var title := str(TITLES.get(stat, stat.capitalize()))
		var help := "Generated copies roll %s between these bounds. Leave the checkbox off to keep the fixed value above." % title
		var fallback := float(stats[stat])
		var bounds: Vector2 = ranges.get(stat, Vector2(fallback, fallback))
		var block := VBoxContainer.new()
		block.add_theme_constant_override("separation", roundi(_scaled(6.0)))
		parent.add_child(block)
		var enabled := CheckBox.new()
		enabled.text = title
		describe_control(enabled, "Roll %s within a range" % title, help)
		enabled.button_pressed = ranges.has(stat)
		block.add_child(enabled)
		var pair := HBoxContainer.new()
		pair.tooltip_text = help
		pair.visible = enabled.button_pressed
		block.add_child(pair)
		var update := func(next: Array) -> void:
			ranges[stat] = Vector2(next[0], next[1])
			write.call(ranges.duplicate())
		_components(pair, [bounds.x, bounds.y], ["Lowest roll", "Highest roll"], false, update, -10000.0)
		enabled.toggled.connect(func(roll_range: bool) -> void:
			pair.visible = roll_range
			if roll_range:
				var editors := pair.find_children("*", "SpinBox", true, false)
				ranges[stat] = Vector2(editors[0].value, editors[1].value)
			else:
				ranges.erase(stat)
			write.call(ranges.duplicate()))


func _add_field(parent: VBoxContainer, key: String, value: Variant, write: Callable, scope: String) -> void:
	if key == "art":
		return
	var melee_profile := _kind == &"families"
	if melee_profile and key == "name":
		return
	var titles := MELEE_TITLES if melee_profile else TITLES
	var title := str(titles.get(key, key.capitalize()))
	if key == "life_by_level" and value is Array:
		var editor := CurveGraph.instantiate() as CurveEditor
		editor.configure("Player level", "Base Life", "Sets unmodified maximum Life at each milestone. Life interpolates linearly between milestones.")
		editor.show_milestones(value, Progression.MAX_LEVEL)
		editor.milestones_committed.connect(func(points: Array[Vector2], _operation: StringName, _index: int) -> void: write.call(points))
		editor.get_node("%Gestures").set_meta(&"workbench_property", key)
		parent.add_child(editor)
		return
	if key == "power_by_level" and value is Array:
		var editor := PowerGraphs.instantiate() as PowerCurves
		editor.configure(value, Progression.MAX_LEVEL)
		editor.milestones_committed.connect(write)
		editor.get_node("SharedLevels").set_meta(&"workbench_property", key)
		parent.add_child(editor)
		return
	if value is Curve:
		var editor := CurveGraph.instantiate() as CurveEditor
		var help := PropertyHelp.field(key, scope, _kind)
		_section(parent, title)
		editor.configure("Offset", "Value", help)
		editor.show_curve(value)
		editor.set_read_only(not value.is_built_in())
		editor.curve_committed.connect(write)
		parent.add_child(editor)
		return
	if value is Dictionary:
		if key == "stats" and _kind == &"legendaries":
			title = "Fixed Stat Values"
		_section(parent, title, key)
		_build_dictionary(parent, value, write, key)
		return
	var help := PropertyHelp.field(key, scope, _kind)
	if key == "description" and (value is String or value is StringName):
		var write_description := write
		if value is StringName:
			write_description = func(next: String) -> void: write.call(StringName(next))
		_add_description(parent, title, help, str(value), write_description)
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(_scaled(16.0)))
	parent.add_child(row)
	var label := property_label(title, help)
	label.set_meta(&"workbench_property", key)
	row.add_child(label)
	row.tooltip_text = help
	if key == "id":
		var identifier := _readonly(str(value))
		describe_control(identifier, title, "%s\nRead only · %s" % [str(value), help])
		row.add_child(identifier)
		return
	if key == "play_sound" and _kind == &"cards":
		_add_card_sound(parent, row, value as HearthSoundCue, write)
		return
	if value is Vector2i:
		_components(row, [value.x, value.y], ["Width", "Height"], false,
			func(parts: Array) -> void: write.call(Vector2i(int(parts[0]), int(parts[1]))),
			1.0, [12.0, 6.0], str(UNITS.get(key, "")))
	elif typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		var probability := _kind in [&"card_chances", &"item_profiles"] or key in [
			"legendary_card_eligibility",
			"vendor_rare_chance", "vendor_price_per_depth", "heal", "protection", "strike_bonus", "timed_bonus"]
		var minimum := 0.0 if scope not in ["stats", "implicit"] else -10000.0
		var maximum := 100000.0
		if key in ["level", "minimum_depth", "vendor_upgrade_level", "vendor_max_depth"]:
			minimum = 1.0
		elif key == "drop_weight":
			minimum = 0.0001
		elif key == "affix_tier":
			minimum = 1.0
			maximum = maxf(1.0, float(AffixRecords.tier_levels.size()))
		if key == "vendor_max_depth":
			maximum = 100.0
		elif key == "vendor_price_per_depth":
			maximum = 25.0
		var unit := "m" if melee_profile and key in ["width", "height"] else str(UNITS.get(key, ""))
		var number := _add_number(row, value, write, probability, minimum, maximum, title, unit)
		if _kind == &"item_profiles" and key in ["magic", "rare"]:
			_rarity_chances[key] = number
	elif value is bool:
		var box := CheckButton.new()
		box.button_pressed = value
		box.toggled.connect(write)
		describe_control(box, title, help)
		row.add_child(box)
	elif value is Array:
		if key == "slots":
			_slot_choices(row, value, write, help)
		elif value.size() == 2 and typeof(value[0]) in [TYPE_INT, TYPE_FLOAT]:
			# Some ranges start with integral bounds but permit a later fractional balance change.
			_components(row, [float(value[0]), float(value[1])], ["Minimum", "Maximum"], false, write)
		else:
			row.add_child(_readonly(", ".join(PackedStringArray(value))))
	elif value is String or value is StringName:
		var write_text: Callable = write
		if value is StringName:
			write_text = func(next: String) -> void: write.call(StringName(next))
		var options := _options(key)
		if not options.is_empty():
			_add_choice(row, str(value), options, write_text, key, title)
		else:
			var line := LineEdit.new()
			line.text = value
			describe_control(line, title, help)
			style_line_edit(line)
			line.text_changed.connect(write_text)
			_add_filling(row, line)
	else:
		row.add_child(_readonly(str(value)))


func _add_description(parent: VBoxContainer, title: String, help: String, value: String, write: Callable) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", roundi(_scaled(6.0)))
	parent.add_child(block)
	var label := property_label(title, help)
	label.set_meta(&"workbench_property", "description")
	block.add_child(label)
	var description := TextEdit.new()
	description.text = value
	description.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	var background := _input_background()
	if background != null:
		description.add_theme_stylebox_override("normal", background)
	description.custom_minimum_size.y = _scaled(84.0)
	describe_control(description, title, help)
	description.text_changed.connect(func() -> void: write.call(description.text))
	block.add_child(description)


func _add_card_sound(parent: VBoxContainer, row: HBoxContainer, value: HearthSoundCue, write: Callable) -> void:
	var picker := EditorResourcePicker.new()
	picker.base_type = "HearthSoundCue"
	describe_control(picker, "Play sound", row.tooltip_text)
	_add_filling(row, picker)
	var inspector := EditorInspector.create_default_inspector()
	inspector.custom_minimum_size.y = _scaled(175.0)
	parent.add_child(inspector)
	var edit_sound := func(sound: Resource) -> void:
		# Keep edits on this card even when the picker receives a shared cue.
		var draft := sound.duplicate(true) as HearthSoundCue if sound != null else null
		picker.edited_resource = draft
		inspector.edit(draft)
		inspector.visible = draft != null
	edit_sound.call(value)
	picker.resource_changed.connect(func(sound: Resource) -> void:
		edit_sound.call(sound)
		write.call(picker.edited_resource))
	inspector.property_edited.connect(func(_property: String) -> void: write.call(picker.edited_resource))


func _add_number(parent: Control, value: Variant, write: Callable, probability: bool,
		minimum: float, maximum := 100000.0, title := "", unit := "") -> SpinBox:
	var integral := value is int and not probability
	var spin := SpinBox.new()
	spin.alignment = HORIZONTAL_ALIGNMENT_LEFT
	spin.min_value = minimum
	spin.max_value = minf(100.0, maximum) if probability else maximum
	spin.step = 1.0 if integral else (0.001 if probability else 0.0001)
	spin.value = float(value) * (100.0 if probability else 1.0)
	spin.suffix = "%" if probability else unit
	spin.update_on_text_changed = true
	describe_control(spin, title, parent.tooltip_text)
	describe_control(spin.get_line_edit(), title, parent.tooltip_text)
	style_line_edit(spin.get_line_edit())
	spin.value_changed.connect(func(next: float) -> void:
		if integral:
			write.call(roundi(next))
		else:
			write.call(next * (0.01 if probability else 1.0)))
	if parent is HBoxContainer:
		spin.custom_minimum_size.x = _scaled(142.0)
		spin.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
		parent.add_child(spin)
	else:
		_add_filling(parent, spin)
	return spin


func _update_rarity_chances(minimum_rarity: String) -> void:
	for rarity in _rarity_chances:
		var spin: SpinBox = _rarity_chances[rarity]
		var available: bool = minimum_rarity == "normal" or (minimum_rarity == "magic" and rarity == "rare")
		spin.editable = available
		spin.tooltip_text = spin.get_parent().tooltip_text if available else "The minimum rarity already guarantees this result or better."
		spin.get_line_edit().tooltip_text = spin.tooltip_text


func _components(parent: HBoxContainer, parts: Array, names: Array, probability: bool,
		write: Callable, minimum := 0.0, maximum: Variant = 100000.0, unit := "") -> void:
	var values := parts.duplicate()
	for index in values.size():
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.tooltip_text = parent.tooltip_text
		column.add_theme_constant_override("separation", roundi(_scaled(4.0)))
		parent.add_child(column)
		var caption := _readonly(names[index])
		caption.tooltip_text = parent.tooltip_text
		caption.add_theme_font_size_override("font_size", roundi(_scaled(12.0)))
		column.add_child(caption)
		var part_write := func(next: Variant) -> void:
			values[index] = next
			write.call(values.duplicate())
		var ceiling := float(maximum[index]) if maximum is Array else float(maximum)
		_add_number(column, values[index], part_write, probability, minimum, ceiling, names[index], unit)


func _options(key: String) -> PackedStringArray:
	match key:
		"type": return _types
		"slot": return PackedStringArray(Validation.SLOTS)
		"element": return PackedStringArray(AbilitySchema.DAMAGE_TYPES.keys())
		"condition": return PackedStringArray(["", "chilled", "rooted"])
		"effect", "affix_id": return PackedStringArray(_record_choices.keys())
		"base_id": return _base_ids
		"minimum": return PackedStringArray(RARITY.slice(0, 3))
		"rarity": return PackedStringArray(RARITY)
		"side": return PackedStringArray(["prefix", "suffix"])
	return []


func _add_choice(parent: Control, value: String, options: PackedStringArray, write: Callable, key: String, title: String) -> void:
	var choice := OptionButton.new()
	if not options.has(value):
		options.insert(0, value)
	choice.fit_to_longest_item = false
	describe_control(choice, title, parent.tooltip_text)
	for option in options:
		var label := "Default" if option.is_empty() else option.capitalize()
		if key in ["effect", "affix_id"]:
			label = _record_choices.get(option, label)
		choice.add_item(label)
	choice.select(options.find(value))
	choice.item_selected.connect(func(index: int) -> void: write.call(options[index]))
	_add_filling(parent, choice)


func _slot_choices(parent: Control, slots: Array, write: Callable, help: String) -> void:
	var menu := MenuButton.new()
	menu.flat = false
	menu.focus_mode = Control.FOCUS_ALL
	var popup := menu.get_popup()
	popup.hide_on_checkable_item_selection = false
	for slot: String in Validation.SLOTS:
		popup.add_check_item(slot.capitalize())
		popup.set_item_checked(popup.item_count - 1, slot in slots)
		popup.set_item_metadata(popup.item_count - 1, slot)
	_update_slot_menu(menu, slots, help)
	popup.index_pressed.connect(func(index: int) -> void:
		popup.set_item_checked(index, not popup.is_item_checked(index))
		var next: Array[String] = []
		for row in popup.item_count:
			if popup.is_item_checked(row):
				next.append(popup.get_item_metadata(row))
		_update_slot_menu(menu, next, help)
		write.call(next))
	_add_filling(parent, menu)


func _update_slot_menu(menu: MenuButton, slots: Array, help: String) -> void:
	var names := PackedStringArray()
	for slot in slots:
		names.append(str(slot).capitalize())
	var selected := "Any equipment slot" if names.is_empty() else ", ".join(names)
	menu.text = selected if names.size() <= 2 else "%d eligible slots" % names.size()
	describe_control(menu, "Eligible slots", "%s\n%s" % [selected, help])


func _section(parent: VBoxContainer, title: String, key := "") -> void:
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", roundi(_scaled(10.0)))
	parent.add_child(header)
	header.add_child(HSeparator.new())
	var label := Label.new()
	label.text = title
	label.set_meta(&"workbench_property", key)
	label.add_theme_font_size_override("font_size", int(_scaled(15.0)))
	header.add_child(label)


func _readonly(message: String) -> Label:
	var label := Label.new()
	label.text = message
	label.modulate.a = 0.73
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.tooltip_text = message
	return label


func _add_filling(parent: Control, child: Control) -> void:
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(child)


func _scaled(amount: float) -> float:
	return EditorInterface.get_editor_scale() * amount


static func property_label(title: String, help: String) -> Label:
	var label := Label.new()
	label.text = title
	label.tooltip_text = help
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 132.0 * EditorInterface.get_editor_scale()
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


static func describe_control(control: Control, title: String, help: String) -> void:
	control.tooltip_text = help
	control.accessibility_name = title
	control.accessibility_description = help


static func style_line_edit(input: LineEdit) -> void:
	var background := _input_background()
	if background != null:
		input.add_theme_stylebox_override("normal", background)


static func _input_background() -> StyleBoxFlat:
	var editor_theme := EditorInterface.get_editor_theme()
	if not editor_theme.has_color("base_color", "Editor"):
		return null
	var background := StyleBoxFlat.new()
	background.bg_color = editor_theme.get_color("base_color", "Editor")
	background.set_corner_radius_all(roundi(5.0 * EditorInterface.get_editor_scale()))
	background.set_border_width_all(1)
	background.border_color = editor_theme.get_color("font_color", "Editor")
	background.border_color.a = 0.14
	background.content_margin_left = 8.0 * EditorInterface.get_editor_scale()
	background.content_margin_right = background.content_margin_left
	background.content_margin_top = 3.0 * EditorInterface.get_editor_scale()
	background.content_margin_bottom = background.content_margin_top
	return background

