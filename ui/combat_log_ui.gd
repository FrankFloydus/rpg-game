extends Control

signal back_requested

const MenuFrame := preload("res://ui/menu_frame.gd")
const EVENT_NAMES := {
	&"cast_start": "Cast Started", &"cast_cancel": "Cast Cancelled", &"cast_end": "Cast Ended",
	&"damage": "Damage", &"status": "Status",
}
const EVENT_COLORS := {
	&"cast_start": Color("#e4bf88"), &"cast_cancel": Color("#d79986"), &"cast_end": Color("#b8bda3"),
	&"damage": Color("#f0a188"), &"status": Color("#c8a9d8"),
}
const SOURCE_NAMES := {&"player": "Player", &"enemy": "Enemies", &"world": "Environment"}
const COLUMN_NAMES := ["Time", "Event", "Actor", "Ability", "Target", "Result"]
const ABILITY_COLUMN := 3
const RESULT_COLUMN := 5
const TOOLTIP_GAP := 8.0

var _events: Array[Dictionary] = []
var _kind_filters: Dictionary[StringName, Button] = {}
var _source_filters: Dictionary[StringName, Button] = {}
var _tooltip_item: TreeItem

@onready var _table: Tree = %EventTable
@onready var _time_font := get_theme_font("font", "GearValue")
@onready var _empty: Label = %Empty
@onready var _back: Button = %Back
@onready var _count: Label = %Count
@onready var _tooltip: PanelContainer = %AbilityTooltip
@onready var _tooltip_title: Label = %TooltipTitle
@onready var _tooltip_body: Label = %TooltipBody


func _ready() -> void:
	_back.pressed.connect(back_requested.emit)
	_bind_filters(EVENT_NAMES, _kind_filters)
	_bind_filters(SOURCE_NAMES, _source_filters)
	_configure_columns()
	_table.gui_input.connect(_table_input)
	_table.mouse_exited.connect(_hide_tooltip)
	_table.cell_selected.connect(_show_selected_ability)
	_table.focus_exited.connect(_hide_tooltip)
	_tooltip.minimum_size_changed.connect(_position_tooltip)
	resized.connect(_resize_columns)
	hide()


func present(events: Array[Dictionary]) -> void:
	_events = events.duplicate()
	var has_status := false
	var has_world_events := false
	for entry in _events:
		var kind := StringName(entry.get("kind", ""))
		if kind == &"status":
			has_status = true
		if _source(entry) == &"world":
			has_world_events = true
	_kind_filters[&"status"].visible = has_status
	_source_filters[&"world"].visible = has_world_events
	show()
	_resize_columns()
	_rebuild_table()
	_back.grab_focus()


func close() -> void:
	_hide_tooltip()
	hide()


func is_open() -> bool:
	return visible


func _bind_filters(options: Dictionary, buttons: Dictionary[StringName, Button]) -> void:
	for key: StringName in options:
		var button := get_node("%%Filter_%s" % key) as Button
		button.toggled.connect(_filter_changed)
		buttons[key] = button


func _configure_columns() -> void:
	_table.set_auto_tooltip(false)
	_table.set_h_scroll_enabled(false)
	for column in COLUMN_NAMES.size():
		_table.set_column_title(column, COLUMN_NAMES[column])
		_table.set_column_title_alignment(column, HORIZONTAL_ALIGNMENT_LEFT)
		_table.set_column_clip_content(column, true)
		_table.set_column_expand(column, column >= 2)
	_table.set_column_expand_ratio(ABILITY_COLUMN, 2)
	_table.set_column_expand_ratio(RESULT_COLUMN, 2)


func _resize_columns() -> void:
	if not is_instance_valid(_table):
		return
	var widths := [95, 124, 113, 144, 100, 171] if size.x >= 860.0 else [79, 105, 76, 98, 71, 82]
	for column in widths.size():
		_table.set_column_custom_minimum_width(column, widths[column])
	_position_tooltip()


func _filter_changed(_enabled: bool) -> void:
	_rebuild_table()


func _rebuild_table() -> void:
	_hide_tooltip()
	_table.clear()
	var tree_root := _table.create_item()
	var matching := 0
	for entry in _events:
		var kind := StringName(entry.get("kind", ""))
		if _kind_filters.has(kind) and not _kind_filters[kind].button_pressed:
			continue
		if not _source_filters[_source(entry)].button_pressed:
			continue
		_append_row(tree_root, entry, kind, matching % 2 == 1)
		matching += 1
	_count.text = "%d of %d events" % [matching, _events.size()] if matching != _events.size() else "%d events" % matching
	_empty.text = "No combat events yet" if _events.is_empty() else "No events match these filters"
	_empty.visible = matching == 0


func _append_row(tree_root: TreeItem, entry: Dictionary, kind: StringName, shaded: bool) -> void:
	var row := _table.create_item(tree_root)
	var ability := String(entry.get("ability", ""))
	var description := String(entry.get("description", ""))
	var result := String(entry.get("detail", ""))
	if entry.has("amount"):
		var formatted := ("%.2f" % float(entry["amount"])).rstrip("0").rstrip(".")
		result = formatted if result.is_empty() else "%s  ·  %s" % [formatted, result]
	var cells := [
		_format_time(float(entry.get("time", 0.0))), EVENT_NAMES.get(kind, String(kind).capitalize()),
		String(entry.get("actor", "")), ability, String(entry.get("target", "")), result,
	]
	var actionable := not ability.is_empty() and not description.is_empty()
	var colors := [MenuFrame.MUTED, EVENT_COLORS.get(kind, MenuFrame.MUTED), MenuFrame.TEXT,
		MenuFrame.FOCUS if actionable else MenuFrame.TEXT, MenuFrame.TEXT, MenuFrame.TEXT]
	for column in cells.size():
		row.set_text(column, cells[column])
		row.set_custom_color(column, colors[column])
		row.set_text_overrun_behavior(column, TextServer.OVERRUN_TRIM_ELLIPSIS)
		row.set_selectable(column, column == ABILITY_COLUMN and actionable)
		if shaded:
			row.set_custom_bg_color(column, MenuFrame.BASE)
	row.set_custom_font(0, _time_font)
	row.set_custom_font_size(0, 13)
	row.set_custom_minimum_height(34)
	if not result.is_empty():
		row.set_tooltip_text(RESULT_COLUMN, result)
	if actionable:
		row.set_metadata(ABILITY_COLUMN, description)


func _table_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var item := _table.get_item_at_position(event.position)
		if item and _table.get_column_at_position(event.position) == ABILITY_COLUMN:
			_show_tooltip(item)
		else:
			_hide_tooltip()
	elif event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_hide_tooltip()
	elif event.is_action_pressed("ui_accept"):
		_show_selected_ability()


func _show_selected_ability() -> void:
	if _table.get_selected_column() == ABILITY_COLUMN:
		_show_tooltip(_table.get_selected())


func _show_tooltip(item: TreeItem) -> void:
	if not item or item.get_metadata(ABILITY_COLUMN) == null:
		_hide_tooltip()
		return
	_table.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if _tooltip.visible and item == _tooltip_item:
		return
	_tooltip_item = item
	_tooltip_title.size.x = _tooltip_title.custom_minimum_size.x
	_tooltip_body.size.x = _tooltip_body.custom_minimum_size.x
	_tooltip_title.text = item.get_text(ABILITY_COLUMN)
	_tooltip_body.text = String(item.get_metadata(ABILITY_COLUMN))
	_tooltip.show()
	_position_tooltip()
	_position_tooltip.call_deferred()


func _position_tooltip() -> void:
	if not is_instance_valid(_tooltip) or not _tooltip.visible or not is_instance_valid(_tooltip_item):
		return
	var cell := _table.get_item_area_rect(_tooltip_item, ABILITY_COLUMN)
	var source := get_global_transform().affine_inverse() * (_table.get_global_transform() * cell.position)
	# Wrapped labels revise their minimum after layout. Refit on each minimum change.
	_tooltip.size = _tooltip.get_combined_minimum_size()
	var popup_size := _tooltip.size
	var point := source + Vector2(0, cell.size.y + TOOLTIP_GAP)
	if point.y + popup_size.y + TOOLTIP_GAP > size.y:
		point.y = source.y - popup_size.y - TOOLTIP_GAP
	point.x = clampf(point.x, TOOLTIP_GAP, maxf(TOOLTIP_GAP, size.x - popup_size.x - TOOLTIP_GAP))
	point.y = clampf(point.y, TOOLTIP_GAP, maxf(TOOLTIP_GAP, size.y - popup_size.y - TOOLTIP_GAP))
	_tooltip.position = point


func _hide_tooltip() -> void:
	_tooltip_item = null
	_tooltip.hide()
	_table.mouse_default_cursor_shape = Control.CURSOR_ARROW


static func _source(entry: Dictionary) -> StringName:
	var side := StringName(entry.get("side", &"world"))
	return side if SOURCE_NAMES.has(side) else &"world"


static func _format_time(seconds: float) -> String:
	var millis := maxi(0, roundi(seconds * 1000.0))
	return "%02d:%02d.%03d" % [floori(millis / 60000.0), floori(millis / 1000.0) % 60, millis % 1000]
