@tool
extends RefCounted

const PAGE := Color("#171c21")
const SIDEBAR := Color("#1c2329")
const SURFACE := Color("#222c34")
const BORDER := Color("#34424c")
const TEXT := Color("#e9efee")
const MUTED := Color("#a6b3bd")
const ACCENT := Color("#8ed4bb")
const AMBER := Color("#e8bd80")
const ERROR := Color("#ffb0a9")


static func build(source: Theme, scale: float) -> Theme:
	var result := Theme.new()
	result.merge_with(source)
	result.default_base_scale = source.default_base_scale
	result.default_font = source.default_font
	result.default_font_size = roundi(14 * scale)
	for type: String in ["Label", "Button", "LineEdit", "Tree"]:
		result.set_color("font_color", type, TEXT)
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	result.set_color("guide_color", "Tree", Color.TRANSPARENT)
	result.set_color("drop_position_color", "Tree", ACCENT)
	result.set_color("font_selected_color", "Tree", TEXT)
	result.set_color("font_hovered_color", "Tree", TEXT)
	result.set_font_size("font_size", "Tree", roundi(13 * scale))
	result.set_constant("v_separation", "Tree", roundi(3 * scale))
	result.set_constant("inner_item_margin_top", "Tree", roundi(1 * scale))
	result.set_constant("inner_item_margin_bottom", "Tree", roundi(1 * scale))
	result.set_constant("inner_item_margin_left", "Tree", roundi(4 * scale))
	result.set_constant("inner_item_margin_right", "Tree", roundi(4 * scale))
	result.set_constant("item_margin", "Tree", roundi(10 * scale))
	result.set_constant("draw_guides", "Tree", 0)
	result.set_constant("draw_relationship_lines", "Tree", 0)
	result.set_constant("scroll_max_sticky_items", "Tree", 0)
	result.set_stylebox("panel", "Tree", panel(Color.TRANSPARENT))
	result.set_stylebox("selected", "Tree", panel(Color("#354d49"), Color.TRANSPARENT, scale))
	result.set_stylebox("selected_focus", "Tree", panel(Color("#354d49"), Color("#577a6c"), scale))
	result.set_stylebox("hovered", "Tree", panel(SURFACE, Color.TRANSPARENT, scale))
	result.set_stylebox("focus", "Tree", panel(Color.TRANSPARENT, BORDER, scale))
	result.set_stylebox("normal", "LineEdit", panel(PAGE, BORDER, scale, 8))
	result.set_stylebox("focus", "LineEdit", panel(Color.TRANSPARENT, ACCENT, scale))
	result.set_stylebox("separator", "HSeparator", panel(BORDER))
	result.set_stylebox("separator", "VSeparator", panel(BORDER))
	result.set_constant("separation", "HSeparator", 1)
	result.set_constant("separation", "VSeparator", 1)
	result.set_stylebox("panel", "PanelContainer", panel(PAGE))
	result.set_stylebox("panel", "PopupPanel", panel(SIDEBAR, BORDER, scale))
	for type: String in ["Button", "OptionButton", "WorkbenchTab", "WorkbenchPrimary"]:
		if type.begins_with("Workbench"):
			result.set_type_variation(type, "Button")
		var primary := type == "WorkbenchPrimary"
		var tab := type == "WorkbenchTab"
		result.set_stylebox("normal", type, panel(Color("#32554e") if primary else PAGE if tab else SURFACE, Color.TRANSPARENT if tab else BORDER, scale, 10))
		result.set_stylebox("hover", type, panel(Color("#3a6257") if primary else Color("#2d3a43"), BORDER, scale, 10))
		result.set_stylebox("pressed", type, panel(Color("#354d49"), Color("#577a6c"), scale, 10))
		result.set_stylebox("disabled", type, panel(Color("#242d34"), Color.TRANSPARENT, scale, 10))
		result.set_stylebox("focus", type, panel(Color.TRANSPARENT, ACCENT, scale))
		result.set_color("font_color", type, TEXT)
		result.set_color("font_pressed_color", type, ACCENT)
		result.set_color("font_hover_color", type, TEXT)
		result.set_color("font_disabled_color", type, Color("#83919b"))
	return result


static func panel(fill: Color, edge := Color.TRANSPARENT, scale := 0.0, inset := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	if edge.a > 0.0:
		style.set_border_width_all(1)
		style.border_color = edge
	style.set_corner_radius_all(roundi(5 * scale))
	style.content_margin_left = roundi(inset * scale)
	style.content_margin_right = roundi(inset * scale)
	style.content_margin_top = roundi((inset / 2.0) * scale)
	style.content_margin_bottom = style.content_margin_top
	return style


static func inset(control: MarginContainer, horizontal: int, vertical: int) -> void:
	control.add_theme_constant_override("margin_left", horizontal)
	control.add_theme_constant_override("margin_right", horizontal)
	control.add_theme_constant_override("margin_top", vertical)
	control.add_theme_constant_override("margin_bottom", vertical)
