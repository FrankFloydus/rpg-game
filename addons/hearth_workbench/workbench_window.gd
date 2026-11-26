@tool
extends Window
## Browse runtime records, edit a draft, and save it back to its owning resource.

const Layout := preload("res://addons/hearth_workbench/workbench_layout.tscn")
const QuickFind := preload("res://addons/hearth_workbench/workbench_quick_find.tscn")
const Style := preload("res://addons/hearth_workbench/workbench_style.gd")
const PropertyHelp := preload("res://addons/hearth_workbench/workbench_property_help.gd")

const Catalog := preload("res://addons/hearth_workbench/workbench_catalog.gd")
const Fields := preload("res://addons/hearth_workbench/workbench_fields.gd")
const Validation := preload("res://addons/hearth_workbench/workbench_validation.gd")
const Preview := preload("res://addons/hearth_workbench/workbench_preview.gd")
const WeaponTiming := preload("res://addons/hearth_workbench/workbench_weapon_timing.gd")
const WeaponHitShake := preload("res://addons/hearth_workbench/workbench_hit_shake.gd")
const ItemArt := preload("res://ui/item_art.gd")
const HeldModels := preload("res://data/items/held_item_models.gd")
const CardFace := preload("res://ui/card_face.gd")
const InventoryAppearance := preload("res://ui/inventory_appearance_preview.gd")

var _layout: PanelContainer
var _quick_find: PopupPanel
var _categories: Tree
var _records: Tree
var _search: LineEdit
var _record_heading: Label
var _details_heading: Label
var _source_label: Label
var _status: Label
var _draft_status: Label
var _breadcrumb: Label
var _record_count: Label
var _scene_button: Button
var _browser_toggle: Button
var _tabs: HBoxContainer
var _last_tabs: Dictionary[String, int] = {}
var _sections_by_id: Dictionary[String, TreeItem] = {}
var _section_rebuild := false
var _record_rebuild := false
var _single_record := false
var _save_button: Button
var _reload_button: Button
var _back_button: Button
var _review: ConfirmationDialog
var _inspector: EditorInspector
var _native_filter: LineEdit
var _native_toolbar: HBoxContainer
var _inventory_appearance: InventoryAppearance
var _fields_scroll: ScrollContainer
var _field_panel: VBoxContainer
var _category: Dictionary = {}
var _record: Dictionary = {}
var _reference_origin: Dictionary = {}
var _drafts: Dictionary[String, Resource] = {}
var _hashes: Dictionary[String, String] = {}
var _modified: Dictionary[String, bool] = {}
var _hit_shake_state: Dictionary = {}


func _ready() -> void:
	title = "Hearth Workbench"
	theme = Style.build(EditorInterface.get_editor_theme(), EditorInterface.get_editor_scale())
	min_size = Vector2i(_scaled(760), _scaled(510))
	transient = true
	close_requested.connect(hide)
	_build_interface()
	_build_categories()
	_autosize_browsers()
	size_changed.connect(_autosize_browsers)


func _build_interface() -> void:
	_layout = Layout.instantiate()
	add_child(_layout)
	_categories = _layout.get_node("%Sections")
	_records = _layout.get_node("%Records")
	_search = _layout.get_node("%RecordFilter")
	_record_heading = _layout.get_node("%RecordHeading")
	_details_heading = _layout.get_node("%DetailHeading")
	_source_label = _layout.get_node("%SourceLabel")
	_status = _layout.get_node("%Status")
	_draft_status = _layout.get_node("%DraftStatus")
	_breadcrumb = _layout.get_node("%Breadcrumb")
	_record_count = _layout.get_node("%RecordCount")
	_scene_button = _layout.get_node("%OpenScene")
	_tabs = _layout.get_node("%DetailTabs")
	_fields_scroll = _layout.get_node("%FieldsScroll")
	_field_panel = _layout.get_node("%Fields")
	_save_button = _layout.get_node("%SaveButton")
	_reload_button = _layout.get_node("%ReloadButton")
	_back_button = _layout.get_node("%BackButton")
	_browser_toggle = _layout.get_node("%BrowserToggle")
	_save_button.theme_type_variation = &"WorkbenchPrimary"
	_back_button.pressed.connect(_return_to_reference)
	_save_button.pressed.connect(_save_active_source)
	_reload_button.pressed.connect(_request_reload)
	_scene_button.pressed.connect(_open_current_scene)
	_browser_toggle.toggled.connect(_set_browsers_visible)
	var command_button: Button = _layout.get_node("%CommandButton")
	command_button.pressed.connect(_open_quick_find)
	_categories.item_selected.connect(_on_category_selected)
	_records.item_selected.connect(_on_record_selected)
	_search.text_changed.connect(func(_text: String) -> void: _refresh_records())
	_search.text_submitted.connect(func(_text: String) -> void: _records.grab_focus())
	var details: VBoxContainer = _layout.get_node("%Details")
	_inventory_appearance = InventoryAppearance.new()
	_inventory_appearance.hide()
	details.add_child(_inventory_appearance)
	details.move_child(_inventory_appearance, _fields_scroll.get_index())
	_native_filter = LineEdit.new()
	_native_filter.name = &"PropertyFilter"
	_native_filter.placeholder_text = "Filter properties"
	_native_filter.clear_button_enabled = true
	_native_filter.tooltip_text = "Search settings in this resource. Clear to see all properties."
	_native_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_native_toolbar = HBoxContainer.new()
	_native_toolbar.add_child(_native_filter)
	details.add_child(_native_toolbar)
	details.move_child(_native_toolbar, _fields_scroll.get_index())
	_inspector = EditorInspector.create_default_inspector(_native_filter)
	_inspector.name = &"NativeInspector"
	_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inspector.property_edited.connect(_inspector_edit_committed)
	details.add_child(_inspector)
	var expand_groups := Button.new()
	expand_groups.text = "Expand"
	expand_groups.tooltip_text = "Expand the property groups in this resource."
	expand_groups.pressed.connect(_inspector.expand_all_folding)
	_native_toolbar.add_child(expand_groups)
	var collapse_groups := Button.new()
	collapse_groups.text = "Collapse"
	collapse_groups.tooltip_text = "Collapse the property groups in this resource."
	collapse_groups.pressed.connect(_inspector.collapse_all_folding)
	_native_toolbar.add_child(collapse_groups)
	_quick_find = QuickFind.instantiate()
	add_child(_quick_find)
	_quick_find.theme = theme
	_quick_find.configure(EditorInterface.get_editor_scale())
	_review = ConfirmationDialog.new()
	_review.title = "Reload source"
	_review.ok_button_text = "Discard draft and reload"
	_review.confirmed.connect(_reload_active_source)
	add_child(_review)
	_style_layout()
	_on_record_selected()


func _style_layout() -> void:
	for spec: Array in [["BarInset", 12, 6], ["SectionInset", 9, 12],
			["RecordInset", 9, 12], ["DetailInset", 19, 12], ["FooterInset", 13, 5]]:
		Style.inset(_layout.get_node("%" + spec[0]), _scaled(spec[1]), _scaled(spec[2]))
	for name_key: String in ["SectionPane", "RecordPane"]:
		var pane: PanelContainer = _layout.get_node("%" + name_key)
		pane.add_theme_stylebox_override("panel", Style.panel(Style.SIDEBAR))
	for name_key: String in ["SectionLabel", "RecordCount", "SourceLabel", "Breadcrumb", "Status"]:
		var label: Label = _layout.get_node("%" + name_key)
		label.add_theme_color_override("font_color", Style.MUTED)
		label.add_theme_font_size_override("font_size", _scaled(12 if name_key != "Breadcrumb" else 14))
	_details_heading.add_theme_font_size_override("font_size", _scaled(22))
	_record_heading.add_theme_font_size_override("font_size", _scaled(15))
	_categories.add_theme_font_size_override("font_size", _scaled(12))
	_categories.add_theme_constant_override("item_margin", _scaled(8))
	_field_panel.add_theme_constant_override("separation", _scaled(13))
	_layout.get_node("Stack").add_theme_constant_override("separation", 0)
	_layout.get_node("%Body").add_theme_constant_override("separation", 0)
	_layout.get_node("%Details").add_theme_constant_override("separation", _scaled(7))
	_layout.get_node("%TopBar").add_theme_constant_override("separation", _scaled(8))
	if theme.has_icon("Search", "EditorIcons"):
		_search.right_icon = theme.get_icon("Search", "EditorIcons")


func _autosize_browsers() -> void:
	var logical_width := float(size.x) / EditorInterface.get_editor_scale()
	var compact := logical_width < 850
	_layout.get_node("%SectionPane").custom_minimum_size.x = _scaled(155 if compact else 160)
	_layout.get_node("%RecordPane").custom_minimum_size.x = _scaled(145 if compact else 162)
	_layout.get_node("%DetailInset").add_theme_constant_override("margin_left", _scaled(15 if compact else 18))
	_layout.get_node("%DetailInset").add_theme_constant_override("margin_right", _scaled(15 if compact else 18))


func _set_browsers_visible(shown: bool) -> void:
	for pane_name: String in ["SectionPane", "SectionRule", "RecordPane", "RecordRule"]:
		_layout.get_node("%" + pane_name).visible = shown and (not _single_record or not pane_name.begins_with("Record"))


func _input(event: InputEvent) -> void:
	if not visible or _quick_find.visible or _review.visible:
		return
	if event is not InputEventKey or not event.pressed or event.echo:
		return
	if not (event.ctrl_pressed or event.meta_pressed) or event.alt_pressed or event.shift_pressed:
		return
	match event.keycode:
		KEY_K:
			_open_quick_find()
		KEY_F:
			_focus_filter()
		KEY_S:
			_save_active_source()
		KEY_B:
			_browser_toggle.button_pressed = not _browser_toggle.button_pressed
		_:
			return
	set_input_as_handled()


func _focus_filter() -> void:
	if _single_record:
		if _native_toolbar.visible:
			_native_filter.grab_focus()
			_native_filter.select_all()
		else:
			_open_quick_find()
		return
	_browser_toggle.button_pressed = true
	_search.grab_focus()
	_search.select_all()


func _settle_field() -> void:
	var focused := gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		focused.release_focus()


func _open_current_scene() -> void:
	var path := _active_path()
	if not path.is_empty():
		EditorInterface.open_scene_from_path(path)
		hide()


func _open_quick_find() -> void:
	var entries: Array[Dictionary] = [
		{"label": "Filter this section", "detail": "Ctrl+F", "group": "Actions", "action": _focus_filter},
	]
	if not _save_button.disabled:
		entries.append({"label": "Save changes", "detail": "Ctrl+S", "group": "Actions",
			"action": _save_active_source})
	if not _reload_button.disabled:
		entries.append({"label": "Reload active source", "group": "Actions", "action": _request_reload})
	if _scene_button.visible:
		entries.append({"label": "Open scene", "group": "Actions", "action": _open_current_scene})
	for section: TreeItem in _sections_by_id.values():
		var category: Dictionary = section.get_metadata(0)
		var category_title := Catalog.category_label(category)
		var category_context: String = category.group
		var keywords := "%s %s %s" % [category.name, category_context, category.get("description", "")]
		var nearby := Catalog.category_id(category) == Catalog.category_id(_category)
		entries.append({"label": category_title, "detail": category_context, "keywords": keywords,
			"group": "Sections", "nearby": nearby, "action": _select_category.bind(section)})
		var resource := _search_resource(category.get("path", "")) if not category.get("scene", false) else null
		for record: Dictionary in Catalog.describe_records(category, resource):
			var name := _display_record(category, record)
			var record_path: String = record.get("path", category.get("path", ""))
			var record_keywords := "%s %s %s" % [record.id, category_title, record_path]
			var active := nearby and _same_record(record, _record)
			var destination := _select_category.bind(section, record)
			if name != category_title or category.has("directory"):
				entries.append({"label": name, "detail": category_title, "keywords": record_keywords,
					"group": "Records", "nearby": active, "action": destination})
			_index_settings(entries, section, category, record, name, record_path, resource, record_keywords, active)
	var target_size := Vector2i(mini(_scaled(600), size.x - _scaled(40)), mini(_scaled(426), size.y - _scaled(48)))
	var context := _details_heading.text if not _record.is_empty() else "Workspace"
	_quick_find.open(context, entries, target_size, gui_get_focus_owner())


func _index_settings(entries: Array[Dictionary], section: TreeItem, category: Dictionary,
		record: Dictionary, name: String, path: String, resource: Resource, keywords: String, active: bool) -> void:
	if record.get("scene", false):
		if category.get("directory", "") != Catalog.WEAPON_SCENES:
			return
		var timing_keywords := "%s input buffer trace start trace end impact combo timing" % keywords
		entries.append({"label": "Attack timing", "detail": name, "keywords": timing_keywords,
			"group": "Settings", "nearby": active, "action": _open_setting.bind(section, record, "", 1)})
		if not Catalog.weapon_hit_shake_source(path).is_empty():
			entries.append({"label": "Hit feedback", "detail": name,
				"keywords": "%s hit shake rebound hard stop camera pitch yaw roll duration" % keywords,
				"group": "Settings", "nearby": active, "action": _open_setting.bind(section, record, "", 2)})
		return
	var properties: Array = category.get("fields", []).duplicate()
	var field: StringName = category.get("field", &"")
	var native := field.is_empty() and not category.has("fields")
	if native:
		var object := resource if resource != null else _search_resource(path)
		if object != null:
			for spec: Dictionary in object.get_property_list():
				var label: String = spec.name
				if (int(spec.usage) & PROPERTY_USAGE_EDITOR) != 0 and label != "script" and not label.begins_with("resource_"):
					properties.append(label)
	elif not field.is_empty() and resource != null:
		var collection: Variant = resource.get(field)
		var value: Variant = collection[record.key]
		if value is Dictionary:
			properties = value.keys()
	for property: Variant in properties:
		var key := String(property)
		var label := str(Fields.TITLES.get(key, PropertyHelp.property_label(key))) if not native else PropertyHelp.property_label(key)
		entries.append({"label": label, "detail": name, "keywords": "%s %s %s" % [keywords, name, key],
			"group": "Settings", "focused": active, "action": _open_setting.bind(section, record, key, -1)})


func _search_resource(path: String) -> Resource:
	if _modified.has(path):
		return _drafts.get(path)
	return ResourceLoader.load(path) as Resource if not path.is_empty() and ResourceLoader.exists(path) else null


func _open_setting(section: TreeItem, record: Dictionary, property: String, tab: int) -> void:
	if tab >= 0:
		_last_tabs[record.path] = tab
	_select_category(section, record)
	if property.is_empty():
		return
	if _native_toolbar.visible:
		_native_filter.text = property.capitalize()
		_native_filter.text_changed.emit(_native_filter.text)
		_native_filter.grab_focus()
	else:
		_reveal_field.call_deferred(property)


func _reveal_field(property: String) -> void:
	var label := PropertyHelp.property_label(property)
	for child: Node in _field_panel.find_children("*", "Label", true, false):
		if child.get_meta(&"workbench_property", "") == property or child.text == label:
			_fields_scroll.ensure_control_visible(child)
			return


func _build_categories() -> void:
	var root := _categories.create_item()
	var first: TreeItem
	for group: Dictionary in Catalog.GROUPS:
		var parent := _categories.create_item(root)
		parent.set_text(0, group.name)
		parent.set_tooltip_text(0, group.name)
		parent.set_custom_color(0, Style.ACCENT)
		parent.collapsed = first != null
		for category: Dictionary in group.categories:
			var item := _categories.create_item(parent)
			var route := category.duplicate()
			route["group"] = group.name
			item.set_text(0, route.get("nav_label", Catalog.category_label(route)))
			item.set_tooltip_text(0, route.get("description", route.name))
			item.set_metadata(0, route)
			_sections_by_id[Catalog.category_id(route)] = item
			if first == null:
				first = item
	if first != null:
		_select_category(first)
		_categories.scroll_to_item(first.get_parent())


func _on_category_selected() -> void:
	if _section_rebuild:
		return
	var selected := _categories.get_selected()
	if selected == null:
		return
	if selected.get_metadata(0) == null:
		selected.collapsed = not selected.collapsed
		var active := _sections_by_id.get(Catalog.category_id(_category)) as TreeItem
		if active != null and not active.get_parent().collapsed:
			_section_rebuild = true
			active.select(0)
			_section_rebuild = false
		return
	_show_category(selected.get_metadata(0))


func _select_category(item: TreeItem, preferred: Dictionary = {}) -> void:
	_section_rebuild = true
	item.get_parent().collapsed = false
	item.select(0)
	_categories.ensure_cursor_is_visible()
	_section_rebuild = false
	_show_category(item.get_metadata(0), preferred)


func _show_category(category: Dictionary, preferred: Dictionary = {}) -> void:
	if category != _category or not preferred.is_empty():
		_search.text = ""
	_category = category
	_record = preferred
	_record_heading.text = Catalog.category_label(_category)
	_record_heading.tooltip_text = _category.get("description", "")
	_refresh_records()


func browse_reference(category: String, path: String, record: Dictionary = {}) -> bool:
	for item: TreeItem in _sections_by_id.values():
		var route: Dictionary = item.get_metadata(0)
		if not Catalog.matches_category(route, category):
			continue
		_select_category(item, record if not record.is_empty() else {"path": path})
		return _active_path() == path
	return false


func open_effect_reference(path: String) -> bool:
	return open_source_reference("Effects", path)


func open_source_reference(category: String, path: String) -> bool:
	var current := {"category": _category.get("name", ""), "path": _active_path(),
			"name": _record.get("name", ""), "record": _record.duplicate()}
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
		browse_reference(previous.category, previous.path, previous.record)


func _refresh_records() -> void:
	var previous: Dictionary = _record
	var resource := _load_source(_category.get("path", "")) if not _category.get("scene", false) else null
	var search := _search.text.strip_edges().to_lower()
	_record_rebuild = true
	_records.clear()
	var root := _records.create_item()
	var first: TreeItem
	var keep: TreeItem
	var count := 0
	var entries := Catalog.describe_records(_category, resource)
	_single_record = entries.size() == 1 and not _category.has("field") and not _category.has("directory")
	_set_browsers_visible(_browser_toggle.button_pressed)
	for entry: Dictionary in entries:
		var label := _display_record(_category, entry)
		var searchable := ("%s %s" % [label, entry.id]).to_lower().replace("_", " ")
		if not _contains_terms(searchable, search):
			continue
		var item := _records.create_item(root)
		item.set_text(0, label)
		item.set_tooltip_text(0, label if entry.id.is_empty() else "%s · %s" % [label, entry.id])
		item.set_metadata(0, entry)
		if first == null:
			first = item
		if not previous.is_empty() and _same_record(entry, previous):
			keep = item
		count += 1
	_record_count.text = "%d %s" % [count, "record" if count == 1 else "records"]
	if count != entries.size():
		_record_count.text = "%d of %d records" % [count, entries.size()]
	var selected := keep if keep != null else first
	if selected != null:
		selected.select(0)
		_records.ensure_cursor_is_visible()
	_record_rebuild = false
	_show_record(selected.get_metadata(0) if selected != null else {})


func _same_record(entry: Dictionary, previous: Dictionary) -> bool:
	if entry.has("key") or previous.has("key"):
		return entry.get("key") == previous.get("key")
	if entry.has("path") or previous.has("path"):
		return entry.get("path", _category.get("path", "")) == previous.get("path", "")
	return entry.get("id") == previous.get("id") and entry.get("name") == previous.get("name")


func _display_record(category: Dictionary, record: Dictionary) -> String:
	if record.name == category.name:
		return Catalog.category_label(category)
	if category.get("directory") == Catalog.WEAPON_SCENES and str(record.id).ends_with("_2h"):
		return str(record.id).trim_suffix("_2h").capitalize() + " 2H"
	return record.name


func _contains_terms(searchable: String, search: String) -> bool:
	for term: String in search.replace("_", " ").split(" ", false):
		if term not in searchable:
			return false
	return true


func _on_record_selected() -> void:
	if _record_rebuild:
		return
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
	_fields_scroll.scroll_vertical = 0
	var path := _active_path() if not _record.is_empty() else ""
	var is_scene := bool(_record.get("scene", false))
	var resource := null if is_scene else _load_source(path)
	var shake_path := Catalog.weapon_hit_shake_source(path) if is_scene else ""
	var shake_draft := _load_source(shake_path)
	var heading := _display_record(_category, _record) if not _record.is_empty() else "No matching records"
	_details_heading.text = heading
	_breadcrumb.text = "Workbench  /  %s  /  %s" % [_category.get("group", "Workspace"), Catalog.category_label(_category)]
	_breadcrumb.tooltip_text = _breadcrumb.text
	_source_label.text = _category.get("description", "")
	_source_label.tooltip_text = _source_label.text + ("\n" + path if not path.is_empty() else "")
	if shake_draft != null:
		_source_label.tooltip_text += "\nHit feedback edits · " + shake_path
	_scene_button.visible = is_scene
	_scene_button.tooltip_text = "Open %s in the Godot scene editor." % path
	_tabs.hide()
	for tab: Node in _tabs.get_children():
		_tabs.remove_child(tab)
		tab.queue_free()
	_inspector.hide()
	_native_filter.text = ""
	_native_toolbar.hide()
	_fields_scroll.show()
	_refresh_status()
	if is_scene:
		_build_scene_tabs(path, shake_path, shake_draft)
		return
	if _record.is_empty() or resource == null:
		if not path.is_empty() and resource == null:
			_set_status("The source could not be loaded.", Style.ERROR)
		elif _category.has("name"):
			_field_panel.add_child(_heading("Change the record filter or use Quick find.", 14))
		return
	var field: StringName = _category.get("field", &"")
	if _category.has("fields"):
		_build_subset(resource, path)
	elif field.is_empty():
		_fields_scroll.hide()
		_native_toolbar.show()
		_inspector.show()
		_inspector.edit(resource)
		if path == Catalog.INVENTORY_ITEM_STYLE:
			_inventory_appearance.bind_style(resource)
			_inventory_appearance.show()
	else:
		_build_record(resource, path, field, _record.key)


func _build_scene_tabs(path: String, shake_path: String, shake_draft: Resource) -> void:
	if path == Catalog.PLAYER_SCENE:
		_field_panel.add_child(_heading("Movement and charge are authored on the Player node.", 14))
		return
	var scene := ResourceLoader.load(path, "PackedScene") as PackedScene
	if scene == null:
		return
	var names := PackedStringArray(["Model"])
	if path.begins_with(Catalog.WEAPON_SCENES + "/"):
		names.append("Attack timing")
		if shake_draft != null:
			names.append("Hit feedback")
	elif ResourceLoader.exists(path.get_basename() + "_motion.tres"):
		names.append("Animation")
	if names.size() > 1:
		_tabs.show()
		var group := ButtonGroup.new()
		for index: int in names.size():
			var tab := Button.new()
			tab.text = names[index]
			tab.toggle_mode = true
			tab.button_group = group
			tab.button_pressed = index == _last_tabs.get(path, 0)
			tab.theme_type_variation = &"WorkbenchTab"
			tab.pressed.connect(_select_scene_tab.bind(path, index))
			_tabs.add_child(tab)
	match names[mini(_last_tabs.get(path, 0), names.size() - 1)]:
		"Hit feedback":
			var shake := WeaponHitShake.new()
			shake.name = &"WeaponHitShake"
			shake.configure(scene, path.get_file().get_basename(), shake_draft,
				_mark_modified.bind(shake_path), _hit_shake_state)
			_field_panel.add_child(shake)
		"Attack timing":
			var viewer := Preview.new()
			viewer.offer_scene(scene, "Preview model", false)
			var timing := WeaponTiming.new()
			timing.configure(scene, viewer, func() -> void: _open_animation_player(path))
			_field_panel.add_child(timing)
			_field_panel.add_child(viewer)
		"Animation":
			var open_animation := Button.new()
			open_animation.text = "Open AnimationPlayer"
			open_animation.tooltip_text = "Edit this enemy's clips. Set gameplay windup and recovery in Encounters → Abilities."
			open_animation.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			open_animation.pressed.connect(_open_animation_player.bind(path))
			_field_panel.add_child(open_animation)
		_:
			var viewer := Preview.new()
			viewer.offer_scene(scene, "Model preview", false, true)
			_field_panel.add_child(viewer)


func _select_scene_tab(path: String, index: int) -> void:
	if _last_tabs.get(path, 0) != index:
		_last_tabs[path] = index
		_show_record(_record)
		if index < _tabs.get_child_count():
			_tabs.get_child(index).grab_focus()


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
	var route_fields: Array = _category.get("fields", [])
	if not (&"life_by_level" in route_fields or &"power_by_level" in route_fields):
		form.custom_maximum_size.x = _scaled(420 if _single_record else 560)
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
	return _record.get("path", _category.get("path", "")) if not _record.is_empty() else ""


func _active_save_path() -> String:
	var path := _active_path()
	return Catalog.weapon_hit_shake_source(path) if _record.get("scene", false) else path


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
	var path := _active_save_path()
	var editable := not path.is_empty()
	_reload_button.disabled = not editable
	_save_button.disabled = not editable or not _modified.has(path)
	var name := path.get_file()
	_save_button.tooltip_text = "Save all draft edits to %s. Ctrl+S" % name if editable else "Save scene edits in Godot."
	_reload_button.tooltip_text = "Reload %s from disk." % name if editable else "Reload scene edits from the Godot editor."
	var count := _modified.size()
	if _modified.has(path):
		_set_status("Unsaved changes · " + name, Style.AMBER)
	elif editable:
		_set_status("Source · " + name, Style.MUTED)
	elif _record.get("scene", false):
		_set_status("Scene edits are saved in Godot", Style.MUTED)
	else:
		_set_status("Quick find  Ctrl+K", Style.MUTED)
	_draft_status.text = "%d unsaved %s" % [count, "source" if count == 1 else "sources"] if count else "All drafts saved"
	_draft_status.add_theme_color_override("font_color", Style.AMBER if count else Style.MUTED)
	_draft_status.add_theme_font_size_override("font_size", _scaled(12))
	var sources := PackedStringArray()
	for draft: String in _modified:
		sources.append(draft)
	_draft_status.tooltip_text = "\n".join(sources)
	if not path.is_empty():
		_status.tooltip_text += "\n" + path


func _set_status(message: String, color: Color) -> void:
	_status.text = message
	_status.tooltip_text = message
	_status.add_theme_color_override("font_color", color)


func _save_active_source() -> void:
	_settle_field()
	var path := _active_save_path()
	var resource: Resource = _drafts.get(path)
	if resource == null or not _modified.has(path):
		return
	if FileAccess.get_sha256(path) != _hashes[path]:
		_set_status("Source changed on disk. Draft retained. Review it before reloading.", Style.ERROR)
		return
	var error := Validation.check(path, resource, _load_source(Catalog.GEAR))
	if not error.is_empty():
		_set_status(error, Style.ERROR)
		return
	var result := ResourceSaver.save(resource, path)
	if result != OK:
		_set_status("Could not save the source. %s" % error_string(result), Style.ERROR)
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
	_set_status("Saved " + path.trim_prefix("res://"), Style.ACCENT)


func _request_reload() -> void:
	_settle_field()
	var path := _active_save_path()
	if path.is_empty():
		return
	if _modified.has(path):
		_review.dialog_text = "Discard your unsaved changes to %s and reload it from disk?" % path.get_file()
		_review.popup_centered()
	else:
		_reload_active_source()


func _reload_active_source() -> void:
	var path := _active_save_path()
	var edited := _inspector.get_edited_object()
	_inspector.edit(null)
	if path.is_empty() or ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) == null:
		_inspector.edit(edited)
		_set_status("Could not reload the source.", Style.ERROR)
		return
	_drafts.erase(path)
	_modified.erase(path)
	_hashes.erase(path)
	_refresh_records()
	_set_status("Reloaded " + path.trim_prefix("res://"), Style.ACCENT)


func _heading(message: String, font_size := 14) -> Label:
	var heading := Label.new()
	heading.text = message
	heading.add_theme_font_size_override("font_size", _scaled(font_size))
	return heading


func _scaled(value: int) -> int:
	return roundi(EditorInterface.get_editor_scale() * value)

