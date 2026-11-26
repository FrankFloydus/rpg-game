@tool
extends Control
## Top-down scale drawing of the attack with its starting distance marked separately.

const Style := preload("res://addons/hearth_workbench/workbench_style.gd")
const WARNING := Color("#e27966")

var _profile := {}
var _scale := 1.0


func _ready() -> void:
	_scale = EditorInterface.get_editor_scale()
	custom_minimum_size.y = 154.0 * _scale
	mouse_filter = Control.MOUSE_FILTER_PASS
	accessibility_name = "Top-down hit shape"
	accessibility_description = "The caster, hit area and separate AI start range. Edit the fields above and below to update the drawing."
	tooltip_text = accessibility_description


func show_profile(profile: Dictionary) -> void:
	_profile = profile
	visible = str(profile.get("shape", "")) in ["arc", "disc", "ring", "lane", "ray", "projectile"]
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var shape := str(_profile.get("shape", ""))
	var reach := maxf(0.0, float(_profile.get("reach", 2.25)))
	var start := maxf(0.0, float(_profile.get("start", 2.1)))
	var offset := maxf(0.0, float(_profile.get("offset", 0.0)))
	var width := maxf(0.0, float(_profile.get("width", 0.55)))
	var half_angle := deg_to_rad(clampf(float(_profile.get("arc", 45.0)), 0.0, 180.0))
	var near := 0.0
	match shape:
		"disc": near = maxf(0.0, reach - offset)
		"ring": near = reach
		"arc": near = maxf(0.0, -cos(half_angle) * reach)
	var far := maxf(start, reach + (offset if shape == "disc" else 0.0))
	var horizontal := reach if shape in ["arc", "disc", "ring"] else width
	var inset := 12.0 * _scale
	var legend_height := 31.0 * _scale
	var plot := Rect2(Vector2(inset, inset), size - Vector2(inset * 2.0, inset * 2.0 + legend_height))
	if not plot.has_area():
		return
	var scale_factor := minf(plot.size.y / maxf(near + far, 0.1), plot.size.x / maxf(2.0 * horizontal, 0.1))
	var origin := Vector2(plot.get_center().x, plot.get_center().y + (far - near) * scale_factor * 0.5)
	var outline := WARNING if _profile.get("floor_warning", "") == "always" else Style.ACCENT
	draw_rect(Rect2(Vector2.ZERO, size), Style.PAGE)
	draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), Style.BORDER, false, 1.0)
	draw_line(Vector2(origin.x, plot.position.y), Vector2(origin.x, plot.end.y), Style.BORDER, 1.0, true)
	if reach > 0.0:
		_draw_shape(shape, origin, reach * scale_factor, offset * scale_factor, width * scale_factor,
			half_angle, scale_factor, outline)
	var marker := origin + Vector2.UP * start * scale_factor
	draw_line(marker - Vector2(7.0, 0.0) * _scale, marker + Vector2(7.0, 0.0) * _scale, Style.AMBER, 2.0 * _scale, true)
	draw_circle(origin, 3.0 * _scale, Style.TEXT, true, -1.0, true)
	_draw_legend(outline, legend_height)


func _draw_shape(shape: String, origin: Vector2, reach: float, offset: float, width: float,
		half_angle: float, scale_factor: float, outline: Color) -> void:
	var fill := Color(outline, 0.22)
	var stroke := 1.4 * _scale
	match shape:
		"arc":
			var sweep := PackedVector2Array([origin])
			for index in range(33):
				var angle := lerpf(-half_angle, half_angle, float(index) / 32.0)
				sweep.append(origin + Vector2.UP.rotated(angle) * reach)
			if absf((sweep[1] - origin).cross(sweep[8] - origin)) > 0.0001:
				draw_colored_polygon(sweep, fill)
			sweep.append(origin)
			draw_polyline(sweep, outline, stroke, true)
		"disc":
			var center := origin + Vector2.UP * offset
			draw_circle(center, reach, fill, true, -1.0, true)
			draw_arc(center, reach, 0.0, TAU, 48, outline, stroke, true)
		"ring":
			var inner := clampf(float(_profile.get("inner_radius", 1.0)) * scale_factor, 0.0, reach)
			draw_arc(origin, (inner + reach) * 0.5, 0.0, TAU, 48, fill, maxf(reach - inner, 1.0), true)
			if inner > 0.0:
				draw_arc(origin, inner, 0.0, TAU, 48, outline, stroke, true)
			draw_arc(origin, reach, 0.0, TAU, 48, outline, stroke, true)
		"lane":
			var lane := Rect2(origin + Vector2(-width, -reach), Vector2(width * 2.0, reach))
			draw_rect(lane, fill)
			draw_rect(lane, outline, false, stroke, true)
		"ray", "projectile":
			var tip := origin + Vector2.UP * reach
			draw_line(origin, tip, outline, 2.0 * _scale, true)
			draw_polyline(PackedVector2Array([tip + Vector2(-5, 6) * _scale, tip, tip + Vector2(5, 6) * _scale]), outline, stroke, true)


func _draw_legend(outline: Color, height: float) -> void:
	var rule := size.y - height
	draw_line(Vector2(0.0, rule), Vector2(size.x, rule), Style.BORDER, 1.0)
	var font := get_theme_default_font()
	var font_size := maxi(1, roundi(12.0 * _scale))
	var baseline := rule + (height + font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
	var x := 12.0 * _scale
	var range_label := "AI range" if size.x < 250.0 * _scale else "AI start range"
	for entry: Array in [["Caster", Style.TEXT], ["Hit area", outline], [range_label, Style.AMBER]]:
		var marker := Vector2(x + 3.0 * _scale, rule + height * 0.5)
		draw_circle(marker, 3.0 * _scale, entry[1], true, -1.0, true)
		x += 13.0 * _scale
		draw_string(font, Vector2(x, baseline), entry[0], HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, size.x - x), font_size, Style.MUTED)
		x += font.get_string_size(entry[0], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 16.0 * _scale
