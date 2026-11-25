extends Node3D
## An intermittent lava basin with a dry perimeter and a warning before damage starts.

enum Phase { DORMANT, WARNING, MOLTEN }

const Telegraph := preload("res://combat/effects/enemy_telegraph.gd")
const GameServices := preload("res://systems/game_services.gd")
const TelegraphRules := preload("res://data/telegraph_rules.tres")
const RETURN_GRACE := 1.8
const APPROACH_DISTANCE := 4.0
const CONTACT_HEIGHT := 0.33
const EMISSION_FADE_SECONDS := 0.62
const HIT := {
	"id": &"lava_floor", "name": "Lava Floor", "actor": "Dungeon", "side": &"world",
	"description": "A lava basin deals Fire damage over time while you stand on its molten surface.",
}

## Safe time between molten phases while the chamber is occupied.
@export_range(2.0, 30.0, 0.1, "suffix:s") var dormant_seconds := 8.0
## Minimum warning time. A wider basin can extend it to fit a normal walking escape.
@export_range(1.0, 12.0, 0.1, "suffix:s") var warning_seconds := 2.15
## Duration of the molten and damaging phase.
@export_range(1.0, 12.0, 0.1, "suffix:s") var molten_seconds := 4.2
## Seconds between Fire damage checks while the basin is molten.
@export_range(0.25, 2.0, 0.05, "suffix:s") var tick_seconds := 0.65
## Fraction of maximum Life dealt per tick before Fire Resistance.
@export_range(0.01, 0.20, 0.005) var tick_life_fraction := 0.065
## Minimum raw Fire damage per tick.
@export_range(0.0, 20.0, 0.1) var minimum_tick_damage := 2.0

var _player: Node3D
var _extent := Vector2.ZERO
var _phase := Phase.DORMANT
var _elapsed := 0.0
var _warning_duration := 0.0
var _dormant_duration := RETURN_GRACE
var _next_tick := 0.0
var _active := true
var _warning: MeshInstance3D
var _surface: MeshInstance3D
var _sparks: GPUParticles3D
var _glow: OmniLight3D
var _sound: AudioStreamPlayer3D


## Extent is the centered surface's full X and Z dimensions in meters.
func configure(player: Node3D, extent: Vector2) -> void:
	_player = player
	_extent = extent
	if is_inside_tree():
		_apply_extent()
		_reset(RETURN_GRACE)


func _ready() -> void:
	_surface = $Surface
	_sparks = $Sparks
	_glow = $Glow
	_sound = $Sound
	_warning = Telegraph.make_node()
	add_child(_warning)
	_apply_extent()
	_reset(RETURN_GRACE)


func _enter_tree() -> void:
	if _warning != null:
		_reset(RETURN_GRACE)


func _exit_tree() -> void:
	if _sound != null:
		_sound.stop()


func set_active(wants_active: bool) -> void:
	_active = wants_active
	if is_node_ready():
		_reset(RETURN_GRACE)


func _apply_extent() -> void:
	var usable := _extent.x > 0.0 and _extent.y > 0.0
	_surface.visible = usable
	if not usable:
		return
	_surface.scale = Vector3(_extent.x, 1.0, _extent.y)
	_surface.set_instance_shader_parameter(&"surface_size", _extent)
	var spread: Vector2 = _extent * 0.48
	var motion := _sparks.process_material as ParticleProcessMaterial
	motion.emission_box_extents = Vector3(spread.x, 0.025, spread.y)
	_sparks.visibility_aabb = AABB(Vector3(-spread.x - 0.8, -0.1, -spread.y - 0.8),
		Vector3(spread.x * 2.0 + 1.6, 2.1, spread.y * 2.0 + 1.6))
	_glow.omni_range = _extent.length() * 0.69 + 0.9


func _reset(rest_duration: float) -> void:
	_phase = Phase.DORMANT
	_elapsed = 0.0
	_dormant_duration = rest_duration
	_set_heat(0.0)
	_warning.hide()
	_sparks.emitting = false
	_glow.hide()
	_sound.stop()
	set_physics_process(_active and _extent.x > 0.0 and _extent.y > 0.0)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_player) or not _player.is_inside_tree() \
			or _player.get("gameplay_enabled") == false or _player.get("combat_enabled") == false:
		return
	var point := to_local(_player.global_position)
	_elapsed += delta
	match _phase:
		Phase.DORMANT:
			if _elapsed >= _dormant_duration and absf(point.y) < 1.2 and _near_surface(point):
				_begin_warning()
		Phase.WARNING:
			var fraction := clampf(_elapsed / _warning_duration, 0.0, 1.0)
			Telegraph.set_progress(_warning, fraction)
			_set_heat(fraction * 0.48)
			if fraction >= 1.0:
				_begin_molten()
				_tick(point)
		Phase.MOLTEN:
			if _elapsed >= molten_seconds:
				_reset(dormant_seconds)
				return
			if _elapsed >= _next_tick:
				_tick(point)
			_set_heat(smoothstep(0.0, EMISSION_FADE_SECONDS, molten_seconds - _elapsed))


func _begin_warning() -> void:
	_phase = Phase.WARNING
	_elapsed = 0.0
	var half := _extent * 0.5
	_warning_duration = TelegraphRules.warning_seconds(warning_seconds, minf(half.x, half.y), _player)
	var back_edge := to_global(Vector3(0.0, 0.014, half.y))
	Telegraph.present(_warning, {"shape": "lane", "reach": _extent.y, "width": half.x},
		back_edge, -global_basis.z)
	_glow.show()
	_play_cue(&"ember_vent_warning")


func _begin_molten() -> void:
	_phase = Phase.MOLTEN
	_elapsed = 0.0
	_next_tick = 0.0
	_warning.hide()
	_set_heat(1.0)
	_sparks.emitting = true
	_play_cue(&"ember_vent_burst")


func _near_surface(point: Vector3) -> bool:
	var edge := Vector2(absf(point.x), absf(point.z)) - _extent * 0.5
	return edge.x <= APPROACH_DISTANCE and edge.y <= APPROACH_DISTANCE


func _tick(point: Vector3) -> void:
	_next_tick += tick_seconds
	if point.y < -0.22 or point.y > CONTACT_HEIGHT \
			or absf(point.x) >= _extent.x * 0.5 or absf(point.z) >= _extent.y * 0.5:
		return
	var maximum := float(_player.get("stats").get("max_health", 1.0))
	_player.receive_ground_damage(maxf(minimum_tick_damage, maximum * tick_life_fraction), "fire", self, HIT)


func _set_heat(value: float) -> void:
	_surface.set_instance_shader_parameter(&"heat", value)
	_glow.light_energy = 0.23 + 1.65 * value * value


func _play_cue(event: StringName) -> void:
	var audio := GameServices.audio_for(self)
	if audio != null:
		audio.play_on(event, _sound, -2.0)
