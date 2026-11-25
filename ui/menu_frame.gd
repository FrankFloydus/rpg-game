extends RefCounted
## Shared flat iron surfaces and neutral text for in-game controls.

const THEME := preload("res://ui/hearth_gear_theme.tres")
const BASE := Color("#0b0c0e")
const WELL := Color("#070809")
const RAISED := Color("#16181c")
const HOVER := Color("#212429")
const SELECTED := Color("#262a31")
const LINE := Color("#59616a")
const BORDER := Color("#737c85")
const FOCUS := Color("#a0a8b1")
const TEXT := Color("#e4e7eb")
const MUTED := Color("#b0b6be")
const DIM := Color("#969da6")


static func panel(horizontal_inset := 25.0, vertical_inset := 22.0) -> StyleBoxFlat:
	return well(horizontal_inset, vertical_inset, BASE, BORDER)


static func well(horizontal_inset := 10.0, vertical_inset := 8.0, fill := WELL,
		edge := LINE) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(1)
	style.content_margin_left = horizontal_inset
	style.content_margin_right = horizontal_inset
	style.content_margin_top = vertical_inset
	style.content_margin_bottom = vertical_inset
	return style
