@tool
extends Control
## Top-down scale drawing of the attack with its starting distance marked separately.

var _profile := {}


func _ready() -> void:
	custom_minimum_size.y = 134.0 * EditorInterface.get_editor_scale()
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_profile(profile: Dictionary) -> void:
	_profile = profile
	visible = str(profile.get("shape", "")) in ["arc", "disc", "ring", "lane", "ray", "projectile"]
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var shape := str(_profile.get("shape", ""))
	var reach := float(_profile.get("reach", 2.25))
	var start := float(_profile.get("start", 2.1))
	var offset := float(_profile.get("offset", 0.0))
	var width := float(_profile.get("width", 0.55))
	var radial := shape in ["disc", "ring"]
	var half_angle := deg_to_rad(float(_profile.get("arc", 45.0)))
	var near := maxf(0.0, reach - offset) if radial else (
		maxf(0.0, -cos(half_angle) * reach) if shape == "arc" else 0.0)
	var far := maxf(start, reach + (offset if shape == "disc" else 0.0))
	var horizontal := reach if shape in ["arc", "disc", "ring"] else width
	var scale_factor := minf((size.y - 24.0) / maxf(near + far, 0.1),
		(size.x - 40.0) / maxf(2.0 * horizontal, 0.1))
	var origin := Vector2(size.x * 0.5, size.y - 12.0 - near * scale_factor)
	var ahead := Vector2.UP
	var red := Color("#e27966") if _profile.get("floor_warning", "") == "always" else Color("#9aaed8")
	var fill := Color(red, 0.22)
	draw_rect(Rect2(Vector2.ZERO, size), get_theme_color("dark_color_2", "Editor"))
	draw_line(Vector2(origin.x, 4.0), Vector2(origin.x, size.y - 4.0), Color("#44474e"), 1.0, true)
	match shape:
		"arc":
			var sweep := PackedVector2Array([origin])
			for index in range(33):
				var angle := lerpf(-half_angle, half_angle, float(index) / 32.0)
				sweep.append(origin + ahead.rotated(angle) * reach * scale_factor)
			sweep.append(origin)
			if reaches_area(sweep) and reach > 0.0:
				draw_colored_polygon(sweep, fill)
			draw_polyline(sweep, red, 1.4, true)
		"disc":
			var center := origin + ahead * offset * scale_factor
			draw_circle(center, reach * scale_factor, fill, true, -1.0, true)
			draw_arc(center, reach * scale_factor, 0.0, TAU, 48, red, 1.4, true)
		"ring":
			var inner := minf(float(_profile.get("inner_radius", 1.0)), reach)
			draw_arc(origin, (inner + reach) * 0.5 * scale_factor, 0.0, TAU, 48, fill,
				maxf((reach - inner) * scale_factor, 1.0), true)
			draw_arc(origin, inner * scale_factor, 0.0, TAU, 48, red, 1.4, true)
			draw_arc(origin, reach * scale_factor, 0.0, TAU, 48, red, 1.4, true)
		"lane":
			var lane := Rect2(origin + Vector2(-width, -reach) * scale_factor, Vector2(width * 2.0, reach) * scale_factor)
			draw_rect(lane, fill)
			draw_rect(lane, red, false, 1.4, true)
		"ray", "projectile":
			var tip := origin + ahead * reach * scale_factor
			draw_line(origin, tip, red, 2.0, true)
			draw_polyline(PackedVector2Array([tip + Vector2(-5, 6), tip, tip + Vector2(5, 6)]), red, 1.4, true)
	draw_circle(origin, 3.0, Color("#edf0f6"), true, -1.0, true)
	var marker := origin + ahead * start * scale_factor
	draw_line(marker - Vector2(6.0, 0.0), marker + Vector2(6.0, 0.0), Color("#e9c47d"), 2.0, true)
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size() - 2
	draw_string(font, Vector2(9.0, 16.0), "Caster", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#edf0f6"))
	draw_string(font, Vector2(9.0, 31.0), "AI starts here", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#e9c47d"))


func reaches_area(points: PackedVector2Array) -> bool:
	return points.size() > 3 and absf((points[1] - points[0]).cross(points[8] - points[0])) > 0.0001
