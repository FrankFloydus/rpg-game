@tool
extends Window
## Browse runtime records, edit a draft, and save it back to its owning resource.

const Catalog := preload("res://addons/hearth_workbench/workbench_catalog.gd")
const Fields := preload("res://addons/hearth_workbench/workbench_fields.gd")
const Validation := preload("res://addons/hearth_workbench/workbench_validation.gd")
const Preview := preload("res://addons/hearth_workbench/workbench_preview.gd")
const WeaponTiming := preload("res://addons/hearth_workbench/workbench_weapon_timing.gd")
const ItemArt := preload("res://ui/item_art.gd")
const HeldModels := preload("res://data/items/held_item_models.gd")
const CardFace := preload("res://ui/card_face.gd")
const InventoryAppearance := preload("res://ui/inventory_appearance_preview.gd")

var _categories: Tree
var _records: Tree
var _search: LineEdit
var _record_heading: Label
var _details_heading: Label
var _source_label: Label
var _status: Label
var _save_button: Button
var _reload_button: Button
var _back_button: Button
var _review: ConfirmationDialog
var _inspector: EditorInspector
var _inventory_appearance: InventoryAppearance
var _fields_scroll: ScrollContainer
var _field_panel: VBoxContainer
var _category: Dictionary = {}
var _record: Dictionary = {}
var _reference_origin: Dictionary = {}
var _drafts: Dictionary[String, Resource] = {}
var _hashes: Dictionary[String, String] = {}
var _modified: Dictionary[String, bool] = {}


func _ready() -> void:
	title = "Hearth Workbench"
	theme = EditorInterface.get_editor_theme()
	min_size = Vector2i(_scaled(760), _scaled(500))
	transient = true
	close_requested.connect(hide)
	_build_interface()
	_build_categories()


func _build_interface() -> void:
	var layout := PanelContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if theme.has_color("dark_color_1", "Editor"):
		var background := StyleBoxFlat.new()
		background.bg_color = theme.get_color("dark_color_1", "Editor")
		layout.add_theme_stylebox_override("panel", background)
	add_child(layout)
	var margin := MarginContainer.new()
	for side in ["top", "bottom", "left", "right"]:
		margin.add_theme_constant_override("margin_" + side, _scaled(13))
	layout.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", _scaled(11))
	margin.add_child(column)

	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", _scaled(8))
	column.add_child(toolbar)
	var heading := _heading("Hearth Workbench", 22)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(heading)
	_back_button = Button.new()
	_back_button.text = "Back to ability"
	_back_button.tooltip_text = "Return to the ability whose effect you opened."
	_back_button.hide()
	_back_button.pressed.connect(_return_to_reference)
	toolbar.add_child(_back_button)
	_reload_button = Button.new()
	_reload_button.text = "Reload"
	_reload_button.tooltip_text = "Reload the selected source from disk"
	_reload_button.pressed.connect(_request_reload)
	toolbar.add_child(_reload_button)
	_save_button = Button.new()
	_save_button.text = "Save Changes"
	_save_button.tooltip_text = "Save all edits to the selected source file"
	_save_button.pressed.connect(_save_active_source)
	toolbar.add_child(_save_button)
	column.add_child(HSeparator.new())

	var panes := HSplitContainer.new()
	panes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(panes)
	var navigation := VBoxContainer.new()
	navigation.custom_minimum_size.x = _scaled(160)
	panes.add_child(navigation)
	navigation.add_child(_heading("Categories"))
	_categories = Tree.new()
	_categories.hide_root = true
	_categories.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_categories.item_selected.connect(_on_category_selected)
	navigation.add_child(_categories)

	var work := HSplitContainer.new()
	panes.add_child(work)
	var browser := VBoxContainer.new()
	browser.custom_minimum_size.x = _scaled(224)
	work.add_child(browser)
	_record_heading = _heading("Records")
	browser.add_child(_record_heading)
	_search = LineEdit.new()
	_search.placeholder_text = "Filter by name or ID"
	_search.clear_button_enabled = true
	Fields.style_line_edit(_search)
	_search.text_changed.connect(func(_value: String) -> void: _refresh_records())
	browser.add_child(_search)
	_records = Tree.new()
	_records.hide_root = true
	_records.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_records.columns = 2
	_records.column_titles_visible = true
	_records.set_column_title(0, "Name")
	_records.set_column_title(1, "ID / Level")
	_records.set_column_expand_ratio(0, 7)
	_records.set_column_expand_ratio(1, 4)
	_records.item_selected.connect(_on_record_selected)
	browser.add_child(_records)

	var details := VBoxContainer.new()
	details.custom_minimum_size.x = _scaled(310)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	work.add_child(details)
	_details_heading = _heading("Record", 18)
	_details_heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	details.add_child(_details_heading)
	_source_label = Label.new()
	_source_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_source_label.modulate.a = 0.72
	details.add_child(_source_label)
	details.add_child(HSeparator.new())
	_inventory_appearance = InventoryAppearance.new()
	_inventory_appearance.hide()
	details.add_child(_inventory_appearance)
	_fields_scroll = ScrollContainer.new()
	_fields_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_fields_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(_fields_scroll)
	_field_panel = VBoxContainer.new()
	_field_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fields_scroll.add_child(_field_panel)
	_inspector = EditorInspector.new()
	_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector.property_edited.connect(_inspector_edit_committed)
	details.add_child(_inspector)

	column.add_child(HSeparator.new())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_review = ConfirmationDialog.new()
	_review.title = "Reload Workbench Data"
	_review.dialog_text = "Discard unsaved changes to this file and reload it from disk?"
	_review.ok_button_text = "Discard and Reload"
	_review.confirmed.connect(_reload_active_source)
	add_child(_review)
	_on_record_selected()


func _build_categories() -> void:
	var root := _categories.create_item()
	var first: TreeItem
	for group: Dictionary in Catalog.GROUPS:
		var parent := _categories.create_item(root)
		parent.set_text(0, group.name)
		parent.set_tooltip_text(0, group.name)
		if theme.has_icon(group.icon, "EditorIcons"):
			parent.set_icon(0, theme.get_icon(group.icon, "EditorIcons"))
		parent.set_selectable(0, false)
		parent.collapsed = group.name != "Items"
		for category: Dictionary in group.categories:
			var child := _categories.create_item(parent)
			child.set_text(0, category.name)
			child.set_tooltip_text(0, category.name)
			child.set_metadata(0, category)
			if first == null:
				first = child
	if first != null:
		first.select(0)
		_show_category(first.get_metadata(0))


func _on_category_selected() -> void:
	var selected := _categories.get_selected()
	if selected == null:
		return
	_show_category(selected.get_metadata(0))


func _show_category(category: Dictionary) -> void:
	_category = category
	_record = {}
	_record_heading.text = _category.name
	_refresh_records()


func browse_reference(category: String, path: String) -> bool:
	var group := _categories.get_root().get_first_child()
	while group != null:
		var entry := group.get_first_child()
		while entry != null:
			if entry.get_text(0) == category:
				_search.text = ""
				group.collapsed = false
				entry.select(0)
				_show_category(entry.get_metadata(0))
				var row := _records.get_root().get_first_child()
				while row != null:
					if row.get_metadata(0).get("path", _category.get("path", "")) == path:
						row.select(0)
						_show_record(row.get_metadata(0))
						return true
					row = row.get_next()
				return false
			entry = entry.get_next()
		group = group.get_next()
	return false


func open_effect_reference(path: String) -> bool:
	return open_source_reference("Effects", path)


func open_source_reference(category: String, path: String) -> bool:
	var current := {"category": _category.get("name", ""), "path": _active_path(), "name": _record.get("name", "")}
	if not browse_reference(category, path):
		return false
	if current.category in ["Abilities", "First-person weapon motion"] and not str(current.path).is_empty():
		_reference_origin = current
		_back_button.text = "Back to ability" if current.category == "Abilities" else "Back to weapon motion"
		_back_button.tooltip_text = "Return to %s." % current.name
		_back_button.show()
	return true


func _return_to_reference() -> void:
	var previous := _reference_origin
	_reference_origin = {}
	_back_button.hide()
	if not previous.is_empty():
		browse_reference(previous.category, previous.path)


func _refresh_records() -> void:
	var previous: Dictionary = _record
	var resource := _load_source(_category.get("path", ""))
	var search := _search.text.strip_edges().to_lower()
	_records.clear()
	var root := _records.create_item()
	var first: TreeItem
	var keep: TreeItem
	for entry: Dictionary in Catalog.describe_records(_category, resource):
		if not search.is_empty() and search not in str(entry.name).to_lower() and search not in str(entry.id).to_lower():
			continue
		var item := _records.create_item(root)
		item.set_text(0, entry.name)
		item.set_text(1, entry.id)
		item.set_tooltip_text(0, entry.name)
		item.set_tooltip_text(1, entry.id)
		item.set_metadata(0, entry)
		if first == null:
			first = item
		if not previous.is_empty() and str(entry.get("path", entry.get("key", ""))) == str(previous.get("path", previous.get("key", ""))):
			keep = item
	var selected := keep if keep != null else first
	if selected != null:
		selected.select(0)
	_show_record(selected.get_metadata(0) if selected != null else {})


func _on_record_selected() -> void:
	var selected := _records.get_selected()
	_show_record(selected.get_metadata(0) if selected != null else {})


func _show_record(record: Dictionary) -> void:
	_record = record
	_inspector.edit(null)
	_inventory_appearance.hide()
	_inventory_appearance.bind_style(null)
	for child in _field_panel.get_children():
		_field_panel.remove_child(child)
		child.queue_free()
	var path := _active_path()
	var is_scene := bool(_record.get("scene", false))
	var resource := null if is_scene else _load_source(path)
	_details_heading.text = _record.get("name", "No matching records")
	_source_label.text = path.trim_prefix("res://")
	_source_label.tooltip_text = path
	_inspector.hide()
	_fields_scroll.show()
	_refresh_status()
	if is_scene:
		var open_scene := Button.new()
		open_scene.text = "Open Scene"
		open_scene.tooltip_text = "Open the scene in Godot to edit its Inspector settings, rig, and animations."
		if path == Catalog.PLAYER_SCENE:
			open_scene.tooltip_text = "Edit Player movement, jump, and minimum charge hold on the root Player node."
		open_scene.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		open_scene.pressed.connect(func() -> void:
			EditorInterface.open_scene_from_path(path)
			hide())
		_field_panel.add_child(open_scene)
		var scene := ResourceLoader.load(path, "PackedScene") as PackedScene
		if scene != null and path != Catalog.PLAYER_SCENE:
			var viewer := Preview.new()
			viewer.offer_scene(scene, "Preview model", false)
			_field_panel.add_child(viewer)
			if path.begins_with(Catalog.WEAPON_SCENES + "/"):
				var timing := WeaponTiming.new()
				timing.configure(scene, viewer, func() -> void: _open_animation_player(path))
				_field_panel.add_child(timing)
			elif ResourceLoader.exists(path.get_basename() + "_motion.tres"):
				var animation := Button.new()
				animation.text = "Open AnimationPlayer"
				animation.tooltip_text = "Edit this enemy's poses and ability clips. Set gameplay windup and recovery in Combat > Abilities."
				animation.pressed.connect(func() -> void: _open_animation_player(path))
				_field_panel.add_child(animation)
		return
	if _record.is_empty() or resource == null:
		if not path.is_empty() and resource == null:
			_status.text = "The source could not be loaded."
		return
	var field: StringName = _category.get("field", &"")
	if _category.has("fields"):
		_build_subset(resource, path)
	elif field.is_empty():
		_fields_scroll.hide()
		_inspector.show()
		_inspector.edit(resource)
		if path == Catalog.INVENTORY_ITEM_STYLE:
			_inventory_appearance.bind_style(resource)
			_inventory_appearance.show()
	else:
		_build_record(resource, path, field, _record.key)


func _build_subset(resource: Resource, path: String) -> void:
	var values := {}
	for field: StringName in _category.fields:
		var value: Variant = resource.get(field)
		if value != null:
			values[String(field)] = value
	var write := func(next: Dictionary) -> void:
		for key: String in next:
			resource.set(key, next[key])
		_mark_modified(path)
	_add_fields(values, write, &"", "")


func _build_record(resource: Resource, path: String, field: StringName, key: Variant) -> void:
	if _category.get("tier", false):
		var values := {"level": resource.tier_levels[key], "multiplier": resource.tier_multipliers[key]}
		var write_tier := func(next: Dictionary) -> void:
			resource.tier_levels[key] = int(next.level)
			resource.tier_multipliers[key] = float(next.multiplier)
			_mark_modified(path)
		_add_fields(values, write_tier, field, "")
		return
	var collection: Variant = resource.get(field)
	var write := func(next: Variant) -> void:
		collection[key] = next
		_watch_draft_value(next, path, resource.get_instance_id())
		_mark_modified(path)
	var record: Variant = collection[key]
	if field == &"legendaries":
		record = record.duplicate(true)
		record["drop_weight"] = float(record.get("drop_weight", 1.0))
		record["effect"] = str(record.get("effect", ""))
		record["affix_tier"] = int(record.get("affix_tier", 4))
		record["stat_ranges"] = record.get("stat_ranges", {})
	_add_fields(record, write, field, str(_record.name))


func _add_fields(values: Variant, write: Callable, kind: StringName, key: String) -> void:
	if values is Dictionary and kind in [&"bases", &"types", &"legendaries"]:
		var family := str(values.get("type", _record.get("key", "") if kind == &"types" else ""))
		var base_id := str(values.get("id", "")) if kind == &"bases" else ""
		if kind == &"legendaries":
			base_id = str(values.get("base_id", ""))
			var gear_catalogue := _load_source(Catalog.GEAR)
			for base: Dictionary in gear_catalogue.bases:
				if base.id == base_id:
					family = base.type
					break
		var thumbnail := ItemArt.texture_for_base(base_id, family)
		var model := HeldModels.scene_for(base_id, family)
		if thumbnail != null or model != null:
			var viewer := Preview.new()
			viewer.add_icon(thumbnail, "Inventory icon")
			if model != null:
				viewer.offer_scene(model, "View base model", false)
			_field_panel.add_child(viewer)
	if kind == &"cards":
		var viewer := Preview.new()
		viewer.add_icon(CardFace.art_texture(int(values.art)), "Card illustration")
		_field_panel.add_child(viewer)
	var form := Fields.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field_panel.add_child(form)
	var gear := _load_source(Catalog.GEAR)
	var types := PackedStringArray()
	var bases := PackedStringArray()
	if gear != null:
		types = PackedStringArray(gear.types.keys())
		for base: Dictionary in gear.bases:
			bases.append(base.id)
	var choices := {}
	if kind == &"legendaries":
		choices[""] = "No special effect"
		var definitions := _load_source(Catalog.LEGENDARIES)
		for definition: Dictionary in definitions.legendaries:
			var effect := str(definition.get("effect", ""))
			if not effect.is_empty():
				choices[effect] = effect.capitalize()
	elif kind == &"recipes":
		var definitions := _load_source(Catalog.AFFIXES)
		for pool: Array in [definitions.prefixes, definitions.suffixes]:
			for definition: Dictionary in pool:
				choices[definition.id] = definition.name
	form.build(values, write, kind, key, types, bases, choices)


func _active_path() -> String:
	return _record.get("path", _category.get("path", ""))


func _open_animation_player(path: String) -> void:
	EditorInterface.open_scene_from_path(path)
	hide()
	await get_tree().process_frame
	var scene := EditorInterface.get_edited_scene_root()
	if scene == null or scene.scene_file_path != path:
		return
	var animation_player := scene.find_child("AnimationPlayer", true, false)
	if animation_player != null:
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(animation_player)
		EditorInterface.edit_node(animation_player)


func _load_source(path: String) -> Resource:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	if _modified.has(path):
		return _drafts.get(path)
	var disk_hash := FileAccess.get_sha256(path)
	if _hashes.get(path, "") == disk_hash and _drafts.has(path):
		return _drafts[path]
	var draft := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if draft == null:
		return null
	_drafts[path] = draft
	_hashes[path] = disk_hash
	_watch_draft_value(draft, path, draft.get_instance_id())
	return draft


func _inspector_edit_committed(property: String) -> void:
	var path := _active_path()
	var draft := _drafts.get(path) as Resource
	var edited := _inspector.get_edited_object()
	if draft != null and edited != null:
		_watch_draft_value(edited.get(property), path, draft.get_instance_id())
		_mark_modified(path)


func _watch_draft_value(value: Variant, path: String, draft_id: int, visited: Dictionary[int, bool] = {}) -> void:
	if value is Resource:
		var resource := value as Resource
		var source_file := resource.resource_path.get_slice("::", 0)
		var object_id := resource.get_instance_id()
		if (not source_file.is_empty() and source_file != path) or visited.has(object_id) or resource is Script:
			return
		visited[object_id] = true
		var on_change := _draft_resource_changed.bind(path, draft_id)
		if not resource.changed.is_connected(on_change):
			resource.changed.connect(on_change)
		for property: Dictionary in resource.get_property_list():
			if (int(property.usage) & PROPERTY_USAGE_STORAGE) != 0 and property.type in [TYPE_OBJECT, TYPE_ARRAY, TYPE_DICTIONARY]:
				_watch_draft_value(resource.get(property.name), path, draft_id, visited)
	elif value is Array:
		for entry: Variant in value:
			_watch_draft_value(entry, path, draft_id, visited)
	elif value is Dictionary:
		for entry: Variant in value.values():
			_watch_draft_value(entry, path, draft_id, visited)


func _draft_resource_changed(path: String, draft_id: int) -> void:
	var draft := _drafts.get(path) as Resource
	if draft != null and draft.get_instance_id() == draft_id:
		_mark_modified(path)


func _mark_modified(path: String) -> void:
	if path.is_empty():
		return
	_modified[path] = true
	_refresh_status()


func _refresh_status() -> void:
	var path := _active_path()
	var editable: bool = not _record.get("scene", false) and not path.is_empty()
	_reload_button.disabled = not editable
	# Save is also available for native curve edits or resource handles.
	_save_button.disabled = not editable or not _drafts.has(path)
	var count := _modified.size()
	_status.text = "Unsaved changes in %d source file%s." % [count, "s" if count != 1 else ""] if count > 0 else ""


func _save_active_source() -> void:
	var path := _active_path()
	var resource: Resource = _drafts.get(path)
	if resource == null:
		return
	if FileAccess.get_sha256(path) != _hashes[path]:
		_status.text = "This source changed on disk. Reload it before saving."
		return
	var error := Validation.check(path, resource, _load_source(Catalog.GEAR))
	if not error.is_empty():
		_status.text = error
		return
	var result := ResourceSaver.save(resource, path)
	if result != OK:
		_status.text = "Could not save the source. %s" % error_string(result)
		return
	# Refresh the actual resource used by preloads, open inspectors and preview consumers.
	ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
	# Rebuild the Workbench from the serialized data. Dirty drafts remain separate from it.
	_drafts.erase(path)
	_hashes.erase(path)
	_modified.erase(path)
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem != null and not filesystem.is_scanning():
		filesystem.update_file(path)
	_refresh_records()
	_status.text = "Saved %s" % path.trim_prefix("res://")
	if not _modified.is_empty():
		_status.text += " · %d other source file(s) have unsaved changes." % _modified.size()


func _request_reload() -> void:
	# A curve can be edited through a nested Inspector control without editing the parent property.
	if not _active_path().is_empty():
		_review.popup_centered()


func _reload_active_source() -> void:
	var path := _active_path()
	var edited := _inspector.get_edited_object()
	_inspector.edit(null)
	if path.is_empty() or ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) == null:
		_inspector.edit(edited)
		_status.text = "Could not reload the source."
		return
	_drafts.erase(path)
	_modified.erase(path)
	_hashes.erase(path)
	_refresh_records()
	_status.text = "Reloaded %s" % path.trim_prefix("res://")


func _heading(message: String, font_size := 14) -> Label:
	var heading := Label.new()
	heading.text = message
	heading.add_theme_font_size_override("font_size", _scaled(font_size))
	return heading


func _scaled(value: int) -> int:
	return roundi(EditorInterface.get_editor_scale() * value)

