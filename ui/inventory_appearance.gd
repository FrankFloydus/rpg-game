@tool
extends RefCounted
## Uses the same presentation for gameplay and the Workbench sample states.

const Style := preload("res://data/inventory_item_style.gd")
const Art := preload("res://ui/item_art.gd")
const Frame := preload("res://ui/menu_frame.gd")
const SOURCE := "res://data/inventory_item_style.tres"
const LIVE: Style = preload(SOURCE)
const SWAP_COLOR := Color("#f5cb50")

static var _fit_well := _make_fit_well()


static func paint_placed(canvas: Control, box: Rect2, style: Style, unidentified: bool, highlighted: bool) -> void:
	var tint := style.placed_fill(unidentified, highlighted)
	# Resolve UI opacity against the slot in display color so HDR and the editor show the same fill.
	var fill := Frame.WELL.lerp(tint, tint.a)
	canvas.draw_rect(box, Color(fill, 1.0))
	if style.grain_opacity > 0.0:
		var leather := Art.leather()
		if leather != null:
			canvas.draw_texture_rect(leather, box, false, Color(0.78, 0.76, 0.77, style.grain_opacity))
	if style.outline_color.a > 0.0:
		canvas.draw_rect(box, style.outline_color, false, 1.0)


static func paint_drop(canvas: Control, box: Rect2, style: Style, accepted: bool) -> void:
	var tint := style.valid_drop_color if accepted else style.invalid_drop_color
	_paint_placement(canvas, box, tint, style.drop_fill_opacity)


static func paint_swap(canvas: Control, box: Rect2, style: Style) -> void:
	_paint_placement(canvas, box, SWAP_COLOR, style.drop_fill_opacity)


static func _paint_placement(canvas: Control, box: Rect2, tint: Color, opacity: float) -> void:
	canvas.draw_rect(box.grow(-1.0), Color(tint, opacity))
	canvas.draw_rect(box.grow(-0.5), Color(tint, 0.85), false, 1.0)


static func paint_equipment_fit(canvas: Control, box: Rect2, style: Style) -> bool:
	var opacity := style.equipment_highlight_opacity
	if opacity <= 0.0:
		return false
	var tint := style.valid_drop_color
	var fill := Color(tint.darkened(0.57), opacity)
	if _fit_well.bg_color != fill:
		_fit_well.bg_color = fill
		_fit_well.border_color = Color(tint, opacity)
	canvas.draw_style_box(_fit_well, box)
	var lip := box.grow(-4.0)
	canvas.draw_line(lip.position, Vector2(lip.end.x, lip.position.y), Color(tint.lightened(0.38), opacity * 0.53), 1.0, true)
	canvas.draw_line(Vector2(lip.position.x, lip.end.y), lip.end, Color(tint.darkened(0.68), opacity * 0.73), 1.0, true)
	return true


static func _make_fit_well() -> StyleBoxFlat:
	var well := StyleBoxFlat.new()
	well.set_border_width_all(1)
	return well
