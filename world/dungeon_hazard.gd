extends Node3D
## A floor fixture gives a warning before a short, spatially bounded burst.

signal warning_started(kind: String, position: Vector3)
signal fired(kind: String, position: Vector3)

enum Phase { RESTING, WARNING, FIRING }

const Catalogue := preload("res://assets/audio/sound_catalogue.tres")
const Telegraph := preload("res://combat/effects/enemy_telegraph.gd")
const TelegraphRules := preload("res://data/telegraph_rules.tres")

const PROFILES := {
	"spike_plate": {
		"name": "Spike Plate", "description": "A floor plate lifts a cluster of spikes, dealing Physical damage on contact.",
		"color": Color("#f8bd76"), "metal": Color("#403839"), "damage_type": "physical",
		"status": "", "damage": 3.5, "radius": 1.21, "warning": 1.10, "burst": 0.36, "rearm": 5.10,
	},
	"ember_vent": {
		"name": "Ember Vent", "description": "The grate releases a burst of flame that deals Fire damage and can Burn you.",
		"color": Color("#ff9458"), "metal": Color("#4d332e"), "damage_type": "fire",
		"status": "burning", "damage": 2.75, "radius": 1.22, "warning": 1.23, "burst": 0.58, "rearm": 5.40,
	},
	"miasma_vent": {
		"name": "Miasma Vent", "description": "The grate releases a cloud of miasma that deals Poison damage and can Poison you.",
		"color": Color("#a4dc96"), "metal": Color("#354440"), "damage_type": "poison",
		"status": "poisoned", "damage": 2.75, "radius": 1.29, "warning": 1.35, "burst": 0.75, "rearm": 5.70,
	},
}

const TRIGGER_DISTANCE := 4.30
const RETURN_GRACE := 1.20
const WARNING_COLOR := Color("#f65d44")
const CHALLENGE_HALF_WIDTH := 1.63
const FIXTURE_EDGE := 2.108
const CHALLENGE_WARNING_LIFT := 0.075

var kind := "spike_plate"
var _player: Node3D
var _profile: Dictionary = {}
var _active := true
var _phase := Phase.RESTING
var _elapsed := 0.0
var _remaining := 0.0
var _offset := 0.0
var _radius := 1.2
var _footprint: Dictionary
var _challenge := false
var _warning_seconds := 0.0
var _damage := 0.0
var _contact_tested := false
var _aperture_material: StandardMaterial3D
var _warning: MeshInstance3D
var _effects: Array[Node3D] = []
var _particles: Array[GPUParticles3D] = []
var _light: OmniLight3D
var _sound: AudioStreamPlayer3D
var _warning_stream: AudioStream
var _burst_stream: AudioStream
var _warning_gain := 0.0
var _burst_gain := 0.0


func configure(hazard_kind: String, depth: int, player: Node3D, phase_offset := 0.0,
		placement: Dictionary = {}) -> void:
	assert(_profile.is_empty(), "Configure a new floor hazard only once.")
	kind = hazard_kind if PROFILES.has(hazard_kind) else "spike_plate"
	_profile = PROFILES[kind]
	_player = player
	_offset = clampf(phase_offset, 0.0, 1.40)
	_radius = float(_profile["radius"])
	_footprint = {"shape": "disc", "reach": _radius}
	_challenge = bool(placement.get("challenge", false))
	if _challenge:
		var axis: Vector2i = placement.get("heading", Vector2i.RIGHT)
		rotation.y = atan2(-float(axis.x), -float(axis.y))
		_footprint = {"shape": "lane", "width": CHALLENGE_HALF_WIDTH,
			"reach": clampf(float(placement.get("reach", 1.35)), 0.75, 2.50)}
	_damage = float(_profile["damage"]) + float(clampi(depth - 1, 0, 9)) * 0.30
	_bind_fixture()
	_reset()
	set_physics_process(_active)


func set_active(active: bool) -> void:
	if _active == active:
		return
	_active = active
	if _profile.is_empty():
		return
	_reset()
	set_physics_process(active)


func _enter_tree() -> void:
	# A return portal can place the player back directly on a grate.
	if not _profile.is_empty():
		_reset()
		set_physics_process(_active)


func _exit_tree() -> void:
	if _sound != null:
		_sound.stop()
		_sound.stream = null


func _reset() -> void:
	_phase = Phase.RESTING
	_elapsed = 0.0
	_remaining = RETURN_GRACE + _offset
	_contact_tested = false
	_aperture_material.emission_energy_multiplier = 0.0
	_warning.hide()
	for effect in _effects:
		effect.hide()
	for emitter: GPUParticles3D in _particles:
		emitter.emitting = false
	_light.hide()
	if _sound != null:
		_sound.stop()


func _physics_process(delta: float) -> void:
	if not _active or _profile.is_empty() or not is_instance_valid(_player) or not _player.is_inside_tree():
		return
	if _player.get("gameplay_enabled") == false or _player.get("combat_enabled") == false:
		return
	var offset := _player.global_position - global_position
	var planar_distance := Vector2(offset.x, offset.z).length_squared()
	var near_floor := absf(offset.y) <= 1.20
	match _phase:
		Phase.RESTING:
			_remaining = maxf(0.0, _remaining - delta)
			if (_remaining <= 0.0 and near_floor and planar_distance <= TRIGGER_DISTANCE * TRIGGER_DISTANCE
					and (not _challenge or _approach_visible())):
				_warn()
		Phase.WARNING:
			_elapsed += delta
			var progress := clampf(_elapsed / _warning_seconds, 0.0, 1.0)
			Telegraph.set_progress(_warning, progress)
			_aperture_material.emission_energy_multiplier = lerpf(0.38, 2.60, progress)
			_light.light_energy = 0.17 + 0.65 * progress
			if progress >= 1.0:
				_discharge()
				_check_contact(near_floor, planar_distance)
		Phase.FIRING:
			_elapsed += delta
			var progress := clampf(_elapsed / float(_profile["burst"]), 0.0, 1.0)
			if progress >= 1.0:
				_finish_burst()
				return
			_check_contact(near_floor, planar_distance)
			_aperture_material.emission_energy_multiplier = lerpf(1.65, 0.15, progress)
			_light.light_energy = lerpf(2.1, 0.25, progress)
			if _particles.is_empty():
				for effect in _effects:
					effect.position.y = lerpf(0.02, -0.48, smoothstep(0.48, 1.0, progress))


func _approach_visible() -> bool:
	var height := Vector3.UP * 0.38
	var query := PhysicsRayQueryParameters3D.create(_player.global_position + height, global_position + height, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _footprint_direction() -> Vector3:
	return -global_basis.z.normalized()


func _footprint_origin() -> Vector3:
	return (global_position - _footprint_direction() * float(_footprint.reach) * 0.5
		if _challenge else global_position)


func _warn() -> void:
	_phase = Phase.WARNING
	_elapsed = 0.0
	_warning_seconds = TelegraphRules.warning_seconds(float(_profile["warning"]), Telegraph.escape_distance(_footprint), _player)
	var warning_origin := _footprint_origin()
	if _challenge:
		warning_origin.y += CHALLENGE_WARNING_LIFT
	Telegraph.present(_warning, _footprint, warning_origin, _footprint_direction())
	_aperture_material.emission = WARNING_COLOR
	_aperture_material.emission_energy_multiplier = 0.38
	_light.light_color = WARNING_COLOR
	_light.light_energy = 0.17
	_light.show()
	_play_cue(true)
	warning_started.emit(kind, global_position)


func _discharge() -> void:
	_phase = Phase.FIRING
	_elapsed = 0.0
	_contact_tested = false
	_warning.hide()
	var hue: Color = _profile["color"]
	_aperture_material.emission = hue
	_aperture_material.emission_energy_multiplier = 1.65
	_light.light_color = hue
	_light.light_energy = 2.1
	for effect in _effects:
		effect.position.y = 0.02
		effect.show()
	for emitter: GPUParticles3D in _particles:
		emitter.restart()
		emitter.emitting = true
	_play_cue(false)
	fired.emit(kind, global_position)


func _check_contact(near_floor: bool, planar_distance: float) -> void:
	if not _active or _phase != Phase.FIRING or _contact_tested or not near_floor:
		return
	var inside := (Telegraph.contains(_footprint, _footprint_origin(), _footprint_direction(), _player.global_position)
		if _challenge else planar_distance <= _radius * _radius)
	if not inside:
		return
	_contact_tested = true
	_player.receive_enemy_hit(_damage, _profile["damage_type"], _profile["status"], self, {
		"name": _profile["name"], "description": _profile["description"], "actor": "Dungeon", "side": &"world",
		"unblockable": true,
	})


func _finish_burst() -> void:
	_phase = Phase.RESTING
	_remaining = float(_profile["rearm"])
	_aperture_material.emission_energy_multiplier = 0.0
	# Spikes retract at the end of damage. GPU smoke and sparks can finish fading in place.
	if _particles.is_empty():
		for effect in _effects:
			effect.hide()
	for emitter: GPUParticles3D in _particles:
		emitter.emitting = false
	_light.hide()


func _bind_fixture() -> void:
	_aperture_material = $Apertures.material_override as StandardMaterial3D
	_warning = Telegraph.make_node()
	add_child(_warning)
	_effects.append($Discharge)
	if _challenge:
		_mount_challenge_fixtures()
	_light = $Flash
	for effect in _effects:
		for child: Node in effect.get_children():
			if child is GPUParticles3D:
				_particles.append(child)
	if DisplayServer.get_name() == "headless" and AudioServer.get_driver_name() == "Dummy":
		return
	_sound = $Sound
	var warning := Catalogue.sound_for(StringName(kind + "_warning"))
	var burst := Catalogue.sound_for(StringName(kind + "_burst"))
	if warning != null:
		_warning_stream = warning.make_one_shot()
		_warning_gain = warning.volume_db
	if burst != null:
		_burst_stream = burst.make_one_shot()
		_burst_gain = burst.volume_db


func _mount_challenge_fixtures() -> void:
	var spacing := CHALLENGE_HALF_WIDTH
	var fixture_scale := Vector3((spacing - 0.025) / FIXTURE_EDGE, 1.0, float(_footprint.reach) / FIXTURE_EDGE)
	for source: Node3D in [$Fixture, $Apertures, $Discharge]:
		var second := source.duplicate() as Node3D
		source.position.x = -spacing * 0.5
		second.position.x = spacing * 0.5
		source.scale *= fixture_scale
		second.scale *= fixture_scale
		add_child(second)
		if source == $Discharge:
			_effects.append(second)
		elif source == $Apertures:
			second.material_override = _aperture_material


func _play_cue(alert: bool) -> void:
	var stream := _warning_stream if alert else _burst_stream
	if _sound == null or stream == null:
		return
	_sound.stream = stream
	_sound.volume_db = _warning_gain if alert else _burst_gain
	_sound.play()
