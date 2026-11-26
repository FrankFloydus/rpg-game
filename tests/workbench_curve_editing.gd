extends SceneTree
## Exercises the Workbench graph's insertion/removal around live Godot Curve tangents.

const Graph := preload("res://addons/hearth_workbench/workbench_curve_editor.tscn")
const CurveEditor := preload("res://addons/hearth_workbench/workbench_curve_editor.gd")
const INSERTED_POINT := Vector2(8.0, 16.0)

var _editor: CurveEditor
var _revisions: Array[Curve] = []
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_editor = Graph.instantiate() as CurveEditor
	_editor.size = Vector2(480, 360)
	_editor.curve_committed.connect(func(curve: Curve) -> void: _revisions.append(curve))
	root.add_child(_editor)
	await process_frame
	_check_insert_remove(false)
	_check_insert_remove(true)
	_check_endpoints()
	_editor.free()
	print("workbench_curve_editing: %d/%d checks passed" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)


func _fixture(free_outgoing := false) -> Curve:
	var curve := Curve.new()
	curve.max_domain = 10.0
	curve.max_value = 20.0
	for point in [Vector2(0, 1), Vector2(5, 5), Vector2(10, 9)]:
		curve.add_point(point, 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	if free_outgoing:
		curve.set_point_right_mode(1, Curve.TANGENT_FREE)
		curve.set_point_right_tangent(1, 0.23)
	return curve


func _check_insert_remove(free_outgoing: bool) -> void:
	var baseline := _fixture(free_outgoing)
	_editor.show_curve(baseline)
	_revisions.clear()
	_click(INSERTED_POINT, true)
	if not _check(_revisions.size() == 1 and _revisions[-1].point_count == 4, "Insert adds a key through the graph"):
		return
	_check(not is_equal_approx(_revisions[-1].sample(7.5), baseline.sample(7.5)), "Inserted key changes the sampled segment")
	_delete()
	if not _check(_revisions.size() == 2 and _revisions[-1].point_count == 3, "Delete removes the inserted key"):
		return
	var restored := _revisions[-1]
	_check(baseline.get_point_right_mode(1) == restored.get_point_right_mode(1)
		and is_equal_approx(baseline.get_point_right_tangent(1), restored.get_point_right_tangent(1)),
		"Predecessor keeps its authored free slope or recomputed linear slope")
	_check(is_equal_approx(baseline.get_point_left_tangent(2), restored.get_point_left_tangent(2)),
		"Successor relinks its incoming linear tangent")
	_check(is_equal_approx(baseline.sample(7.5), restored.sample(7.5)), "Removing an inserted key restores the sampled shape")
	if not free_outgoing:
		_check_saved_shape(restored, baseline)


func _check_endpoints() -> void:
	var baseline := _fixture()
	_editor.show_curve(baseline)
	_revisions.clear()
	_click(baseline.get_point_position(0))
	_delete()
	if not _check(_revisions.size() == 1 and _revisions[-1].point_count == 2, "Deletes the first point"):
		return
	_check(is_equal_approx(baseline.sample(7.5), _revisions[-1].sample(7.5)), "Deleting first point preserves the surviving segment")
	_click(baseline.get_point_position(2))
	_delete()
	_check(_revisions.size() == 2 and _revisions[-1].point_count == 1
		and is_equal_approx(_revisions[-1].sample(7.5), 5.0), "Deletes the final endpoint with one valid remaining point")


func _check_saved_shape(curve: Curve, baseline: Curve) -> void:
	var directory := OS.get_user_data_dir().path_join("workbench_curve_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	if not _check(DirAccess.make_dir_absolute(directory) == OK, "Creates isolated curve fixture directory"):
		return
	var path := directory.path_join("curve.tres")
	if _check(ResourceSaver.save(curve, path) == OK, "Saves the edited Curve"):
		var loaded := ResourceLoader.load(path, "Curve", ResourceLoader.CACHE_MODE_IGNORE) as Curve
		_check(loaded != null and is_equal_approx(baseline.sample(7.5), loaded.sample(7.5)), "Reload preserves the restored sample")
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(directory)


func _click(point: Vector2, double_click := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = _editor._to_screen(point)
	event.pressed = true
	event.double_click = double_click
	_editor.graph_control().gui_input.emit(event)
	event = event.duplicate()
	event.pressed = false
	_editor.graph_control().gui_input.emit(event)


func _delete() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_DELETE
	event.pressed = true
	_editor.graph_control().gui_input.emit(event)


func _check(condition: bool, detail: String) -> bool:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(detail)
	return condition
