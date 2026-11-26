@tool
extends VBoxContainer
## Edits one weapon's impact profiles and samples its camera feedback from the draft.

const HitShake := preload("res://data/weapon_hit_shake.gd")
const Preview := preload("res://addons/hearth_workbench/workbench_hit_shake_preview.gd")
const Fields := preload("res://addons/hearth_workbench/workbench_fields.gd")
const Layout := preload("res://addons/hearth_workbench/workbench_hit_shake_layout.tscn")
const SURFACE_LABELS := {
	&"body": "Flesh",
	&"breakable": "Breakable",
	&"stone": "Stone",
	&"metal": "Metal",
	&"wood": "Wood",
	&"armor": "Armor",
	&"guard": "Guard",
	&"mass": "Cleave limit",
}
const MINT := Color("#8ed4bb")
const SLATE := Color("#aeb8c5")
const AMBER := Color("#e0b480")

var _profiles: Resource
var _weapon_type: String
var _state: Dictionary
var _dirty: Callable
var _surface: OptionButton
var _weight: OptionButton
var _direction: OptionButton
var _response: OptionButton
var _response_group: Control
var _animations: Dictionary[StringName, String] = {}
var _editors: Array[SpinBox]
var _preview: Preview
var _reset: Button
var _source: Label
var _playback_mode: Label


func configure(scene: PackedScene, weapon_type: String, profiles: Resource, on_edit: Callable,
		state: Dictionary) -> void:
	_profiles = profiles
	_weapon_type = weapon_type
	_state = state
	_dirty = on_edit
	_animations = Preview.attack_choices(scene)

	var layout := Layout.instantiate()
	add_child(layout)

	_surface = layout.get_node("%HitMaterial")
	Fields.describe_control(_surface, "Contact", "Choose the struck material or the contact that stops the swing.")
	var initial_surface := 0
	for surface: StringName in HitShake.surface_ids(weapon_type):
		var index := _surface.item_count
		_surface.add_item(SURFACE_LABELS.get(surface, String(surface).capitalize()))
		_surface.set_item_metadata(index, surface)
		if surface == state.get("surface", &"body"):
			initial_surface = index
	_surface.select(initial_surface)
	_surface.item_selected.connect(_select_profile)

	_weight = layout.get_node("%HitWeight")
	_weight.add_item("Light")
	_weight.add_item("Charged")
	_weight.select(1 if state.get("charged", false) else 0)
	Fields.describe_control(_weight, "Attack", "Choose the light or charged attack set.")
	_weight.item_selected.connect(func(index: int) -> void:
		_update_direction()
		_select_profile(index))

	_direction = layout.get_node("%HitDirection")
	Fields.describe_control(_direction, "Direction", "Choose the swing whose contact response you want to edit and preview.")
	_direction.item_selected.connect(func(index: int) -> void:
		_state[_direction_state_key()] = _direction.get_item_metadata(index)
		_select_profile(0))
	_response_group = layout.get_node("%ContactResponse")
	_response = layout.get_node("%HitResponse")
	_response.add_item("Hard stop", Preview.Response.STOP)
	_response.add_item("Carry through", Preview.Response.THROUGH)
	Fields.describe_control(_response, "Response", "Hard stop shows a rebound. Carry through plays the surface feedback while the swing continues. Both use the selected material's tuning.")
	_response.item_selected.connect(func(index: int) -> void:
		_state[_response_state_key(_surface_id())] = index
		_select_profile(0))

	_preview = Preview.new()
	_preview.name = &"HitShakePreview"
	_preview.configure(scene, weapon_type, profiles)

	_bind_number(layout.get_node("%HitPitch"), "Pitch", "Vertical kick strength in degrees. The swing and recoil phase set its direction.")
	_bind_number(layout.get_node("%HitYaw"), "Yaw", "Horizontal kick strength in degrees. The swing and recoil phase set its direction.")
	_bind_number(layout.get_node("%HitRoll"), "Roll", "Bank strength in degrees. On mace hits it can reverse independently of pitch and yaw.")
	_bind_number(layout.get_node("%HitDuration"), "Duration", "Time in seconds for the camera kick to play and settle.")

	var loop: CheckButton = layout.get_node("%LoopHit")
	loop.tooltip_text = "Repeat the full swing and its selected contact."
	loop.button_pressed = bool(state.get("looping", true))
	loop.toggled.connect(func(enabled: bool) -> void:
		state["looping"] = enabled
		_preview.set_looping(enabled))
	_preview.set_looping(loop.button_pressed)
	var replay: Button = layout.get_node("%ReplayHit")
	replay.tooltip_text = "Replay the selected contact immediately."
	replay.pressed.connect(_preview.replay)
	_reset = layout.get_node("%ResetHitProfile")
	_reset.pressed.connect(_reset_profile)
	_source = layout.get_node("%HitProfileSource")
	_playback_mode = layout.get_node("%HitPlaybackMode")
	var preview_frame: MarginContainer = layout.get_node("%Preview")
	preview_frame.add_child(_preview)
	preview_frame.move_child(_preview, 0)
	_update_direction()
	_select_profile(0)


func _bind_number(input: SpinBox, title: String, help: String) -> void:
	input.value_changed.connect(_write_profile.bind(_editors.size()))
	Fields.describe_control(input, title, help)
	Fields.describe_control(input.get_line_edit(), title, help)
	Fields.style_line_edit(input.get_line_edit())
	_editors.append(input)


func _surface_id() -> StringName:
	return _surface.get_item_metadata(_surface.selected)


func _swing_id() -> StringName:
	return &"" if _direction.selected < 0 else StringName(_direction.get_item_metadata(_direction.selected))


func _select_profile(_index: int) -> void:
	var surface := _surface_id()
	var charged := _weight.selected == 1
	_state["surface"] = surface
	_state["charged"] = charged
	var clip := _swing_id()
	var profile: Vector4 = _profiles.profile(_weapon_type, surface, charged, clip)
	for index in _editors.size():
		_editors[index].set_value_no_signal(profile[index])
	_refresh_preview(surface, charged, clip)


func _write_profile(value: float, axis: int) -> void:
	var surface := _surface_id()
	var charged := _weight.selected == 1
	var clip := _swing_id()
	var profile: Vector4 = _profiles.profile(_weapon_type, surface, charged, clip)
	if is_equal_approx(profile[axis], value):
		return
	profile[axis] = value
	_profiles.set_profile(_weapon_type, surface, charged, profile, clip)
	_dirty.call()
	_refresh_preview(surface, charged, clip)


func _reset_profile() -> void:
	_profiles.clear_profile(_weapon_type, _surface_id(), _weight.selected == 1, _swing_id())
	_dirty.call()
	_select_profile(0)


func _refresh_preview(surface: StringName, charged: bool, clip: StringName) -> void:
	var custom: bool = _profiles.has_profile_override(_weapon_type, surface, charged, clip)
	var shared: bool = _profiles.has_profile_override(_weapon_type, surface, charged)
	_reset.disabled = not custom
	_reset.text = "Reset profile" if clip.is_empty() else "Reset direction"
	_reset.tooltip_text = "Use the built-in values for this contact." if clip.is_empty() else \
		"Remove this direction's edit and inherit the shared or built-in values."
	if custom:
		_source.text = "Custom values" if clip.is_empty() else "Custom direction"
		_source.tooltip_text = "This selection has its own saved or draft override."
		_source.add_theme_color_override("font_color", MINT)
	else:
		_source.text = "Shared fallback" if shared else "Built-in fallback"
		_source.tooltip_text = "This direction inherits the saved shared profile for this weapon, contact and attack." if shared else \
			"This direction uses the game's built-in values."
		_source.add_theme_color_override("font_color", SLATE)
	_response_group.visible = Preview.can_choose_response(surface)
	_response.select(int(_state.get(_response_state_key(surface), 0)))
	var response := _response.get_selected_id() if _response_group.visible else Preview.Response.DEFAULT
	var hard_stop := Preview.stops_weapon(_weapon_type, surface, clip, response)
	_playback_mode.text = "Hard stop" if hard_stop else "Breakthrough"
	_playback_mode.add_theme_color_override("font_color", AMBER if hard_stop else MINT)
	_playback_mode.tooltip_text = "The swing stops at contact and rebounds." if hard_stop else \
		"The swing follows through after contact."
	_preview.set_feedback(surface, charged, clip, response)


func _response_state_key(surface: StringName) -> String:
	return "response/%s" % surface


func _direction_state_key() -> String:
	return "%s/%s" % [_weapon_type, "charged_clip" if _weight.selected == 1 else "light_clip"]


func _update_direction() -> void:
	var charged := _weight.selected == 1
	var prefix := "heavy" if charged else "light"
	var preferred := StringName(prefix + "_left")
	var selected: StringName = _state.get(_direction_state_key(), preferred)
	_direction.clear()
	for clip: StringName in _animations:
		if HitShake.is_charged_motion(clip) != charged:
			continue
		var index := _direction.item_count
		var label := _animations[clip]
		if _weapon_type == "mace_2h":
			label = String(clip).trim_prefix(prefix + "_").capitalize()
		_direction.add_item(label)
		_direction.set_item_metadata(index, clip)
		if clip == selected:
			_direction.select(index)
	if _direction.selected < 0 and _direction.item_count > 0:
		_direction.select(0)
	_direction.disabled = _direction.item_count < 2
	if _direction.item_count == 0:
		_direction.text = "Shared"
