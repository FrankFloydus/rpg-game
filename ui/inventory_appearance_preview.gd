@tool
extends Control
## Shows the authored item colors using the actual inventory drawing code.

const Appearance := preload("res://ui/inventory_appearance.gd")
const Art := preload("res://ui/item_art.gd")
const Frame := preload("res://ui/menu_frame.gd")
const PLACED := ["Identified", "Identified hover", "Unidentified", "Unidentified hover"]
const PLACEMENT := ["Valid drop", "Invalid drop", "Swap", "Equipment fit"]

var _appearance: Appearance.Style
var _icon: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size.y = _unit() * 10.25
	_icon = Art.texture_for("ring")
	resized.connect(queue_redraw)


func bind_style(style: Appearance.Style) -> void:
	if _appearance != null:
		_appearance.changed.disconnect(queue_redraw)
	_appearance = style
	if _appearance != null:
		_appearance.changed.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	if _appearance == null:
		return
	var unit := _unit()
	var caption_color := get_theme_color(&"font_color", &"Label")
	var font := get_theme_font(&"font", &"Label")
	draw_rect(Rect2(Vector2.ZERO, size).grow(-0.5), Frame.BASE)
	draw_rect(Rect2(Vector2.ZERO, size).grow(-0.5), Frame.LINE, false, 1.0)
	for index in PLACED.size():
		var box := _sample_rect(index, PLACED.size(), unit * 0.5)
		Appearance.paint_placed(self, box, _appearance, index >= 2, index % 2 == 1)
		if _icon != null:
			var icon_size := box.size.y * 0.69
			draw_texture_rect(_icon, Rect2(box.get_center() - Vector2.ONE * icon_size * 0.5, Vector2.ONE * icon_size), false)
		_draw_caption(PLACED[index], index, PLACED.size(), box.end.y + unit, font, caption_color)
	for index in PLACEMENT.size():
		var box := _sample_rect(index, PLACEMENT.size(), unit * 5.95)
		if index == PLACEMENT.size() - 1:
			Appearance.paint_equipment_fit(self, box, _appearance)
		else:
			Appearance.paint_drop(self, box, _appearance, index != 1)
			if index == 2:
				Appearance.paint_swap(self, Rect2(box.position, Vector2(box.size.x * 0.5, box.size.y)), _appearance)
		_draw_caption(PLACEMENT[index], index, PLACEMENT.size(), box.end.y + unit, font, caption_color)


func _sample_rect(index: int, count: int, y: float) -> Rect2:
	var column := size.x / count
	var extent := Vector2(minf(column * 0.80, _unit() * 3.80), _unit() * 2.55)
	var box := Rect2(Vector2(column * (index + 0.5) - extent.x * 0.5, y), extent)
	draw_rect(box, Frame.WELL)
	draw_rect(box, Frame.LINE, false, 1.0)
	return box.grow(-1.0)


func _draw_caption(caption: String, index: int, count: int, y: float, font: Font, color: Color) -> void:
	var column := size.x / count
	var font_size := roundi(_unit() * 0.86)
	var lines := caption.split(" ", false, 1) if count == PLACED.size() else PackedStringArray([caption])
	for line_index in lines.size():
		var text := lines[line_index]
		var baseline := Vector2(column * index, y + line_index * font_size)
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_CENTER, column, font_size, color)


func _unit() -> float:
	return float(get_theme_default_font_size())
