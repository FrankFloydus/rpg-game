extends Control

signal card_played(id: String)
signal slot_changed(slot: int, id: String)
signal close_requested

const Catalog = preload("res://data/card_catalog.gd")
const CardTemplate := preload("res://ui/card_face.tscn")
const Face = preload("res://ui/card_face.gd")
const Loadout := preload("res://ui/card_loadout.gd")
## Projection of the modeled thumb tip in the grip's orthographic viewport.
const THUMB_TIP := Vector2(185.0, 131.0)

@export var serif: Font
@onready var _deck_shade: ColorRect = $DeckShade
@onready var _hand_shade: ColorRect = $HandShade
@onready var _hand_view: Control = $Content/Hand
@onready var _fan: Control = $Content/Hand/Fan
@onready var _hand_hint: Label = $Content/Hand/Hint
@onready var _deck_frame: PanelContainer = $Content/DeckFrame
@onready var _deck_title: Label = $Content/DeckFrame/Stack/Header/Heading
@onready var _loadout: Loadout = $Content/DeckFrame/Stack/Loadout
@onready var _left_arm: TextureRect = $LeftArm
@onready var _arm_view: SubViewport = $LeftArm/ArmViewport
@onready var _arm_pose: Node3D = $LeftArm/ArmViewport/Pose
@onready var _left_thumb: TextureRect = $LeftThumb
@onready var _thumb_view: SubViewport = $LeftThumb/ThumbViewport

var _hand: Array[Face] = []
var _rest_hits: Array[Transform2D] = []
var _fan_animation: Tween
var _shade_animation: Tween
var _pointed_card := -1
var _pointer_anchor := Vector2.INF
var _focused_card := -1
var _pressed_card := -1
var _view := ""


func _ready() -> void:
	_left_arm.texture = _arm_view.get_texture()
	_left_thumb.texture = _thumb_view.get_texture()
	_thumb_view.world_3d = _arm_view.find_world_3d()
	var thumb := _arm_pose.find_child("FrontThumb", true, false) as MeshInstance3D
	if thumb != null:
		thumb.layers = 2
	resized.connect(_resize_fan)
	mouse_exited.connect(_point_at_card.bind(-1))
	$Content/DeckFrame/Stack/Header/Close.pressed.connect(close_requested.emit)
	_loadout.serif = serif
	_loadout.slot_changed.connect(slot_changed.emit)
	hide()


func _gui_input(event: InputEvent) -> void:
	if _view != "hand":
		return
	if event is InputEventMouseMotion:
		_point_at_card(_card_under_pointer(event.position), event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var card := _card_under_pointer(event.position)
		if event.pressed:
			_pressed_card = card
			_point_at_card(card, event.position)
		else:
			var played := _pressed_card
			_pressed_card = -1
			if played >= 0 and played == card:
				_hand[played].pressed.emit()
		accept_event()


func show_hand(ids: Array[String]) -> void:
	_clear("hand")
	_hand_shade.self_modulate.a = 0.0
	_shade_animation = create_tween().set_ignore_time_scale(true)
	_shade_animation.tween_property(_hand_shade, "self_modulate:a", 1.0, 0.22)
	for id in ids:
		var face := CardTemplate.instantiate() as Face
		_fan.add_child(face)
		face.present(Catalog.CARDS[id], serif)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.tooltip_text = ""
		face.pressed.connect(func() -> void: card_played.emit(id))
		var index := _hand.size()
		face.focus_entered.connect(_focus_card.bind(index))
		face.focus_exited.connect(_focus_card.bind(-1))
		_hand.append(face)
	_show_grip(true)
	_arrange_fan(true)


func show_loadout(available: Array[String], equipped: Array[String], reset_selection := false,
		read_only_note := "", title_text := "Expedition Deck") -> void:
	if _view != "deck":
		_clear("deck")
	_deck_title.text = title_text
	_loadout.present(available, equipped, reset_selection, read_only_note)


func dismiss() -> void:
	_view = ""
	if _fan_animation != null:
		_fan_animation.kill()
	if _shade_animation != null:
		_shade_animation.kill()
	_show_grip(false)
	hide()


func _clear(mode: String) -> void:
	_view = ""
	if _fan_animation != null:
		_fan_animation.kill()
	if _shade_animation != null:
		_shade_animation.kill()
	_show_grip(false)
	for child in _fan.get_children():
		_fan.remove_child(child)
		child.queue_free()
	_hand.clear()
	_rest_hits.clear()
	_pointed_card = -1
	_pointer_anchor = Vector2.INF
	_focused_card = -1
	_pressed_card = -1
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	_view = mode
	_hand_view.visible = mode == "hand"
	_hand_shade.visible = _hand_view.visible
	_deck_frame.visible = mode == "deck"
	_deck_shade.visible = _deck_frame.visible
	show()


func _resize_fan() -> void:
	if _view == "hand":
		_arrange_fan(false)


func _point_at_card(index: int, point := Vector2.INF) -> void:
	if _pointed_card == index:
		return
	_pointed_card = index
	_pointer_anchor = point
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if index >= 0 else Control.CURSOR_ARROW
	if index >= 0:
		_hand[index].play_hover_sound()
	_arrange_fan(false)


func _focus_card(index: int) -> void:
	if _focused_card == index:
		return
	_focused_card = index
	if index >= 0 and _pointed_card < 0:
		_hand[index].play_hover_sound()
	_arrange_fan(false)


func _card_under_pointer(point: Vector2) -> int:
	# Keep the hover point usable during the lift, then follow the visible cards.
	if _pointed_card >= 0 and point.distance_squared_to(_pointer_anchor) <= 144.0:
		var face := _hand[_pointed_card]
		if _on_card(_rest_hits[_pointed_card].affine_inverse() * point, face.size):
			return _pointed_card
	var front := -1
	var layer := -1
	for index in _hand.size():
		var face := _hand[index]
		var local := face.get_transform().affine_inverse() * point
		if face.z_index >= layer and _on_card(local, face.size):
			front = index
			layer = face.z_index
	return front


func _on_card(point: Vector2, extent: Vector2) -> bool:
	return Rect2(Vector2.ZERO, extent).has_point(point)


func _show_grip(shown: bool) -> void:
	var update := SubViewport.UPDATE_ALWAYS if shown else SubViewport.UPDATE_DISABLED
	_arm_view.render_target_update_mode = update
	_thumb_view.render_target_update_mode = update
	_left_arm.visible = shown
	_left_thumb.visible = shown


func _arrange_fan(entrance: bool) -> void:
	if _view != "hand" or _hand.is_empty():
		return
	if _fan_animation != null:
		_fan_animation.kill()
	_fan_animation = create_tween().set_parallel().set_ignore_time_scale(true)
	_fan_animation.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var factor := clampf(minf(size.y / 770.0, size.x / 650.0), 0.2, 1.12)
	var viewport_size := size
	var half_hand := float(_hand.size() - 1) * 0.5
	var pivot_step := minf(72.0, 90.0 / maxf(1.0, half_hand)) * factor
	var tilt_step := minf(16.0, 33.0 / maxf(1.0, half_hand))
	var selected := _pointed_card if _pointed_card >= 0 else _focused_card
	_rest_hits.resize(_hand.size())
	var hint_offset := -(_hand[0].size.y * 0.73 + 26.0) * factor
	_hand_hint.offset_top = hint_offset
	_hand_hint.offset_bottom = hint_offset + 22.0
	var duration := 0.32 if entrance else 0.14
	for index in _hand.size():
		var face := _hand[index]
		var spread := float(index) - half_hand
		var tilt := deg_to_rad(spread * tilt_step)
		var hinge := Vector2(viewport_size.x * 0.5 + spread * pivot_step,
			viewport_size.y + (face.pivot_offset.y - face.size.y * 0.70 + absf(rad_to_deg(tilt)) * 0.7) * factor)
		var resting := Transform2D(tilt, Vector2.ONE * factor, 0.0, hinge)
		resting.origin -= resting.basis_xform(face.pivot_offset)
		_rest_hits[index] = resting
		var active := index == selected
		var scale_goal := factor * (1.10 if active else 1.0)
		var angle := tilt
		if active:
			var half_width := face.size.x * scale_goal * 0.5
			var side_step := sin(tilt) * face.pivot_offset.y * factor * 0.73
			hinge.x = clampf(hinge.x + side_step, half_width, viewport_size.x - half_width)
			hinge.y = viewport_size.y - (face.size.y - face.pivot_offset.y) * scale_goal - 2.0
			angle = 0.0
		face.z_index = 30 if active else _hand.size() + 1 - int(absf(spread) * 2.0)
		if entrance:
			face.position = Vector2(hinge.x,
				viewport_size.y + face.pivot_offset.y * factor + 28.0) - face.pivot_offset
			face.rotation = tilt * 0.5
			face.scale = Vector2.ONE * factor
		_fan_animation.tween_property(face, "position", hinge - face.pivot_offset, duration)
		_fan_animation.tween_property(face, "rotation", angle, duration)
		_fan_animation.tween_property(face, "scale", Vector2.ONE * scale_goal, duration)
	_arrange_grip(factor, selected, duration, entrance)


func _arrange_grip(factor: float, selected: int, duration: float, entrance: bool) -> void:
	var held := _hand.size() - 1
	if held > 0 and held == selected:
		held -= 1
	var stock := _rest_hits[held]
	var top := stock * Vector2(_hand[held].size.x * 0.92, 0.0)
	var grip_height := size.y - 73.0 * factor
	var tip_target := top + stock.y * ((grip_height - top.y) / stock.y.y)
	var grip_scale := factor * 1.56
	var end := tip_target - THUMB_TIP * grip_scale
	for surface: TextureRect in [_left_arm, _left_thumb]:
		surface.size = Vector2(_arm_view.size) * grip_scale
		if entrance:
			surface.position = end + Vector2(34.0, 135.0) * factor
		_fan_animation.tween_property(surface, "position", end, duration)
	if entrance:
		_arm_pose.rotation.z = deg_to_rad(14.0)
	_fan_animation.tween_property(_arm_pose, "rotation:z", 0.0, duration)
