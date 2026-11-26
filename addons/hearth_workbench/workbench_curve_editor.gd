@tool
extends VBoxContainer

signal curve_committed(curve: Curve)
signal milestones_committed(points: Array[Vector2], operation: StringName, index: int)

const Style := preload("res://addons/hearth_workbench/workbench_style.gd")
const GRAPH_HELP := "Drag to reshape. Double-click empty space or press Insert to add a point. Press Enter to select the next point, use the arrow keys to nudge it, or press Delete to remove it."

var _curve: Curve
var _source: Curve
var _drag_start: Curve
var _drag_side := 0
var _drag_origin := Vector2.ZERO
var _dragged := false
var _selected := -1
var _hovered := -1
var _updating := false
var _read_only := false
var _linear_milestones := false
var _axis_x := "X"
var _axis_y := "Y"

@onready var _graph: Control = %CurveGraph
@onready var _selection: Label = %Selection
@onready var _offset: SpinBox = %Offset
@onready var _value: SpinBox = %Value
@onready var _remove: Button = %RemovePoint
@onready var _incoming: OptionButton = %Incoming
@onready var _outgoing: OptionButton = %Outgoing


func _ready() -> void:
	_graph.draw.connect(_draw_curve)
	_graph.gui_input.connect(_graph_input)
	_graph.resized.connect(_graph.queue_redraw)
	_graph.focus_entered.connect(_graph.queue_redraw)
	_graph.focus_exited.connect(func() -> void:
		_cancel_drag()
		_graph.queue_redraw())
	_graph.mouse_exited.connect(func() -> void:
		_hovered = -1
		_graph.queue_redraw())
	_offset.value_changed.connect(func(value: float) -> void: _edit_coordinate(value, true))
	_value.value_changed.connect(func(value: float) -> void: _edit_coordinate(value, false))
	_remove.pressed.connect(_remove_selected)
	for choice: OptionButton in [_incoming, _outgoing]:
		var side := -1 if choice == _incoming else 1
		var label := "In" if side < 0 else "Out"
		choice.add_item(label + " · Free", Curve.TANGENT_FREE)
		choice.add_item(label + " · Linear", Curve.TANGENT_LINEAR)
		choice.item_selected.connect(func(index: int) -> void: _set_tangent_mode(side, choice.get_item_id(index)))
	_refresh()


func configure(axis_x: String, axis_y: String, help: String) -> void:
	_axis_x = axis_x
	_axis_y = axis_y
	tooltip_text = help
	_refresh()


func graph_control() -> Control:
	return %CurveGraph


func coordinate_controls() -> Array[Control]:
	return [%Offset.get_line_edit(), %Value.get_line_edit(), %RemovePoint, %Incoming, %Outgoing]


func show_curve(source: Curve) -> void:
	if source == _source and _curve != null:
		return
	if _source != null and _source.changed.is_connected(_reload_curve):
		_source.changed.disconnect(_reload_curve)
	_source = source
	if _source != null:
		_source.changed.connect(_reload_curve)
	_linear_milestones = false
	_reload_curve()


func show_milestones(points: Array[Vector2], level_limit: int, selected := -1) -> void:
	_linear_milestones = true
	_curve = Curve.new()
	var maximum_x := float(level_limit)
	var maximum_y := 1.0
	for point: Vector2 in points:
		maximum_x = maxf(maximum_x, point.x)
		maximum_y = maxf(maximum_y, point.y)
	_curve.max_domain = maximum_x
	_curve.min_domain = 1.0
	_curve.max_value = _milestone_upper_bound(maximum_y)
	_curve.min_value = 0.0001
	for point: Vector2 in points:
		_curve.add_point(point, 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	_selected = mini(selected, points.size() - 1)
	_refresh()


func set_read_only(read_only: bool) -> void:
	_read_only = read_only
	_refresh()


func _reload_curve() -> void:
	_curve = _source.duplicate() as Curve if _source != null else null
	_selected = -1
	_drag_start = null
	_refresh()


func _refresh() -> void:
	if not is_node_ready():
		return
	_graph.custom_minimum_size = Vector2(260, 178) * _scale()
	_graph.tooltip_text = tooltip_text if _read_only else GRAPH_HELP
	_graph.accessibility_name = "%s by %s curve" % [_axis_y, _axis_x]
	_graph.accessibility_description = tooltip_text + " " + _graph.tooltip_text
	%Gestures.visible = not _read_only and _curve != null
	_offset.custom_minimum_size.x = 122.0 * _scale()
	_value.custom_minimum_size.x = 122.0 * _scale()
	_offset.tooltip_text = _axis_x + " coordinate of the selected point."
	_value.tooltip_text = _axis_y + " coordinate of the selected point."
	_offset.get_line_edit().accessibility_name = _axis_x
	_value.get_line_edit().accessibility_name = _axis_y
	_offset.get_line_edit().accessibility_description = _offset.tooltip_text
	_value.get_line_edit().accessibility_description = _value.tooltip_text
	_offset.step = 1.0 if _linear_milestones else 0.0001
	_value.allow_greater = _linear_milestones
	var has_point := _curve != null and _selected >= 0 and _selected < _curve.point_count
	var editable := has_point and not _read_only
	%TangentModes.visible = editable and not _linear_milestones
	_offset.visible = has_point
	_value.visible = has_point
	_remove.visible = editable
	_offset.editable = editable
	_value.editable = editable
	_remove.disabled = not editable or (_linear_milestones and _curve.point_count <= 1)
	_incoming.disabled = not editable or not _has_tangent(-1)
	_outgoing.disabled = not editable or not _has_tangent(1)
	_selection.text = "Select a point" if _curve != null and _curve.point_count > 0 else "No points"
	_updating = true
	if has_point:
		_selection.text = "Point %d / %d" % [_selected + 1, _curve.point_count]
		var limits := _offset_limits()
		var point := _curve.get_point_position(_selected)
		_offset.min_value = limits.x
		_offset.max_value = limits.y
		_value.min_value = _curve.min_value
		_value.max_value = _curve.max_value
		_offset.set_value_no_signal(point.x)
		_value.set_value_no_signal(point.y)
		_incoming.select(_incoming.get_item_index(_curve.get_point_left_mode(_selected)))
		_outgoing.select(_outgoing.get_item_index(_curve.get_point_right_mode(_selected)))
	_updating = false
	_graph.queue_redraw()


func _draw_curve() -> void:
	var plot := _plot()
	var scale := _scale()
	var font := get_theme_default_font()
	var font_size := roundi(12.0 * scale)
	_graph.draw_rect(Rect2(Vector2.ZERO, _graph.size), Style.PAGE.darkened(0.12))
	if _curve == null:
		_graph.draw_string(font, Vector2(12, 24) * scale, "No curve assigned", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Style.TEXT)
		return
	_graph.draw_string(font, Vector2(9, 17) * scale, _axis_y, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Style.TEXT)
	for index in 5:
		var fraction := float(index) / 4.0
		var domain := lerpf(_curve.min_domain, _curve.max_domain, fraction)
		if (_linear_milestones or _axis_x == "Enemy level") and index > 0 and index < 4:
			domain = snappedf(domain, 5.0 if _curve.max_domain - _curve.min_domain >= 40.0 else 1.0)
		var x := _to_screen(Vector2(domain, 0.0)).x
		var y := plot.end.y - plot.size.y * fraction
		_graph.draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Style.BORDER)
		_graph.draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Style.BORDER)
		var x_tick := _number(domain)
		var y_tick := _number(lerpf(_curve.min_value, _curve.max_value, fraction))
		_draw_label(font, font_size, x_tick, Vector2(x, plot.end.y + (15.0 * scale)), HORIZONTAL_ALIGNMENT_CENTER)
		_draw_label(font, font_size, y_tick, Vector2(plot.position.x - (8.0 * scale), y + (4.0 * scale)), HORIZONTAL_ALIGNMENT_RIGHT)
	_draw_label(font, font_size, _axis_x, Vector2(plot.get_center().x, _graph.size.y - (5.0 * scale)), HORIZONTAL_ALIGNMENT_CENTER)
	_graph.draw_rect(plot, Style.ACCENT if _graph.has_focus() else Style.BORDER, false, scale)
	if _curve.point_count == 0:
		return
	var samples := PackedVector2Array()
	var sample_count := clampi(ceili(plot.size.x / (2.0 * scale)), 64, 384)
	for index in sample_count + 1:
		var offset := lerpf(_curve.min_domain, _curve.max_domain, float(index) / float(sample_count))
		samples.append(_to_screen(Vector2(offset, _curve.sample(offset))))
	_graph.draw_polyline(samples, Style.ACCENT, 2.0 * scale, true)
	if _selected >= 0:
		var origin := _to_screen(_curve.get_point_position(_selected))
		for side: int in [-1, 1]:
			if _has_tangent(side):
				var handle := _tangent_handle(side)
				_graph.draw_line(origin, handle, Style.MUTED, scale, true)
				_graph.draw_circle(handle, 3.5 * scale, Style.PAGE, true, -1.0, true)
				_graph.draw_circle(handle, 3.5 * scale, Style.MUTED, false, scale, true)
	for index in _curve.point_count:
		var point := _to_screen(_curve.get_point_position(index))
		var active := index == _selected or index == _hovered
		var radius := (5.0 if active else 3.5) * scale
		_graph.draw_circle(point, radius + scale, Style.PAGE, true, -1.0, true)
		_graph.draw_circle(point, radius, Style.TEXT if active else Style.ACCENT, true, -1.0, true)


func _draw_label(font: Font, font_size: int, text: String, anchor: Vector2, alignment: HorizontalAlignment) -> void:
	var label_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var position := anchor
	position.x -= label_width * (0.5 if alignment == HORIZONTAL_ALIGNMENT_CENTER else 1.0)
	_graph.draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Style.TEXT)


func _plot() -> Rect2:
	var start := Vector2(54.0, 29.0) * _scale()
	var padding := Vector2(18.0, 35.0) * _scale()
	return Rect2(start, (_graph.size - start - padding).max(Vector2.ONE))


func _scale() -> float:
	return maxf(1.0, float(get_theme_default_font_size()) / 14.0)


func _to_screen(value: Vector2) -> Vector2:
	var plot := _plot()
	var x := inverse_lerp(_curve.min_domain, _curve.max_domain, value.x)
	var y := inverse_lerp(_curve.min_value, _curve.max_value, value.y)
	return plot.position + Vector2(clampf(x, 0.0, 1.0), 1.0 - clampf(y, 0.0, 1.0)) * plot.size


func _from_screen(value: Vector2) -> Vector2:
	var plot := _plot()
	var local := (value - plot.position) / plot.size
	return Vector2(lerpf(_curve.min_domain, _curve.max_domain, local.x), lerpf(_curve.max_value, _curve.min_value, local.y))


func _number(value: float) -> String:
	return str(snappedf(value, 0.001))


func _graph_input(event: InputEvent) -> void:
	if _curve == null:
		return
	if event is InputEventMouseButton:
		_mouse_button(event)
	elif event is InputEventMouseMotion:
		_mouse_motion(event)
	elif event is InputEventKey and event.pressed and not _read_only:
		_key_pressed(event)


func _mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed:
		if _drag_start != null:
			_drag_start = null
			if _dragged:
				_commit()
			_graph.accept_event()
		return
	_graph.grab_focus()
	var point := _point_at(event.position)
	_drag_side = 0
	if not _read_only and point < 0:
		for side: int in [-1, 1]:
			if _has_tangent(side) and _tangent_handle(side).distance_to(event.position) <= 8.0 * _scale():
				_drag_side = side
				break
	if _drag_side == 0:
		if point < 0 and event.double_click and _plot().has_point(event.position) and not _read_only:
			_insert_point(_from_screen(event.position))
			_graph.accept_event()
			return
		_selected = point
	if _selected >= 0 and not _read_only:
		_drag_start = _curve.duplicate() as Curve
		_drag_origin = event.position
		_dragged = false
	_refresh()
	_graph.accept_event()


func _mouse_motion(event: InputEventMouseMotion) -> void:
	if _drag_start == null or (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		var point := _point_at(event.position)
		if _hovered != point:
			_hovered = point
			_graph.queue_redraw()
		return
	if not _dragged and _drag_origin.distance_to(event.position) < 2.0 * _scale():
		return
	_dragged = true
	if _drag_side == 0:
		var delta := _from_screen(event.position) - _from_screen(_drag_origin)
		_move_selected(_drag_start.get_point_position(_selected) + delta)
	else:
		_drag_tangent(event.position)
	_refresh()
	_graph.accept_event()


func _key_pressed(event: InputEventKey) -> void:
	if _drag_start != null:
		if event.keycode == KEY_ESCAPE:
			_cancel_drag()
			_graph.accept_event()
		return
	if event.keycode == KEY_INSERT and not event.echo:
		_insert_at_gap()
		_graph.accept_event()
		return
	if _selected < 0:
		if event.keycode == KEY_ENTER and _curve.point_count > 0:
			_selected = 0
			_refresh()
			_graph.accept_event()
		return
	if event.keycode in [KEY_DELETE, KEY_BACKSPACE]:
		_remove_selected()
		_graph.accept_event()
		return
	if event.keycode in [KEY_ENTER, KEY_HOME, KEY_END]:
		match event.keycode:
			KEY_HOME:
				_selected = 0
			KEY_END:
				_selected = _curve.point_count - 1
			_:
				_selected = (_selected + 1) % _curve.point_count
		_refresh()
		_graph.accept_event()
		return
	var direction := Vector2.ZERO
	match event.keycode:
		KEY_LEFT:
			direction = Vector2.LEFT
		KEY_RIGHT:
			direction = Vector2.RIGHT
		KEY_UP:
			direction = Vector2(0.0, 1.0)
		KEY_DOWN:
			direction = Vector2(0.0, -1.0)
		_:
			return
	var step := Vector2((_curve.max_domain - _curve.min_domain) * 0.01, (_curve.max_value - _curve.min_value) * 0.01)
	if _linear_milestones:
		step.x = 1.0
	_move_selected(_curve.get_point_position(_selected) + direction * step * (5.0 if event.shift_pressed else 1.0))
	_commit(&"move", _selected)
	_graph.accept_event()


func _cancel_drag() -> void:
	if _drag_start == null:
		return
	_curve = _drag_start
	_drag_start = null
	_refresh()


func _point_at(local: Vector2) -> int:
	var nearest := -1
	var distance := 9.0 * _scale()
	for index in _curve.point_count:
		var next := local.distance_to(_to_screen(_curve.get_point_position(index)))
		if next < distance:
			distance = next
			nearest = index
	return nearest


func _insert_point(point: Vector2) -> void:
	if _linear_milestones:
		point.x = roundf(point.x)
	point.x = clampf(point.x, _curve.min_domain, _curve.max_domain)
	point.y = clampf(point.y, _curve.min_value, _curve.max_value)
	for index in _curve.point_count:
		if absf(point.x - _curve.get_point_position(index).x) < _offset_gap():
			_selected = index
			_refresh()
			return
	var mode := Curve.TANGENT_LINEAR if _linear_milestones else Curve.TANGENT_FREE
	_selected = _curve.add_point(point, 0.0, 0.0, mode, mode)
	_commit(&"insert", _selected)


func _insert_at_gap() -> void:
	var gap_begin := _curve.min_domain
	var gap_end := _curve.max_domain
	var widest := -1.0
	var lower := _curve.min_domain
	for index in _curve.point_count + 1:
		var upper := _curve.get_point_position(index).x if index < _curve.point_count else _curve.max_domain
		if upper - lower > widest:
			gap_begin = lower
			gap_end = upper
			widest = upper - lower
		lower = upper
	var offset := (gap_begin + gap_end) * 0.5
	var value := _curve.sample(offset) if _curve.point_count > 0 else (_curve.min_value + _curve.max_value) * 0.5
	_insert_point(Vector2(offset, value))


func _move_selected(point: Vector2) -> void:
	var limits := _offset_limits()
	var current := _curve.get_point_position(_selected)
	if _linear_milestones and not is_equal_approx(point.x, current.x):
		point.x = roundf(point.x)
	point.x = clampf(point.x, limits.x, limits.y)
	point.y = clampf(point.y, _curve.min_value, _curve.max_value)
	if not is_equal_approx(current.x, point.x):
		_selected = _curve.set_point_offset(_selected, point.x)
	if not is_equal_approx(current.y, point.y):
		_curve.set_point_value(_selected, point.y)


func _offset_limits() -> Vector2:
	var current := _curve.get_point_position(_selected).x
	var minimum := _curve.min_domain
	var maximum := _curve.max_domain
	if _selected > 0:
		minimum = minf(current, _curve.get_point_position(_selected - 1).x + _offset_gap())
	if _selected + 1 < _curve.point_count:
		maximum = maxf(current, _curve.get_point_position(_selected + 1).x - _offset_gap())
	return Vector2(minimum, maximum)


func _offset_gap() -> float:
	return 1.0 if _linear_milestones else (_curve.max_domain - _curve.min_domain) * 0.00001


func _remove_selected() -> void:
	if _selected < 0 or _read_only or (_linear_milestones and _curve.point_count <= 1):
		return
	var removed := _selected
	_curve.remove_point(_selected)
	# Curve already recomputes adjacent linear segments on insert and move. Removal leaves its cached slopes behind.
	if removed > 0 and _curve.get_point_right_mode(removed - 1) == Curve.TANGENT_LINEAR:
		_curve.set_point_right_mode(removed - 1, Curve.TANGENT_LINEAR)
	if removed < _curve.point_count and _curve.get_point_left_mode(removed) == Curve.TANGENT_LINEAR:
		_curve.set_point_left_mode(removed, Curve.TANGENT_LINEAR)
	_selected = mini(_selected, _curve.point_count - 1)
	_commit(&"remove", removed)


func _edit_coordinate(value: float, is_offset: bool) -> void:
	if _updating or _selected < 0 or _read_only or not is_finite(value):
		return
	var point := _curve.get_point_position(_selected)
	if is_offset:
		point.x = value
	else:
		if _linear_milestones:
			value = minf(value, maxf(100000.0, _curve.max_value))
			if value > _curve.max_value:
				_curve.max_value = _milestone_upper_bound(value)
		point.y = value
	_move_selected(point)
	_commit(&"move", _selected)


func _has_tangent(side: int) -> bool:
	return _curve != null and not _linear_milestones and _selected >= 0 and _selected + side >= 0 and _selected + side < _curve.point_count


func _tangent_handle(side: int) -> Vector2:
	var point := _curve.get_point_position(_selected)
	var tangent := _curve.get_point_left_tangent(_selected) if side < 0 else _curve.get_point_right_tangent(_selected)
	var slope_in_pixels := tangent * _plot().size.y * (_curve.max_domain - _curve.min_domain)
	slope_in_pixels /= _plot().size.x * (_curve.max_value - _curve.min_value)
	var direction := Vector2(1.0, -slope_in_pixels).normalized() * float(side)
	return (_to_screen(point) + direction * (29.0 * _scale())).clamp(Vector2(5, 5), _graph.size - Vector2(5, 5))


func _drag_tangent(local: Vector2) -> void:
	var point := _curve.get_point_position(_selected)
	var delta := _from_screen(local) - point
	var gap := maxf(absf(delta.x), (_curve.max_domain - _curve.min_domain) * 0.0025)
	var slope := delta.y / (gap * float(_drag_side))
	if _drag_side < 0:
		_curve.set_point_left_mode(_selected, Curve.TANGENT_FREE)
		_curve.set_point_left_tangent(_selected, slope)
	else:
		_curve.set_point_right_mode(_selected, Curve.TANGENT_FREE)
		_curve.set_point_right_tangent(_selected, slope)


func _set_tangent_mode(side: int, mode: int) -> void:
	if _read_only or not _has_tangent(side):
		return
	if side < 0:
		_curve.set_point_left_mode(_selected, mode)
	else:
		_curve.set_point_right_mode(_selected, mode)
	_commit()


func _commit(operation := &"move", index := -1) -> void:
	_refresh()
	if _linear_milestones:
		var points: Array[Vector2] = []
		for point_index in _curve.point_count:
			points.append(_curve.get_point_position(point_index))
		milestones_committed.emit(points, operation, _selected if index < 0 else index)
		return
	if _source != null and _source.changed.is_connected(_reload_curve):
		_source.changed.disconnect(_reload_curve)
	var next := _curve.duplicate() as Curve
	if _source != null and not _source.resource_scene_unique_id.is_empty():
		next.resource_scene_unique_id = _source.resource_scene_unique_id
	_source = next
	_source.changed.connect(_reload_curve)
	curve_committed.emit(_source)


func _milestone_upper_bound(maximum: float) -> float:
	var with_padding := maximum * 1.2
	var step := maxf(0.25, pow(10.0, floorf(log(with_padding) / log(10.0)) - 1.0))
	return ceilf(with_padding / step) * step
