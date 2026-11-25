@tool
extends Button

const MenuFrame := preload("res://ui/menu_frame.gd")

@export var portrait: Texture2D:
	set(value):
		portrait = value
		queue_redraw()

@export var display_only := false:
	set(value):
		display_only = value
		_update_caption_visibility()
		queue_redraw()


func _ready() -> void:
	_update_caption_visibility()
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)


func _update_caption_visibility() -> void:
	var caption := get_node_or_null("Caption") as Label
	if caption:
		caption.visible = not display_only

func set_caption(label: Label) -> void:
	add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	label.offset_left = 7
	label.offset_right = -7
	label.offset_top = -37
	label.offset_bottom = -5
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

func _draw() -> void:
	var side := minf(size.x - 16.0, size.y - (16.0 if display_only else 44.0))
	if side <= 0.0:
		return
	var art := Rect2(Vector2((size.x - side)*0.5, 8.0), Vector2.ONE*side)
	draw_rect(art, MenuFrame.WELL)
	if portrait != null:
		draw_texture_rect(portrait, art, false)
	else:
		_draw_shrouded_profile(art)
	var highlighted := not disabled and not display_only and (is_hovered() or has_focus())
	var edge := MenuFrame.FOCUS if highlighted else MenuFrame.LINE
	draw_rect(art, edge, false, 1.0)
	if not display_only:
		draw_line(Vector2(12, size.y - 37), Vector2(size.x - 12, size.y - 37), edge.darkened(0.35), 1.0)

func _draw_shrouded_profile(art: Rect2) -> void:
	var center := art.get_center()
	var unit := art.size.x
	var surround := Color("#292c31")
	draw_arc(center, unit*0.338, 0.0, TAU, 60, surround, 1.1, true)
	draw_arc(center, unit*0.366, -PI*0.06, PI*1.06, 36, Color("#343840"), 1.0, true)
	var silhouette := PackedVector2Array()
	for point: Vector2 in [Vector2(-0.35, 0.27), Vector2(-0.27, 0.14),
		Vector2(-0.15, 0.08), Vector2(-0.19, -0.07), Vector2(-0.12, -0.22),
		Vector2(-0.045, -0.29), Vector2(0.050, -0.25), Vector2(0.15, -0.18),
		Vector2(0.20, -0.031), Vector2(0.13, 0.09), Vector2(0.26, 0.14),
		Vector2(0.36, 0.27)]:
		silhouette.append(center + point*unit)
	draw_colored_polygon(silhouette, Color("#202329"))
	silhouette.append(silhouette[0])
	draw_polyline(silhouette, Color("#343840"), 1.0, true)
	var mask := PackedVector2Array([Vector2(-0.091, -0.054), Vector2(-0.035, -0.154),
		Vector2(0.052, -0.162), Vector2(0.115, -0.09), Vector2(0.059, 0.055),
		Vector2(-0.035, 0.025)])
	for index in mask.size():
		mask[index] = center + mask[index]*unit
	draw_colored_polygon(mask, Color("#111317"))
