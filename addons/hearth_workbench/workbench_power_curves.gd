@tool
extends VBoxContainer

signal milestones_committed(points: Array[Vector3])

const CurveEditor := preload("res://addons/hearth_workbench/workbench_curve_editor.gd")

var _points: Array[Vector3] = []
var _level_limit := 100


func configure(points: Array[Vector3], level_limit: int) -> void:
	_points = points.duplicate()
	_level_limit = level_limit
	%AttackCurve.configure("Item level", "Attack multiplier", "Scales attack stats at this item level. The multiplier interpolates between milestones.")
	%DefenseCurve.configure("Item level", "Defense multiplier", "Scales defense stats at this item level. The multiplier interpolates between milestones.")
	%AttackCurve.show_milestones(_series(true), _level_limit)
	%DefenseCurve.show_milestones(_series(false), _level_limit)
	%AttackCurve.milestones_committed.connect(_edit.bind(true))
	%DefenseCurve.milestones_committed.connect(_edit.bind(false))


func _edit(points: Array[Vector2], operation: StringName, index: int, attack: bool) -> void:
	if operation == &"remove":
		_points.remove_at(index)
	else:
		var selected := points[index]
		if operation == &"insert":
			var peer := _sample_peer(selected.x, attack)
			_points.insert(index, Vector3(selected.x, selected.y, peer) if attack else Vector3(selected.x, peer, selected.y))
		else:
			var existing := _points[index]
			_points[index] = Vector3(selected.x, selected.y, existing.z) if attack else Vector3(selected.x, existing.y, selected.y)
	var peer_graph: CurveEditor = %DefenseCurve if attack else %AttackCurve
	peer_graph.show_milestones(_series(not attack), _level_limit, index)
	milestones_committed.emit(_points.duplicate())


func _series(attack: bool) -> Array[Vector2]:
	var series: Array[Vector2] = []
	for point in _points:
		series.append(Vector2(point.x, point.y if attack else point.z))
	return series


func _sample_peer(level: float, attack: bool) -> float:
	if _points.is_empty():
		return 1.0
	# The unseen series follows the same interpolation and end clamping as item power at runtime.
	var peer: Array[Vector2] = _series(not attack)
	var lower := peer[0]
	if level <= lower.x:
		return lower.y
	for index in range(1, peer.size()):
		var upper := peer[index]
		if level <= upper.x:
			return lerpf(lower.y, upper.y, inverse_lerp(lower.x, upper.x, level))
		lower = upper
	return lower.y
