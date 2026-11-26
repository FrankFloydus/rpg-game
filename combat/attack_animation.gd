@tool
extends RefCounted
## Timing read directly from an editable Godot Animation resource.

const TRACE_START := &"Trace Start"
const TRACE_END := &"Trace End"
const TERRAIN_START := &"Terrain Start"
const INPUT_BUFFER := &"Input Buffer"
const COMBO_ENTRY := &"Combo Entry"
const COMBO_EXIT := &"Combo Exit"
const IMPACT := &"Impact"

var length: float
var trace_start: float
var trace_end: float
var terrain_start: float
var input_buffer: float
var combo_entry: float
var combo_exit: float
var impact: float


static func read(animation: Animation) -> RefCounted:
	if animation == null or not animation.has_marker(TRACE_START) \
			or not animation.has_marker(TRACE_END) or not animation.has_marker(INPUT_BUFFER):
		return null
	var result = new()
	result.length = animation.length
	result.trace_start = animation.get_marker_time(TRACE_START)
	result.trace_end = animation.get_marker_time(TRACE_END)
	result.input_buffer = clampf(animation.get_marker_time(INPUT_BUFFER), 0.0, result.length)
	if result.trace_start < 0.0 or result.trace_end > result.length or result.trace_end < result.trace_start:
		return null
	if animation.has_marker(COMBO_ENTRY):
		result.combo_entry = clampf(animation.get_marker_time(COMBO_ENTRY), 0.0, result.trace_start * 0.85)
	result.combo_exit = clampf(animation.get_marker_time(COMBO_EXIT), result.trace_end, result.length) \
		if animation.has_marker(COMBO_EXIT) else result.length
	result.impact = (result.trace_start + result.trace_end) * 0.5
	if animation.has_marker(IMPACT):
		result.impact = clampf(animation.get_marker_time(IMPACT), result.trace_start, result.trace_end)
	result.terrain_start = result.trace_start
	if animation.has_marker(TERRAIN_START):
		result.terrain_start = clampf(animation.get_marker_time(TERRAIN_START), result.trace_start, result.impact)
	return result


func at_elapsed(elapsed: float, duration: float, release_marker := 0.0, time_to_impact := 0.0) -> float:
	if time_to_impact <= 0.0 or time_to_impact >= duration:
		return length * clampf(elapsed / duration, 0.0, 1.0)
	if elapsed < time_to_impact:
		return lerpf(release_marker, impact, clampf(elapsed / time_to_impact, 0.0, 1.0))
	return lerpf(impact, length, clampf((elapsed - time_to_impact) / (duration - time_to_impact), 0.0, 1.0))
