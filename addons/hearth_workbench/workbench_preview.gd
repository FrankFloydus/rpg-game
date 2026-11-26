@tool
extends VBoxContainer
## Live rendering of selected project assets in an isolated preview viewport.

var _stage: SubViewport
var _preview_root: Node3D
var _camera: Camera3D
var _scene: PackedScene
var _animation_player: AnimationPlayer
var _sample_clip := &""
var _sample_seconds := 0.0


func offer_scene(scene: PackedScene, title: String, playback: bool, show_initially := false) -> void:
	_scene = scene
	var toggle := Button.new()
	toggle.text = title
	toggle.toggle_mode = true
	toggle.button_pressed = show_initially
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	toggle.tooltip_text = "Show this actual project scene in the preview."
	toggle.toggled.connect(func(show_preview: bool) -> void:
		if show_preview:
			_open_scene(playback)
		else:
			_close_scene())
	add_child(toggle)
	if show_initially:
		_open_initial_scene.call_deferred(toggle, playback)


func _open_initial_scene(toggle: Button, playback: bool) -> void:
	if is_inside_tree() and toggle.button_pressed:
		_open_scene(playback)


func add_icon(texture: Texture2D, title: String) -> void:
	if texture == null:
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2.ONE * 50.0 * EditorInterface.get_editor_scale()
	icon.texture = texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.tooltip_text = texture.resource_path
	row.add_child(icon)
	var label := Label.new()
	label.text = title
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.tooltip_text = texture.resource_path
	row.add_child(label)
	add_child(row)


func _open_scene(playback: bool) -> void:
	if _stage != null:
		return
	var viewer := SubViewportContainer.new()
	viewer.custom_minimum_size.y = 190.0 * EditorInterface.get_editor_scale()
	viewer.stretch = true
	viewer.mouse_filter = Control.MOUSE_FILTER_PASS
	viewer.tooltip_text = "Drag to orbit. Scroll to zoom."
	viewer.gui_input.connect(_on_view_input)
	add_child(viewer)
	_stage = SubViewport.new()
	_stage.own_world_3d = true
	_stage.process_mode = Node.PROCESS_MODE_ALWAYS
	_stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewer.add_child(_stage)
	var preview_stage := _stage
	viewer.visibility_changed.connect(func() -> void:
		if _stage == preview_stage:
			preview_stage.render_target_update_mode = SubViewport.UPDATE_ALWAYS if viewer.is_visible_in_tree() \
				else SubViewport.UPDATE_DISABLED)
	_preview_root = Node3D.new()
	_stage.add_child(_preview_root)

	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#24262c")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#e6ebec")
	environment.ambient_light_energy = 0.76
	world.environment = environment
	_stage.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-39.0, -38.0, 0.0)
	key.light_energy = 1.6
	_stage.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-23.0, 147.0, 0.0)
	rim.light_color = Color("#e2d3ba")
	rim.light_energy = 0.7
	_stage.add_child(rim)
	_camera = Camera3D.new()
	_stage.add_child(_camera)
	_camera.fov = 44.0
	_camera.current = true

	var body := _scene.instantiate()
	_prepare(body)
	_preview_root.add_child(body)
	_animation_player = body.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var bounds := _bounds(_preview_root)
	var extent := maxf(maxf(bounds.size.x, bounds.size.y), bounds.size.z)
	var size_scale := clampf(extent, 0.50, 1.75 if playback else 32.0)
	var center := bounds.get_center()
	if playback:
		center = center.limit_length(0.52)
	_preview_root.position = -center
	_camera.position = Vector3(-0.38, 0.13, -1.58).normalized() * size_scale * 1.46
	_camera.look_at(Vector3.ZERO)
	sample_clip(_sample_clip, _sample_seconds)
	if playback:
		var replay := Button.new()
		replay.text = "Replay particles"
		replay.tooltip_text = "Restart each emitter in the actual scene."
		replay.pressed.connect(func() -> void: _restart(body))
		viewer.add_child(replay)
		_restart(body)


func _close_scene() -> void:
	if _stage == null:
		return
	var viewer := _stage.get_parent()
	remove_child(viewer)
	viewer.queue_free()
	_stage = null
	_preview_root = null
	_camera = null
	_animation_player = null


func sample_clip(clip: StringName, seconds: float) -> void:
	_sample_clip = clip
	_sample_seconds = seconds
	if _animation_player == null or not _animation_player.has_animation(clip):
		return
	_animation_player.play(clip)
	_animation_player.seek(seconds, true, true)
	_animation_player.pause()


func _on_view_input(event: InputEvent) -> void:
	if _camera == null:
		return
	if event is InputEventMouseButton and event.pressed:
		var zoom := 0.88 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.14
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_camera.position = _camera.position.normalized() * clampf(_camera.position.length() * zoom, 0.3, 64.0)
			_camera.look_at(Vector3.ZERO)
			get_viewport().set_input_as_handled()
	if not event is InputEventMouseMotion or not (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		return
	_camera.position = _camera.position.rotated(Vector3.UP, -event.relative.x * 0.018)
	var camera_right := _camera.basis.x.normalized()
	var next := _camera.position.rotated(camera_right, -event.relative.y * 0.018)
	if absf(next.normalized().y) < 0.97:
		_camera.position = next
	_camera.look_at(Vector3.ZERO)


func _prepare(node: Node) -> void:
	node.set_script(null)
	for connection: Dictionary in node.get_incoming_connections():
		connection.signal.disconnect(connection.callable)
	if node is Timer or node is AnimationPlayer or node is CollisionObject3D:
		node.process_mode = Node.PROCESS_MODE_DISABLED
	for child in node.get_children():
		_prepare(child)


func _bounds(node: Node) -> AABB:
	var result := AABB()
	if node is MeshInstance3D and node.mesh != null and node.visible:
		result = node.global_transform * node.get_aabb()
	elif node is GPUParticles3D:
		result = node.global_transform * node.visibility_aabb
	elif node is CPUParticles3D:
		result = AABB(node.global_position - Vector3.ONE * 1.5, Vector3.ONE * 3.0)
	for child in node.get_children():
		var child_bounds := _bounds(child)
		if child_bounds.has_volume():
			result = result.merge(child_bounds) if result.has_volume() else child_bounds
	return result


func _restart(node: Node) -> void:
	if node is GPUParticles3D or node is CPUParticles3D:
		if not node.one_shot:
			node.preprocess = maxf(node.preprocess, minf(node.lifetime * 0.55, 0.32))
		node.restart()
		node.emitting = true
		if node is GPUParticles3D:
			node.request_particles_process(minf(node.lifetime * 0.25, 0.12))
	for child in node.get_children():
		_restart(child)
