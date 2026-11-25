@tool
class_name BloodGpuEmitterLayer
extends GPUParticles3D
## A manually emitted GPU blood layer. The Addon Process Material reads the
## particle data assembled from the Blood Layer fields below.

enum Channel { MIST, SHEET, DROPS, CLOTS, COLLISION_EVENT }
enum Alignment { CAMERA, VELOCITY, CUSTOM, NORMAL, NORMAL_AND_TANGENT }
enum EmissionShape { CONE, SPHERE }
enum UvFlip { NONE, RANDOM_U, RANDOM_V, RANDOM_UV }
enum PixelCoverage { AUTOMATIC, DISABLED, GEOMETRY, RGBA }
enum SourceRayTiming { SIMULATION_STEP, PREVIOUS_PHYSICS_FRAME, HOST_PHYSICS_STEP }

const EMIT_FLAGS := EMIT_FLAG_POSITION | EMIT_FLAG_VELOCITY | EMIT_FLAG_CUSTOM | EMIT_FLAG_COLOR | EMIT_FLAG_ROTATION_SCALE
const DEFAULTS := {
	&"enabled": true, &"emitter_name": &"", &"reference_material": &"",
	&"channel": Channel.SHEET, &"alignment": Alignment.VELOCITY,
	&"uv_flip": UvFlip.NONE, &"facing_direction": Vector3.UP,
	&"emission_shape": EmissionShape.CONE, &"speed_stretch": true, &"collision_events": false,
	&"particle_count": 1, &"stream_count": 0, &"emission_window": 0.0, &"spawn_delay": 0.0,
	&"cone_degrees": 30.0, &"speed": Vector2(0.5, 1.5), &"particle_lifetime": Vector2(0.25, 0.7),
	&"width": Vector2(0.12, 0.32), &"length": Vector2(0.28, 0.65), &"spawn_radius": 0.0,
	&"gravity": 2.5, &"drag": 1.0, &"opacity": 0.88,
	&"source_motion": false, &"follow_source_transform": false, &"source_world_sprite_size": false,
	&"velocity_min": Vector3.ZERO, &"velocity_max": Vector3.ZERO,
	&"velocity_add_min": Vector3.ZERO, &"velocity_add_max": Vector3.ZERO,
	&"velocity_world_space": false, &"velocity_add_world_space": false, &"cone_world_space": false,
	&"cone_axis": Vector3.UP, &"cone_inner_degrees": 0.0, &"cone_speed": Vector2.ZERO,
	&"cone_axis_distribution": 0.0, &"cone_speed_falloff": 0.0,
	&"cone_use_distribution": false, &"cone_use_falloff": false,
	&"radial_speed": Vector2.ZERO, &"radial_origin": Vector3.ZERO, &"radial_random_direction": false,
	&"gravity_min": Vector3.ZERO, &"gravity_max": Vector3.ZERO, &"gravity_tracks_world": false,
	&"drag_range": Vector2.ZERO,
	&"stream_rate": 0.0, &"stream_delay": 0.0, &"stream_spacing": 0.0, &"loop_duration": 0.0, &"burst_loop_limit": 0,
	&"stream_probability": 1.0, &"stream_movement_tolerance": 0.0, &"stream_max_movement": 50.0,
	&"stream_max_speed": 0.0, &"inherit_velocity": 0.0,
	&"continuous_inherit_velocity": 0.0, &"continuous_inherit_velocity_limit": 0.0,
	&"rotation_range": Vector2.ZERO, &"alignment_direction": Vector3.UP,
	&"alignment_uses_initial_velocity": false, &"uniform_sprite_size": false, &"size_scale_range": Vector2.ONE,
	&"alignment_world_space": false, &"spawn_offset_world_space": false, &"spawn_offset": Vector3.ZERO,
	&"spawn_inner_radius": 0.0, &"spawn_radius_range": Vector2.ZERO, &"spawn_surface_only": false, &"spawn_shape_scale": Vector3.ONE, &"spawn_shape_world_space": false, &"spawn_ring": false,
	&"spawn_hemisphere_axis": Vector3.ZERO, &"spawn_disc": false,
	&"collision_radius_scale": 1.0, &"collision_scales_with_size": false, &"contact_after_force_solve": false,
	&"use_source_collision_rays": false, &"source_ray_timing": SourceRayTiming.SIMULATION_STEP,
	&"collision_replay_after": 0.0, &"collision_kill": false, &"use_scene_depth_collision": false, &"contact_source": &"",
	&"contact_spawn_mid_tick": false,
	&"dissolve_curve": null, &"alpha_curve": null, &"size_x_curve": null, &"size_y_curve": null,
	&"speed_scale_min": Vector2.ONE, &"speed_scale_max": Vector2.ONE,
	&"speed_scale_threshold": 0.0, &"speed_scale_curve": null, &"camera_offset": 0.0,
	&"sprite_pivot": Vector2(0.5, 0.5), &"smoke_color": Vector3(-1.0, -1.0, -1.0), &"smoke_frame_span": 63.0,
	&"pixel_coverage": PixelCoverage.AUTOMATIC, &"pixel_coverage_blend": 1.0,
}
const CURVE_PARAMETERS := {
	&"dissolve_curve": &"source_dissolve_curve", &"alpha_curve": &"source_alpha_curve",
	&"size_x_curve": &"source_size_x_curve", &"size_y_curve": &"source_size_y_curve",
	&"speed_scale_min": &"source_speed_scale_min", &"speed_scale_max": &"source_speed_scale_max",
	&"speed_scale_threshold": &"source_speed_scale_threshold", &"camera_offset": &"source_camera_offset",
	&"smoke_color": &"source_main_color", &"sprite_pivot": &"source_sprite_pivot",
	&"smoke_frame_span": &"source_smoke_frame_span",
	&"speed_scale_curve": &"source_speed_scale_curve",
	&"pixel_coverage": &"source_pixel_coverage", &"pixel_coverage_blend": &"source_pixel_coverage_blend",
}
const SCRIPT_PATH := "res://addons/godot-dismemberment/effects/scenes/blood_gpu_emitter_layer.gd"
const SMOKE_SHADER := preload("res://addons/godot-dismemberment/effects/blood_gpu_smoke_draw.gdshader")
const PROCESS_SHADER := preload("res://addons/godot-dismemberment/effects/blood_gpu_process.gdshader")
const RENDER_PROPERTIES: Array[StringName] = [
	&"material_override", &"material_overlay", &"cast_shadow", &"gi_mode", &"layers",
	&"amount", &"lifetime", &"preprocess", &"speed_scale", &"fixed_fps", &"interpolate",
	&"fract_delta", &"local_coords", &"visibility_aabb", &"draw_order", &"draw_passes",
	&"process_material", &"draw_pass_1", &"draw_pass_2", &"draw_pass_3", &"draw_pass_4",
	&"collision_base_size", &"transform_align", &"trail_enabled", &"trail_lifetime",
]

@export_group("Blood Layer")
## Allow this layer to emit when the effect plays.
@export var enabled: bool = DEFAULTS.enabled
## Name of this layer. Contact receivers use it to select which particles to listen to.
@export var emitter_name: StringName = DEFAULTS.emitter_name
## Identifier of the equivalent Niagara material. Edit Material Override to change the Godot material.
@export var reference_material: StringName = DEFAULTS.reference_material
## Select the shared material slot. Collision Event marks a layer that emits no visible sprites.
@export var channel: Channel = DEFAULTS.channel
## Choose how each sprite faces the camera, follows velocity, or uses an authored direction or surface frame.
@export var alignment: Alignment = DEFAULTS.alignment
## Choose a cone or all directions for legacy launch velocity. With Source Motion, use the cone and radial controls below.
@export var emission_shape: EmissionShape = DEFAULTS.emission_shape
## Let compatible draw materials stretch sprites as their speed increases.
@export var speed_stretch: bool = DEFAULTS.speed_stretch
## Send particle contacts to matching decal and particle receivers during gameplay.
@export var collision_events: bool = DEFAULTS.collision_events
## Number of particles in each burst, before any continuous emissions.
@export_range(0, 1024, 1) var particle_count: int = DEFAULTS.particle_count
## Number of particles spread over the emission window when Source Motion is disabled.
@export_range(0, 1024, 1) var stream_count: int = DEFAULTS.stream_count
## How long the time-based stream emits, in seconds.
@export_range(0.0, 60.0, 0.01, "or_greater", "suffix:s") var emission_window: float = DEFAULTS.emission_window
## Delay in seconds before the burst. Also delays the stream when Source Motion is disabled.
@export_range(0.0, 60.0, 0.01, "or_greater", "suffix:s") var spawn_delay: float = DEFAULTS.spawn_delay
## Maximum angle from the cone axis, in degrees.
@export_range(0.0, 180.0, 0.1, "suffix:Â°") var cone_degrees: float = DEFAULTS.cone_degrees
## Minimum and maximum launch speed in m/s when Source Motion is disabled.
@export var speed: Vector2 = DEFAULTS.speed
## Minimum and maximum lifespan in seconds for each particle.
@export var particle_lifetime: Vector2 = DEFAULTS.particle_lifetime
## Minimum and maximum sprite width in metres before effect scale and size curves.
@export var width: Vector2 = DEFAULTS.width
## Minimum and maximum sprite height in metres before effect scale. Uniform Sprite Size uses Width for both axes.
@export var length: Vector2 = DEFAULTS.length
## Outer radius of the spawn shape in metres. Zero spawns at the offset unless Spawn Radius Range supplies a radius.
@export_range(0.0, 3.0, 0.005, "suffix:m") var spawn_radius: float = DEFAULTS.spawn_radius
## Downward acceleration when Source Motion is disabled. Negative values accelerate particles upward.
@export_range(-20.0, 30.0, 0.01, "suffix:m/sÂ²") var gravity: float = DEFAULTS.gravity
## How quickly drag slows particles when Source Motion is disabled. Zero applies no drag.
@export_range(0.0, 15.0, 0.01) var drag: float = DEFAULTS.drag
## Multiplier for the particle's starting opacity. Its material and curves control the final fade.
@export_range(0.0, 2.0, 0.01, "or_greater") var opacity: float = DEFAULTS.opacity

@export_group("Source Motion")
## Use the authored Niagara modules instead of the legacy speed and spread.
@export var source_motion := false
## Keep live smoke attached to a moving source. Supports the bundled smoke and process shaders.
@export var follow_source_transform := false
## Per-axis minimum of the initial velocity in m/s. The launch frame has +Y forward, -X up, and +Z right.
@export var velocity_min := Vector3.ZERO
## Per-axis maximum of the initial velocity in m/s.
@export var velocity_max := Vector3.ZERO
## Per-axis minimum of a second, independently sampled launch velocity in m/s.
@export var velocity_add_min := Vector3.ZERO
## Per-axis maximum of the second launch velocity in m/s.
@export var velocity_add_max := Vector3.ZERO
## Interpret Velocity Min and Max in world axes instead of the launch frame.
@export var velocity_world_space := false
## Interpret Velocity Add Min and Max in world axes instead of the launch frame.
@export var velocity_add_world_space := false
## Interpret the cone axis and its sampled velocity in world axes.
@export var cone_world_space := false
## Direction at the center of the source velocity cone.
@export var cone_axis := Vector3.UP
## Minimum angle from the cone axis, in degrees. A positive value excludes the center of the cone.
@export var cone_inner_degrees := 0.0
## Minimum and maximum speed in m/s contributed by the cone. Zero disables this velocity contribution.
@export var cone_speed := Vector2.ZERO
## Bias cone samples toward the axis. Used when Cone Use Distribution is enabled.
@export var cone_axis_distribution := 0.0
## Reduce launch speed toward the edge of the cone. Used when Cone Use Falloff is enabled.
@export var cone_speed_falloff := 0.0
## Apply Cone Axis Distribution when sampling launch directions.
@export var cone_use_distribution := false
## Apply Cone Speed Falloff to cone velocity.
@export var cone_use_falloff := false
## Minimum and maximum radial speed in m/s. Negative values send particles inward.
@export var radial_speed := Vector2.ZERO
## Local point from which radial velocity is measured.
@export var radial_origin := Vector3.ZERO
## Sample radial velocity independently of the spawn position.
@export var radial_random_direction := false
## Per-axis minimum world-space acceleration in metres per second squared.
@export var gravity_min := Vector3.ZERO
## Per-axis maximum world-space acceleration in metres per second squared.
@export var gravity_max := Vector3.ZERO
## In source-attached smoke, update the local force from the world-space acceleration each step.
@export var gravity_tracks_world := false
## Minimum and maximum drag sampled at birth. Larger values slow particles more quickly.
@export var drag_range := Vector2.ZERO
## Offset from the layer origin in metres. Spawn Offset World Space selects the coordinate axes.
@export var spawn_offset := Vector3.ZERO
## Minimum distance from the spawn center for a filled sphere or disc.
@export var spawn_inner_radius := 0.0
## Minimum and maximum outer spawn radius in metres. A nonzero range replaces Spawn Radius.
@export var spawn_radius_range := Vector2.ZERO
## Place spherical births on the outer surface instead of filling its volume.
@export var spawn_surface_only := false
## Per-axis stretch for the spherical spawn shape. Use it to make an ellipsoid.
@export var spawn_shape_scale := Vector3.ONE
## Sample the hemisphere facing this axis in the spawn shape's coordinate space. Zero uses the full sphere.
@export var spawn_hemisphere_axis := Vector3.ZERO
## Keep the spawn shape aligned to world axes when the effect rotates.
@export var spawn_shape_world_space := false
## Use a planar spawn shape. With a sampled radius and Spawn Disc disabled, births lie on that radius.
@export var spawn_ring := false
## Fill the planar spawn shape uniformly by area within its sampled outer radius.
@export var spawn_disc := false
## Particles per second over the authored emission window.
@export var stream_rate := 0.0
## Time in seconds before the source stream starts within each loop.
@export var stream_delay := 0.0
## Time in seconds between loop starts. Zero plays the emission schedule once.
@export var loop_duration := 0.0
## Number of authored burst loops. Zero keeps the burst on every loop.
@export var burst_loop_limit := 0
## Distance between movement-based spawns in metres.
@export var stream_spacing := 0.0
## Probability from 0 to 1 that a distance-based spawn produces a particle.
@export var stream_probability := 1.0
## Ignore source travel below this distance in metres when placing distance-based births.
@export var stream_movement_tolerance := 0.0
## Maximum distance sampled per update when no source speed limit is set.
@export var stream_max_movement := 50.0
## Suppress distance-based births when the source moves faster than this speed.
## Zero keeps the movement limit above. Rate-based births still run.
@export_range(0.0, 50.0, 0.01, "or_greater", "suffix:m/s") var stream_max_speed := 0.0
## Fraction of the source's velocity inherited when a particle is born.
@export var inherit_velocity := 0.0
## Source velocity added every 60 Hz simulation step, as a fraction of its speed.
@export var continuous_inherit_velocity := 0.0
## Limit on source speed before the continuous inheritance multiplier. Zero uses the full source speed.
@export_range(0.0, 20.0, 0.01, "or_greater", "suffix:m/s") var continuous_inherit_velocity_limit := 0.0
## Initial sprite rotation in turns, sampled at spawn.
@export var rotation_range := Vector2.ZERO
## Direction for Custom or Normal alignment, or the tangent for Normal And Tangent alignment.
@export var alignment_direction := Vector3.UP
## Use the launch velocity for the initial alignment direction. Normal And Tangent uses the authored frame.
@export var alignment_uses_initial_velocity := false
## Sample one value from Width and use it for both sprite axes before scaling.
@export var uniform_sprite_size := false
## Per-particle shared size multiplier before the age and speed curves.
@export var size_scale_range := Vector2.ONE
## Interpret the authored alignment and facing directions in world axes.
@export var alignment_world_space := false
## Interpret Spawn Offset in world axes so it does not rotate with the effect.
@export var spawn_offset_world_space := false

@export_group("Source Collision")
## Multiply the collision radius derived from half the sprite's diagonal.
@export var collision_radius_scale := 1.0
## Apply the shared X and Y size curve to the collision radius as the sprite ages.
@export var collision_scales_with_size := false
## Keep the remaining tangential motion before sending the source collision event.
@export var contact_after_force_solve := false
## Confirm sphere contacts against the source emitter's previous-step center rays.
@export var use_source_collision_rays := false
## Simulation Step resolves the preceding 60 Hz particle query. Previous Physics Frame
## reproduces Niagara's async query lifetime when Godot physics matches the source world's cadence.
## Host Physics Step advances the sprite and collision rays once per physics frame for
## immediate, non-looping bursts using the bundled process shader. Requires Use Source Collision Rays.
@export var source_ray_timing: SourceRayTiming = DEFAULTS.source_ray_timing
## Source emitter active time before an immediate, non-looping burst can replay its final contact batch.
## Zero disables the replay. Continuous and delayed emitters ignore this setting.
@export_range(0.0, 60.0, 0.01, "or_greater", "suffix:s") var collision_replay_after := 0.0
## Retire a particle on collision so its sprite disappears at the impact.
@export var collision_kill := false
## Simulate eligible finite visual bursts against the active Forward+ camera depth.
@export var use_scene_depth_collision := false
## Only spawn this layer at a collision from the named source layer.
@export var contact_source: StringName
## Start a contact sprite halfway through its first 60 Hz update at the contact position.
@export var contact_spawn_mid_tick := false

@export_group("Source Sprite Curves")
## Keep sprite dimensions independent of the source transform, using the explicit effect scale.
@export var source_world_sprite_size := false
## Match Niagara's minimum sprite size for translucent materials in perspective.
@export var pixel_coverage := PixelCoverage.AUTOMATIC
## Blend the selected alpha or RGBA adjustment as the original sprite becomes subpixel.
@export_range(0.0, 1.0, 0.01) var pixel_coverage_blend := 1.0
## Randomly mirror the Niagara sprite textures along U, V, or independently along both.
@export var uv_flip: UvFlip = DEFAULTS.uv_flip
## Facing normal for Normal And Tangent alignment. Alignment Direction is its tangent.
## Alignment World Space selects the coordinate space for both directions.
@export var facing_direction := Vector3.UP
## Dissolve threshold over the particle's normalized lifetime, from birth at 0 to expiry at 1.
@export var dissolve_curve: CurveTexture
## Opacity multiplier over the particle's normalized lifetime.
@export var alpha_curve: CurveTexture
## Horizontal sprite scale over the particle's normalized lifetime.
@export var size_x_curve: CurveTexture
## Vertical sprite scale over the particle's normalized lifetime.
@export var size_y_curve: CurveTexture
## Horizontal and vertical size multipliers at zero particle speed.
@export var speed_scale_min := Vector2.ONE
## Horizontal and vertical size multipliers at or above Speed Scale Threshold.
@export var speed_scale_max := Vector2.ONE
## Speed in m/s at which the maximum speed scale is reached. Zero disables this scaling.
@export var speed_scale_threshold := 0.0
## Remap normalized speed before interpolating the minimum and maximum size multipliers.
@export var speed_scale_curve: CurveTexture
## Move the drawn sprite toward the camera by this many metres. Negative values move it away.
@export var camera_offset := 0.0
## Anchor point within the sprite from 0 to 1 on each axis. (0.5, 0.5) centers it.
@export var sprite_pivot := Vector2(0.5, 0.5)
## Linear RGB override for the smoke tint. Leave all three values at -1 to use the material color.
@export var smoke_color := Vector3(-1.0, -1.0, -1.0)
## How far the smoke flipbook advances over the particle lifetime. The atlas has 64 frames.
@export_range(0.0, 64.0, 1.0) var smoke_frame_span: float = DEFAULTS.smoke_frame_span

## Read the saved editor fields for pooled playback without instantiating scenes.
static func read_scene_layers(scene: PackedScene) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if scene == null:
		return result
	var state := scene.get_state()
	for index in range(1, state.get_node_count()):
		if state.get_node_path(index, true) != NodePath("."):
			continue
		var layer := DEFAULTS.duplicate()
		layer.renderer = {}
		layer.transform = Transform3D.IDENTITY
		layer.visible = true
		var is_layer := false
		for property_index in state.get_node_property_count(index):
			var name := state.get_node_property_name(index, property_index)
			var value = state.get_node_property_value(index, property_index)
			if name == &"script" and value is Script and value.resource_path == SCRIPT_PATH:
				is_layer = true
			elif name in RENDER_PROPERTIES:
				layer.renderer[name] = value
			elif layer.has(name):
				layer[name] = value
		if is_layer:
			_set_collision_curve_samples(layer)
			result.append(layer)
	return result

static func read_renderer_settings(emitter: GPUParticles3D) -> Dictionary:
	var settings := {}
	for property in RENDER_PROPERTIES:
		if renderer_property_available(emitter, property):
			settings[property] = emitter.get(property)
	return settings

static func depth_backend(owner: Node3D, emitter: GPUParticles3D, layer: Dictionary, material: Material) -> Node:
	if not layer.use_scene_depth_collision or Engine.is_editor_hint() \
			or RenderingServer.get_current_rendering_method() != &"forward_plus":
		return null
	const PATH := "res://addons/godot-dismemberment/effects/blood_depth_spots.gd"
	if not ResourceLoader.exists(PATH, "Script"):
		return null
	var backend: GDScript = load(PATH)
	return backend.get_backend(owner) if backend.eligible(layer, emitter, material) else null

static func clear_depth_owner(owner: Node3D) -> void:
	var viewport := owner.get_viewport()
	const DEPTH_KEY := &"_blood_spots_depth_backend"
	if viewport != null and viewport.has_meta(DEPTH_KEY):
		var depth: Node = viewport.get_meta(DEPTH_KEY)
		if is_instance_valid(depth):
			depth.clear_owner(owner.get_instance_id())

static func renderer_property_available(emitter: GPUParticles3D, property: StringName) -> bool:
	var name := String(property)
	return not name.begins_with("draw_pass_") or int(name.trim_prefix("draw_pass_")) <= emitter.draw_passes

func get_blood_settings() -> Dictionary:
	var settings := {}
	for property: StringName in DEFAULTS:
		settings[property] = get(property)
	settings.transform = transform
	settings.visible = visible
	_set_collision_curve_samples(settings)
	return settings

static func visual_curve_settings(layer: Dictionary) -> Dictionary:
	var result := {}
	for key in CURVE_PARAMETERS:
		var value = layer.get(key, DEFAULTS[key])
		if value != DEFAULTS[key]:
			result[key] = value
	return result

static func needs_anisotropic_normal_binding(material: Material) -> bool:
	return material is ShaderMaterial and material.get_shader_parameter(&"source_normal_anisotropic") == true \
		and material.get_shader_parameter(&"source_graph") == true \
		and material.get_shader_parameter(&"source_normal_map_anisotropic") != material.get_shader_parameter(&"source_normal_map")

static func bind_visual_curves(material: Material, layer: Dictionary) -> Material:
	if not material is ShaderMaterial or material.get_shader_parameter(&"source_graph") != true:
		return material
	var settings := visual_curve_settings(layer)
	var bind_normal := needs_anisotropic_normal_binding(material)
	if settings.is_empty() and not bind_normal:
		return material
	var result := material.duplicate() as ShaderMaterial
	if bind_normal:
		result.set_shader_parameter(&"source_normal_map_anisotropic", material.get_shader_parameter(&"source_normal_map"))
	for key in settings:
		result.set_shader_parameter(CURVE_PARAMETERS[key], settings[key])
		if settings[key] is CurveTexture:
			result.set_shader_parameter(&"has_" + key, true)
	return result

static func supports_source_attachment(layer: Dictionary, draw: Material, process: Material) -> bool:
	return layer.follow_source_transform and layer.source_motion and layer.channel == Channel.MIST \
		and not layer.collision_events and not layer.collision_kill and layer.continuous_inherit_velocity == 0.0 \
		and draw is ShaderMaterial and draw.shader == SMOKE_SHADER \
		and process is ShaderMaterial and process.shader == PROCESS_SHADER

static func set_smoke_draw_basis(emitter: GPUParticles3D) -> void:
	var basis := emitter.global_basis
	var invertible := basis.is_finite() and basis.determinant() != 0.0
	var rows := basis.inverse().transposed() if invertible else Basis.IDENTITY
	emitter.set_instance_shader_parameter(&"source_emitter_inverse_x", rows.x)
	emitter.set_instance_shader_parameter(&"source_emitter_inverse_y", rows.y)
	emitter.set_instance_shader_parameter(&"source_emitter_inverse_z", rows.z)
	emitter.set_instance_shader_parameter(&"source_emitter_unscale", Vector3.ONE / basis.get_scale().abs()
		if invertible else Vector3.ONE)

static func set_smoke_gravity_basis(emitter: GPUParticles3D) -> void:
	var basis := emitter.global_basis
	var world_to_local := basis.orthonormalized().transposed() if basis.is_finite() and basis.determinant() != 0.0 \
		else Basis.IDENTITY
	(emitter.process_material as ShaderMaterial).set_shader_parameter(&"source_gravity_world_to_local", world_to_local)

var _source_attached := false
var _local_coords_before_attachment := false
var _unbound_smoke_process: ShaderMaterial
var _bound_smoke_process: ShaderMaterial

func bind_source_attachment(layer: Dictionary) -> void:
	var supported := supports_source_attachment(layer, material_override, process_material)
	if supported != _source_attached:
		if supported:
			_local_coords_before_attachment = local_coords
			local_coords = true
		else:
			local_coords = _local_coords_before_attachment
			set_instance_shader_parameter(&"source_emitter_inverse_x", null)
			set_instance_shader_parameter(&"source_emitter_inverse_y", null)
			set_instance_shader_parameter(&"source_emitter_inverse_z", null)
			set_instance_shader_parameter(&"source_emitter_unscale", null)
		_source_attached = supported
		set_notify_transform(supported)
	if supported and layer.gravity_tracks_world:
		if process_material != _bound_smoke_process:
			_unbound_smoke_process = process_material as ShaderMaterial
			_bound_smoke_process = _unbound_smoke_process.duplicate() as ShaderMaterial
			process_material = _bound_smoke_process
	elif _bound_smoke_process != null:
		if process_material == _bound_smoke_process:
			process_material = _unbound_smoke_process
		_unbound_smoke_process = null
		_bound_smoke_process = null
	if supported:
		set_smoke_draw_basis(self)
		if _bound_smoke_process != null:
			set_smoke_gravity_basis(self)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and _source_attached and is_inside_tree():
		set_smoke_draw_basis(self)
		if _bound_smoke_process != null and process_material == _bound_smoke_process:
			set_smoke_gravity_basis(self)

static func supports_gpu() -> bool:
	if DisplayServer.get_name() == "headless":
		return false
	var method := RenderingServer.get_current_rendering_method()
	return method == &"forward_plus" or method == &"mobile"

static func launch_axis(family: StringName, direction: Vector3) -> Vector3:
	var direction_scale := maxf(absf(direction.x), maxf(absf(direction.y), absf(direction.z)))
	var axis := (direction / direction_scale).normalized() if direction_scale > 0.0 else Vector3.UP
	if family == &"hit" and direction_scale > 0.0:
		axis = -axis
	if family == &"dripping" or family == &"dynamic":
		return (Vector3.DOWN + axis * 0.22).normalized()
	if family == &"hit" or family == &"slash" or family == &"dripping_splash" or family == &"splash":
		return (axis + Vector3.UP * 0.22).normalized()
	return axis

## Converts an Unreal +X launch direction into the layer's +Y launch frame.
static func launch_pose(family: StringName, direction: Vector3, size_scale: float,
		location: Vector3, source_motion: bool, up := Vector3.UP) -> Transform3D:
	if not source_motion:
		var axis := launch_axis(family, direction)
		return Transform3D(Basis(Quaternion(Vector3.UP, axis)).scaled(Vector3.ONE * size_scale), location)

	var forward := _direction(direction, Vector3.RIGHT)
	if family == &"hit":
		forward = -forward
	var side := forward.cross(up).normalized()
	if side.is_zero_approx():
		var preferred_side := Vector3.BACK if absf(forward.z) < 0.95 else Vector3.RIGHT
		side = (preferred_side - forward * preferred_side.dot(forward)).normalized()
	var launch_up := side.cross(forward)
	var frame := Basis(-launch_up, forward, side)
	return Transform3D(frame.scaled(Vector3.ONE * size_scale), location)

static func _direction(value: Vector3, fallback: Vector3) -> Vector3:
	var magnitude := maxf(absf(value.x), maxf(absf(value.y), absf(value.z)))
	return (value / magnitude).normalized() if magnitude > 0.0 else fallback

static func _random_vector(minimum: Vector3, maximum: Vector3) -> Vector3:
	return Vector3(randf_range(minimum.x, maximum.x), randf_range(minimum.y, maximum.y),
		randf_range(minimum.z, maximum.z))

static func _random_unit_vector() -> Vector3:
	var z := randf_range(-1.0, 1.0)
	var angle := randf() * TAU
	var radius := sqrt(maxf(0.0, 1.0 - z * z))
	return Vector3(radius * cos(angle), z, radius * sin(angle))

static func _cone_velocity(axis: Vector3, inner: float, outer: float, speed: float,
		distribution: float, falloff: float) -> Vector3:
	var reference := Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT
	var tangent := reference.cross(axis).normalized()
	var bitangent := axis.cross(tangent)
	var azimuth := randf() * TAU
	var cos_inner := cos(deg_to_rad(inner))
	var outer_multiplier := clampf(randf_range(lerpf(1.0, -0.5, distribution), 1.0), 0.0, 1.0) if distribution > 0.0 else 1.0
	var cos_outer := cos(deg_to_rad(outer * outer_multiplier))
	var cosine := randf_range(cos_outer, cos_inner)
	var radial := sqrt(maxf(0.0, 1.0 - cosine * cosine))
	var spread := tangent * cos(azimuth) + bitangent * sin(azimuth)
	var direction := axis * cosine + spread * radial
	if falloff > 0.0:
		speed *= lerpf(1.0, pow(clampf(cosine, 0.0, 1.0), falloff * 10.0), falloff)
	return direction * speed

static func has_spawns(layer: Dictionary, duration: float, moving_source: bool) -> bool:
	if layer.particle_count > 0:
		return true
	if not layer.source_motion:
		return layer.stream_count > 0
	if moving_source and layer.stream_spacing > 0.0:
		return true
	if layer.stream_rate <= 0.0:
		return false
	if layer.loop_duration > 0.0 and duration != 0.0:
		return true
	return stream_count_for_layer(layer) > 0

static func supports_host_clock(layer: Dictionary, process: Material, local_coordinates: bool,
		speed_scale: float, preprocess: float) -> bool:
	return not Engine.is_editor_hint() and layer.source_ray_timing == SourceRayTiming.HOST_PHYSICS_STEP \
		and layer.source_motion and layer.use_source_collision_rays and not layer.use_scene_depth_collision \
		and not local_coordinates and speed_scale == 1.0 and preprocess == 0.0 \
		and layer.spawn_delay == 0.0 and layer.loop_duration == 0.0 \
		and layer.stream_rate == 0.0 and layer.stream_spacing == 0.0 and layer.collision_replay_after == 0.0 \
		and layer.continuous_inherit_velocity == 0.0 and layer.contact_source.is_empty() \
		and process is ShaderMaterial and process.shader == PROCESS_SHADER

static func particle_count_for_layer(layer: Dictionary) -> int:
	return maxi(layer.particle_count, 0) + stream_count_for_layer(layer)

static func duration_for_layer(layer: Dictionary) -> float:
	return maxf(layer.spawn_delay, layer.stream_delay + layer.emission_window) 		+ maxf(layer.particle_lifetime.x, layer.particle_lifetime.y)

static func stream_count_for_layer(layer: Dictionary) -> int:
	if layer.source_motion:
		return maxi(int(floor(layer.stream_rate * layer.emission_window + 0.00001)), 0)
	return maxi(layer.stream_count, 0)

static func emit_layer(emitter: GPUParticles3D, layer: Dictionary, effect_transform: Transform3D,
		collision_samples: Array[Dictionary] = [], collect_collisions := false,
		source_velocity := Vector3.ZERO, particle_id_provider := Callable(), sprite_scale := 0.0) -> int:
	if not layer.enabled or not layer.visible or layer.channel == Channel.COLLISION_EVENT:
		return 0
	var burst_count := maxi(layer.particle_count, 0)
	var stream_count := stream_count_for_layer(layer)
	if burst_count + stream_count == 0:
		return 0

	var context := prepare_layer(emitter, layer, effect_transform, sprite_scale)
	for particle in burst_count + stream_count:
		var delay: float = layer.spawn_delay
		if particle >= burst_count:
			var stream_index := particle - burst_count + 1
			if layer.source_motion:
				delay = layer.stream_delay + float(stream_index) / layer.stream_rate
			else:
				delay += layer.emission_window * float(stream_index) / stream_count
		emit_prepared_sample(emitter, layer, context, delay, collision_samples, collect_collisions, source_velocity, particle_id_provider)
	request_gpu_update(emitter)
	return burst_count + stream_count

static func equivalent_draw_quad(a: Variant, b: Variant) -> bool:
	return a == b or a is QuadMesh and b is QuadMesh and a.size == b.size and a.orientation == b.orientation 		and a.subdivide_width == b.subdivide_width and a.subdivide_depth == b.subdivide_depth 		and a.center_offset == b.center_offset and a.flip_faces == b.flip_faces and a.material == b.material

static func request_gpu_update(emitter: GPUParticles3D) -> void:
	# Manual emission buffers particles. Queue their normal update before the next viewport cull.
	if emitter.is_visible_in_tree():
		RenderingServer.particles_request_process(emitter.get_base())

static func emit_sample(emitter: GPUParticles3D, layer: Dictionary, effect_transform: Transform3D,
		delay := 0.0, collision_samples: Array[Dictionary] = [], collect_collisions := false,
		source_velocity := Vector3.ZERO, particle_id_provider := Callable(), motion_slot := 0, sprite_scale := 0.0) -> void:
	if layer.enabled and layer.visible and layer.channel != Channel.COLLISION_EVENT:
		emit_prepared_sample(emitter, layer, prepare_layer(emitter, layer, effect_transform, sprite_scale), delay,
			collision_samples, collect_collisions, source_velocity, particle_id_provider, motion_slot)

static func prepare_layer(emitter: GPUParticles3D, layer: Dictionary, effect_transform: Transform3D,
		sprite_scale := 0.0) -> Dictionary:
	var world: Transform3D = effect_transform * layer.transform
	var orientation := world.basis.orthonormalized()
	var source_motion: bool = layer.source_motion
	var local_inverse := emitter.global_basis.inverse() if emitter.local_coords else Basis.IDENTITY
	var velocity_inverse := local_inverse
	if emitter.local_coords and supports_source_attachment(layer, emitter.material_override, emitter.process_material):
		velocity_inverse = emitter.global_basis.orthonormalized().transposed()
	if not emitter.local_coords:
		_cover(emitter, emitter.to_local(world.origin))
	var radius := maxf(0.0, layer.spawn_radius)
	var alignment_basis := Basis.IDENTITY if layer.alignment_world_space else orientation
	var custom_alignment := alignment_basis * _direction(layer.alignment_direction, Vector3.UP)
	var packed_twist := 0.0
	if layer.alignment == Alignment.NORMAL_AND_TANGENT:
		var normal := alignment_basis * _direction(layer.facing_direction, Vector3.UP)
		var reference := Vector3.UP if absf(normal.y) < 0.99 else Vector3.RIGHT
		var reference_right := reference.cross(normal).normalized()
		var reference_up := normal.cross(reference_right)
		var sprite_right := custom_alignment.cross(normal)
		var facing_twist := atan2(sprite_right.dot(reference_up), sprite_right.dot(reference_right))
		packed_twist = fposmod(facing_twist / TAU, 1.0) * 0.5
		custom_alignment = normal
	var scale := world.basis.get_scale().abs()
	var dimensions := scale
	if sprite_scale > 0.0 and source_motion and not emitter.local_coords \
			and layer.get(&"source_world_sprite_size", false):
		var layer_transform: Transform3D = layer.transform
		dimensions = layer_transform.basis.get_scale().abs() * sprite_scale
	return {
		&"world": world, &"orientation": orientation, &"scale": scale, &"dimensions": dimensions,
		&"local_inverse": local_inverse, &"velocity_inverse": velocity_inverse,
		&"cone_axis": _direction(layer.cone_axis, Vector3.UP) if source_motion else Vector3.UP,
		&"cone_angle": layer.cone_degrees if source_motion or layer.emission_shape == EmissionShape.CONE else 180.0,
		&"custom_alignment": custom_alignment, &"packed_twist": packed_twist,
		&"radius": radius,
		&"spawn_hemisphere_axis": _direction(layer.get(&"spawn_hemisphere_axis", Vector3.ZERO), Vector3.ZERO),
	}

static func _set_collision_curve_samples(layer: Dictionary) -> void:
	if not layer.collision_scales_with_size:
		return
	var size_texture: CurveTexture = layer.size_x_curve
	if size_texture == null or size_texture != layer.size_y_curve or size_texture.curve == null:
		return
	var curve := size_texture.curve
	var samples := PackedFloat32Array()
	samples.resize(33)
	for index in samples.size():
		samples[index] = curve.sample(float(index) / (samples.size() - 1))
	layer[&"radius_curve"] = samples

static func emit_prepared_sample(emitter: GPUParticles3D, layer: Dictionary, context: Dictionary, delay: float,
		collision_samples: Array[Dictionary], collect_collisions: bool, source_velocity: Vector3,
		particle_id_provider := Callable(), motion_slot := 0, gpu_births: Variant = null) -> void:
	var world: Transform3D = context.world
	var orientation: Basis = context.orientation
	var scale: Vector3 = context.scale
	var local_inverse: Basis = context.local_inverse
	var radius: float = context.radius
	if layer.spawn_radius_range != Vector2.ZERO:
		radius = maxf(0.0, randf_range(layer.spawn_radius_range.x, layer.spawn_radius_range.y))
	var source_motion: bool = layer.source_motion
	var offset: Vector3 = Vector3.ZERO if layer.spawn_offset_world_space else layer.spawn_offset
	var shape_offset := Vector3.ZERO
	if radius > 0.0:
		var fill_disc: bool = layer.get(&"spawn_disc", false)
		if layer.spawn_ring or fill_disc:
			var angle := randf() * TAU
			var distance := radius
			if fill_disc or layer.spawn_radius_range == Vector2.ZERO:
				var inner := clampf(layer.spawn_inner_radius, 0.0, radius)
				distance = sqrt(randf_range(inner * inner, radius * radius))
			var ring_axis := Vector3(cos(angle), 0.0, sin(angle)) if layer.spawn_shape_world_space \
				else Vector3(0.0, cos(angle), sin(angle))
			shape_offset = ring_axis * distance
		else:
			var distance := radius
			if not layer.spawn_surface_only:
				var inner := clampf(layer.spawn_inner_radius, 0.0, radius)
				distance = pow(randf_range(inner * inner * inner, radius * radius * radius), 1.0 / 3.0)
			var direction := _random_unit_vector()
			var hemisphere_axis: Vector3 = context.spawn_hemisphere_axis
			if hemisphere_axis != Vector3.ZERO:
				direction -= hemisphere_axis * (2.0 * minf(direction.dot(hemisphere_axis), 0.0))
			shape_offset = direction * distance * layer.spawn_shape_scale
	if not layer.spawn_shape_world_space:
		offset += shape_offset
	var position := world * offset
	if layer.spawn_offset_world_space:
		position += layer.spawn_offset * scale
	if layer.spawn_shape_world_space:
		position += shape_offset * scale
	var velocity := Vector3.ZERO
	var acceleration := Vector3(0.0, -layer.gravity, 0.0)
	var drag: float = layer.drag
	if source_motion:
		var primary_velocity := _random_vector(layer.velocity_min, layer.velocity_max)
		var additional_velocity := _random_vector(layer.velocity_add_min, layer.velocity_add_max)
		velocity = primary_velocity if layer.velocity_world_space else orientation * primary_velocity
		velocity += additional_velocity if layer.velocity_add_world_space else orientation * additional_velocity
		if layer.radial_speed != Vector2.ZERO:
			var radial: Vector3 = position - world * layer.radial_origin
			radial = orientation * _random_unit_vector() if layer.radial_random_direction or radial.is_zero_approx() else radial.normalized()
			velocity += radial * randf_range(layer.radial_speed.x, layer.radial_speed.y)
		if layer.cone_speed != Vector2.ZERO:
			var cone := _cone_velocity(context.cone_axis, layer.cone_inner_degrees, context.cone_angle,
				randf_range(layer.cone_speed.x, layer.cone_speed.y),
				clampf(layer.cone_axis_distribution, 0.0, 1.0) if layer.cone_use_distribution else 0.0,
				clampf(layer.cone_speed_falloff, 0.0, 1.0) if layer.cone_use_falloff else 0.0)
			velocity += cone if layer.cone_world_space else orientation * cone
		acceleration = _random_vector(layer.gravity_min, layer.gravity_max)
		drag = randf_range(layer.drag_range.x, layer.drag_range.y)
	else:
		velocity = orientation * _cone_velocity(Vector3.UP, 0.0, context.cone_angle,
			randf_range(layer.speed.x, layer.speed.y), 0.0, 0.0)
	if motion_slot == 0:
		velocity += source_velocity * layer.inherit_velocity
	var roll := randf_range(layer.rotation_range.x, layer.rotation_range.y) * TAU if source_motion else randf() * TAU
	var jitter := randf_range(layer.size_scale_range.x, layer.size_scale_range.y) if source_motion else randf_range(0.67, 1.18)
	var base_width := randf_range(layer.width.x, layer.width.y)
	var base_length := base_width if layer.uniform_sprite_size else randf_range(layer.length.x, layer.length.y)
	var dimensions: Vector3 = context.dimensions
	var width_value := base_width * dimensions.x * jitter
	var length_value := base_length * dimensions.y * jitter
	var duration: float = maxf(randf_range(layer.particle_lifetime.x, layer.particle_lifetime.y), 0.001)
	var custom_alignment: Vector3 = context.custom_alignment
	var alignment := custom_alignment
	if layer.alignment_uses_initial_velocity and layer.alignment != Alignment.NORMAL_AND_TANGENT:
		alignment = _direction(velocity, custom_alignment)
	var particle_id := 0
	if layer.collision_kill and particle_id_provider.is_valid():
		particle_id = int(particle_id_provider.call(duration + delay))
	var host_tick: int = layer.get(&"source_rays_host_tick", -1)
	if collect_collisions and (layer.collision_events or layer.collision_kill):
		collision_samples.append({
			&"position": position, &"velocity": velocity, &"delay": delay, &"lifetime": duration,
			&"gravity": acceleration, &"drag": drag, &"layer": layer.emitter_name, &"particle_id": particle_id,
			&"radius": Vector2(width_value, length_value).length() * 0.5 * layer.collision_radius_scale,
		})
		if layer.has(&"radius_curve"):
			collision_samples[-1][&"radius_curve"] = layer.radius_curve
		if layer.get(&"contact_after_force_solve", false):
			collision_samples[-1][&"contact_after_force_solve"] = true
		if layer.get(&"use_source_collision_rays", false):
			collision_samples[-1][&"use_source_collision_rays"] = true
			if host_tick >= 0:
				collision_samples[-1][&"source_rays_host_tick"] = host_tick
			elif layer.source_ray_timing == SourceRayTiming.PREVIOUS_PHYSICS_FRAME:
				collision_samples[-1][&"source_rays_previous_physics_frame"] = true
		if layer.collision_replay_after > 0.0 and layer.stream_rate == 0.0 \
				and layer.stream_spacing == 0.0 and layer.loop_duration == 0.0 and layer.spawn_delay == 0.0:
			collision_samples[-1][&"collision_replay_after"] = layer.collision_replay_after
	var flags := int(layer.speed_stretch)
	if layer.uv_flip != UvFlip.NONE:
		# Bits 1 and 2 carry independent U and V flips. Color remains available for collision IDs.
		flags |= (randi() & int(layer.uv_flip)) << 1
	if layer.contact_spawn_mid_tick and not layer.contact_source.is_empty():
		flags |= 8
		delay += 1.0 / 120.0
	var simulation_acceleration := local_inverse * acceleration
	if layer.gravity_tracks_world and emitter.local_coords \
			and supports_source_attachment(layer, emitter.material_override, emitter.process_material):
		flags |= 16
		simulation_acceleration = acceleration
	if host_tick >= 0:
		flags |= 32
		motion_slot = host_tick & 65535
	# The fractional part carries a tangent's twist without modifying its normal.
	var sprite_data := float(flags) + float(context.packed_twist)
	if gpu_births != null:
		gpu_births.append_array([
			position.x, position.y, position.z, 0.0,
			velocity.x, velocity.y, velocity.z, drag,
			duration, 0.5 * Vector2(width_value, length_value).length() * layer.collision_radius_scale, 1.0, 0.0,
			acceleration.x, acceleration.y, acceleration.z, 0.0,
			roll, width_value, length_value, layer.opacity,
			float(layer.alignment), sprite_data, alignment.x, alignment.y,
			alignment.z, 0.0, 0.0, 0.0,
		])
		return
	var packed_flags := Basis(Vector3(delay, float(layer.alignment), sprite_data),
		local_inverse * alignment, simulation_acceleration)
	var spawn := Transform3D(packed_flags, emitter.to_local(position) if emitter.local_coords else position)
	var velocity_inverse: Basis = context.velocity_inverse
	emitter.emit_particle(spawn, velocity_inverse * velocity, Color(float(particle_id), drag, layer.opacity, length_value),
		Color(roll, float(motion_slot), width_value, duration), EMIT_FLAGS)

static func _cover(emitter: GPUParticles3D, point: Vector3) -> void:
	var margin := Vector3(28.0, 28.0, 28.0)
	var bounds := emitter.visibility_aabb
	if not bounds.has_point(point - margin) or not bounds.has_point(point + margin):
		emitter.visibility_aabb = bounds.expand(point - margin).expand(point + margin)



