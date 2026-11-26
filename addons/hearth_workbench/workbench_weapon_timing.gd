@tool
extends VBoxContainer
## Reads the actual animation assets and sends editing to Godot's animation timeline.

const WeaponRoles := preload("res://combat/weapons/weapon_roles.gd")
const MARKERS := {
	&"Trace Start": "Attack playback can start detecting melee contacts here.",
	&"Terrain Start": "Arms the mace's surface checks near aim. A charged swing can begin a wall stop once it reaches Impact. Enemy traces use Trace Start.",
	&"Impact": "Authored contact or release pose. Sets the first possible wall stop on a charged mace swing and shapes the catch. Defaults to the trace midpoint.",
	&"Trace End": "This swing stops detecting new melee contacts after this point.",
	&"Input Buffer": "Earliest follow-up start for a 2H mace light. Early presses can already be queued. For other attacks this opens follow-up buffering.",
	&"Combo Entry": "Incoming pose at the start of a linked mace light. Adjusts the blend target without advancing the attack clock or trace.",
	&"Combo Exit": "Outgoing mace follow-through pose to use by the link gate. Keep this before the return to ready so a late link can blend directly into the next attack.",
}

var _clips := {}
var _viewer: Control
var _time: HSlider
var _marker_panel: VBoxContainer
var _time_label: Label
var _selected := &""


func configure(scene: PackedScene, viewer: Control, open_timeline: Callable) -> void:
	_viewer = viewer

	var instance := scene.instantiate()
	var player := instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null:
		for clip_id: StringName in player.get_animation_list():
			if _is_attack_clip(clip_id):
				_clips[clip_id] = player.get_animation(clip_id)
	instance.free()
	if _clips.is_empty():
		var empty := Label.new()
		empty.text = "This scene has no timed attack clips."
		add_child(empty)
		return
	var toolbar := HBoxContainer.new()
	add_child(toolbar)
	var clip := OptionButton.new()
	clip.name = &"AttackClip"
	clip.fit_to_longest_item = false
	clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip.tooltip_text = "Select one of the real AnimationPlayer clips. Charge clips finish before the charged strike begins."
	for clip_id: StringName in _clips:
		var animation: Animation = _clips[clip_id]
		clip.add_item(animation.resource_name if not animation.resource_name.is_empty() else String(clip_id).capitalize())
		clip.set_item_metadata(clip.item_count - 1, clip_id)
	clip.item_selected.connect(func(index: int) -> void: _show_clip(clip.get_item_metadata(index)))
	toolbar.add_child(clip)

	var timeline := Button.new()
	timeline.text = "Open AnimationPlayer"
	timeline.tooltip_text = "Edit the selected weapon's timeline in Godot. Move its existing markers to change the timing without changing poses."
	timeline.pressed.connect(open_timeline)
	toolbar.add_child(timeline)
	_time = HSlider.new()
	_time.step = 0.001
	_time.tooltip_text = "Open Preview model to see this pose. In play, attack speed and weapon commitment scale the markers with the pose."
	_time.value_changed.connect(_seek)
	add_child(_time)
	_time_label = Label.new()
	_time_label.tooltip_text = _time.tooltip_text
	add_child(_time_label)
	_marker_panel = VBoxContainer.new()
	add_child(_marker_panel)
	var weapon_type := scene.resource_path.get_file().get_basename()
	if WeaponRoles.DIRECTIONAL_CHARGE_MOVE_FACTORS.has(weapon_type):
		var limit := Label.new()
		limit.text = "Charged movement limit · %d%%" % roundi(
			float(WeaponRoles.DIRECTIONAL_CHARGE_MOVE_FACTORS[weapon_type]) * 100.0)
		limit.tooltip_text = "As this weapon winds up, movement eases toward this share of normal speed and returns through follow-through."
		add_child(limit)
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
