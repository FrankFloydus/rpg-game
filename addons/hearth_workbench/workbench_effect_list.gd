@tool
extends EditorProperty
## Ability references edit linkage here and open the effect's own record for tuning.

var _entries: Array[EffectDefinition] = []
var _navigate: Callable
var _list := VBoxContainer.new()
var _displayed: Array = []


func configure(entries: Array[EffectDefinition], navigate: Callable) -> void:
	_entries = entries
	_navigate = navigate
	_list.add_theme_constant_override("separation", 6)
	add_child(_list)
	set_bottom_editor(_list)


func _update_property() -> void:
	var object := get_edited_object()
	if object == null:
		return
	var effects: Array[EffectDefinition] = object.get(get_edited_property())
	if _displayed == effects and _list.get_child_count() > 0:
		return
	_displayed = effects.duplicate()
	_rebuild(effects)


func _rebuild(effects: Array[EffectDefinition]) -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	for index in effects.size():
		var effect := effects[index]
		var row := HBoxContainer.new()
		_list.add_child(row)
		var choice := OptionButton.new()
		choice.fit_to_longest_item = false
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.tooltip_text = "Effect preset attempted after a confirmed hit. Tuning the preset affects every ability referencing it."
		row.add_child(choice)
		if effect != null and effect not in _entries:
			choice.add_item(effect.display_name)
			choice.set_item_metadata(choice.item_count - 1, effect)
		for entry in _entries:
			choice.add_item(entry.display_name)
			choice.set_item_metadata(choice.item_count - 1, entry)
		choice.select(-1)
		for entry_index in choice.item_count:
			var entry: EffectDefinition = choice.get_item_metadata(entry_index)
			if effect != null and entry.resource_path == effect.resource_path:
				choice.select(entry_index)
				break
		choice.item_selected.connect(func(choice_index: int) -> void:
			var next := effects.duplicate()
			next[index] = choice.get_item_metadata(choice_index)
			emit_changed(get_edited_property(), next))
		var open := Button.new()
		open.text = "Open"
		open.tooltip_text = "Open the selected effect so you can tune its chance, duration, and visuals."
		open.disabled = effect == null
		open.pressed.connect(func() -> void: _navigate.call(effect))
		row.add_child(open)
		var remove := Button.new()
		remove.text = "−"
		remove.tooltip_text = "Remove this effect from the ability's hit."
		remove.pressed.connect(func() -> void:
			var next := effects.duplicate()
			next.remove_at(index)
			emit_changed(get_edited_property(), next))
		row.add_child(remove)
	var add := MenuButton.new()
	add.text = "Add on-hit effect"
	add.tooltip_text = "Choose an existing effect preset to attach to this ability's hit."
	add.disabled = _entries.is_empty()
	_list.add_child(add)
	var popup := add.get_popup()
	for entry in _entries:
		popup.add_item(entry.display_name)
	popup.index_pressed.connect(func(index: int) -> void:
		var next := effects.duplicate()
		next.append(_entries[index])
		emit_changed(get_edited_property(), next))
