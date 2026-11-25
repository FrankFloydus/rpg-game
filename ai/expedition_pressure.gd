extends Node
## Paces attacks from the expedition's fixed roster after bursts of combat.

const UPDATE_INTERVAL := 0.25

var _director: AIHordeDirector
var _player: Node3D
var _elapsed := 0.0


func configure(player: Node3D, rating: int) -> void:
	assert(_director == null and is_instance_valid(player))
	_player = player
	_director = AIHordeDirector.new()
	_director.name = "HordeDirector"
	set_encounter_rating(rating)
	_director.fade_pressure = 9.0
	_director.pressure_decay = 13.5
	_director.pressure_grace = 0.75
	_director.sustain_duration = 1.75
	_director.relax_duration = 2.60
	_director.register_pressure_target(player)
	add_child(_director)


func set_encounter_rating(rating: int) -> void:
	_director.peak_pressure = 24.0 + clampf(float(rating - 1) * 0.75, 0.0, 6.0)


func record_pressure(amount: float) -> void:
	if is_instance_valid(_director) and is_instance_valid(_player):
		_director.record_target_pressure(_player, amount)


func attack_cost_multiplier() -> float:
	if is_instance_valid(_director):
		match _director.get_state():
			&"fade": return 1.35
			&"relax": return 1.65
	return 1.0


func _physics_process(delta: float) -> void:
	if not is_instance_valid(_director):
		return
	_elapsed += delta
	if _elapsed >= UPDATE_INTERVAL:
		# The layout owns the finite roster. Supply no reinforcement gates.
		_director.update_encounter(_elapsed, {}, [])
		_elapsed = 0.0
