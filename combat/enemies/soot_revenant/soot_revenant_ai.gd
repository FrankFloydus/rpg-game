extends "res://combat/enemies/ranged_enemy.gd"

const GroundCast := preload("res://combat/effects/ground_cast.gd")
const LightningBeam := preload("res://combat/effects/soot_conduit_beam.tscn")
const BeamGeometry := preload("res://combat/effects/soot_conduit_beam.gd")
const CONDUIT := "soot_conduit"
const CHANNEL_HOLD_PHASE := 0.64

const DEFINITION := {
	"id": 14,
	"name": "Soot Revenant",
	"level": 4,
	"family": "revenant",
	"weapon": "staff",
	"skin": "7a707c",
	"cloth": "363146",
	"accent": "ac8dda",
	"height": 2.06,
	"width": 0.32,
	"scale": 1.07,
	"part": "black_ichor",
	"ranged": true,
	"additional_moves_level": 1,
}

var _conduit: Node3D


func definition() -> Dictionary:
	return DEFINITION


func _is_projectile_attack() -> bool:
	return _move_id == CONDUIT or super._is_projectile_attack()


func _begin_attack(direction: Vector3) -> void:
	if _move_id == CONDUIT:
		_profile = _profile.duplicate()
		var reach := float(_profile.reach) * _attack_scale()
		var width := float(_profile.width) * _attack_scale()
		var open := GroundCast.open_length(self, global_position, direction, reach, width, BeamGeometry.BEAM_HEIGHT)
		_profile.reach = maxf(0.02, open / _attack_scale())
	super._begin_attack(direction)


func _release_attack() -> bool:
	if _move_id != CONDUIT:
		return super._release_attack()
	_attack_warning.hide()
	if not _commit_attack_cost(_cast_definition()):
		return false
	if float(_warning_footprint.reach) <= 0.10:
		_finish_attack_cast(&"cast_cancel", "Beam obstructed")
		return false
	_attack_phase = AttackPhase.AREA_TRACE
	_strike_time = 0.0
	_has_move_goal = false
	_planned_velocity = Vector3.ZERO
	_conduit = LightningBeam.instantiate()
	add_child(_conduit)
	_conduit.launch(_floor_warning_origin(), _windup_toward, _warning_footprint,
		_attack_ability, _attack_damage(), _player, _profile, _ability_trace)
	return true


func _advance_area_trace() -> bool:
	if _move_id != CONDUIT:
		return super._advance_area_trace()
	if is_instance_valid(_conduit) and not _conduit.is_queued_for_deletion():
		return false
	_strike_time = STRIKE_CLIP_SECONDS * CHANNEL_HOLD_PHASE
	_finish_attack_cast(&"cast_end", "Channel ended")
	return true


func _strike_progress() -> float:
	var phase := super._strike_progress()
	return minf(phase, CHANNEL_HOLD_PHASE) if is_instance_valid(_conduit) else phase


func _reset_attack() -> void:
	if is_instance_valid(_conduit):
		_conduit.set_physics_process(false)
		_conduit.hide()
		_conduit.queue_free()
	_conduit = null
	super._reset_attack()
