@tool
extends VBoxContainer
## Reads the actual animation assets and sends editing to Godot's animation timeline.

const WeaponRoles := preload("res://combat/weapons/weapon_roles.gd")
const MARKERS := {
	&"Trace Start": "Attack playback can start detecting melee contacts here.",
	&"Impact": "Authored point of strongest contact or projectile release. With no marker, the trace midpoint is used.",
	&"Trace End": "This swing stops detecting new melee contacts after this point.",
	&"Input Buffer": "From this point through the rest of the clip, an input can queue the next swing.",
}

var _clips := {}
var _viewer: Control
var _time: HSlider
var _marker_panel: VBoxContainer
var _time_label: Label
var _selected := &""


func configure(scene: PackedScene, viewer: Control, open_timeline: Callable) -> void:
	_viewer = viewer
	var content := VBoxContainer.new()
	var section := Button.new()
	section.text = "Attack clips and timing"
	section.tooltip_text = "Inspect the authored clip, charge length, trace window, and input buffer."
	section.toggle_mode = true
	section.toggled.connect(func(expanded: bool) -> void: content.visible = expanded)
	add_child(section)
	content.hide()
	add_child(content)

	var instance := scene.instantiate()
	var player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null:
		for clip_id: StringName in player.get_animation_list():
			if _is_attack_clip(clip_id):
				_clips[clip_id] = player.get_animation(clip_id)
	instance.free()
	if _clips.is_empty():
		section.hide()
		return
	var clip := OptionButton.new()
	clip.fit_to_longest_item = false
	clip.tooltip_text = "Select one of the real AnimationPlayer clips. Charge clips finish before the charged strike begins."
	for clip_id: StringName in _clips:
		var animation: Animation = _clips[clip_id]
		clip.add_item(animation.resource_name if not animation.resource_name.is_empty() else String(clip_id).capitalize())
		clip.set_item_metadata(clip.item_count - 1, clip_id)
	clip.item_selected.connect(func(index: int) -> void: _show_clip(clip.get_item_metadata(index)))
	content.add_child(clip)
	var weapon_type := scene.resource_path.get_file().get_basename()
	if WeaponRoles.DIRECTIONAL_CHARGE_MOVE_FACTORS.has(weapon_type):
		var limit := Label.new()
		limit.text = "Charged movement limit: %d%%" % roundi(
			float(WeaponRoles.DIRECTIONAL_CHARGE_MOVE_FACTORS[weapon_type]) * 100.0)
		limit.tooltip_text = "As this weapon winds up, movement eases toward this share of normal speed and returns through follow-through."
		content.add_child(limit)

	var timeline := Button.new()
	timeline.text = "Open AnimationPlayer"
	timeline.tooltip_text = "Edit the selected weapon's timeline in Godot. Move its existing markers to change the timing without changing poses."
	timeline.pressed.connect(open_timeline)
	content.add_child(timeline)
	_time = HSlider.new()
	_time.step = 0.001
	_time.tooltip_text = "Open Preview model to see this pose. In play, attack speed and weapon commitment scale the markers with the pose."
	_time.value_changed.connect(_seek)
	content.add_child(_time)
	_time_label = Label.new()
	_time_label.tooltip_text = _time.tooltip_text
	content.add_child(_time_label)
	_marker_panel = VBoxContainer.new()
	content.add_child(_marker_panel)
	clip.select(0)
	_show_clip(clip.get_item_metadata(0))


func _show_clip(key: StringName) -> void:
	_selected = key
	var animation: Animation = _clips[key]
	_time.max_value = animation.length
	_time.set_value_no_signal(0.0)
	_seek(0.0)
	for child in _marker_panel.get_children():
		_marker_panel.remove_child(child)
		child.queue_free()
	for name: StringName in MARKERS:
		if not animation.has_marker(name):
			continue
		var at := animation.get_marker_time(name)
		var jump := Button.new()
		jump.text = "%s   %0.3f s" % [name, at]
		jump.alignment = HORIZONTAL_ALIGNMENT_LEFT
		jump.tooltip_text = MARKERS[name]
		jump.pressed.connect(func() -> void: _time.value = at)
		_marker_panel.add_child(jump)


func _seek(seconds: float) -> void:
	_time_label.text = "%0.3f / %0.3f s · %s" % [seconds, _time.max_value, _selected]
	_viewer.sample_clip(_selected, seconds)


func _is_attack_clip(key: StringName) -> bool:
	var stem := String(key).get_file()
	if stem == "dual_clash_charge":
		return true
	stem = stem.trim_prefix("dual_")
	return stem.begins_with("light") or stem.begins_with("heavy") or stem.begins_with("charge")
