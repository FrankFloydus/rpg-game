extends RefCounted
## Tracks per-target light chains and per-item rearm times for the four legendary melee weapons.

const Rules := preload("res://data/weapon_legendary_rules.tres")
const Roles := preload("res://combat/weapons/weapon_roles.gd")
const LATCHKNIFE := &"latchknife"
const STILLSTONE := &"stillstone"
const GRAVEGATE := &"gravegate"
const UNMATCHED_PAIR := &"unmatched_pair"
const THREE_LIGHT_STEPS := 0b111

class Latch:
	var steps := 0
	var until := 0.0
	var rearm_at := 0.0

var main_effect: StringName
var off_effect: StringName
var has_pair := false
var _now := 0.0
var _latches: Dictionary[int, Latch] = {}
var _last_prune := 0.0
var _rearm_at: Dictionary[StringName, float] = {}
var _pair_step := 0
var _pair_until := 0.0


func configure(main: StringName, off: StringName, dual_wield: bool) -> void:
	var paired := dual_wield and (main == UNMATCHED_PAIR or off == UNMATCHED_PAIR)
	if main != main_effect or off != off_effect or has_pair != paired:
		reset_sequences()
	main_effect = main
	off_effect = off
	has_pair = paired


func reset_sequences() -> void:
	_pair_step = 0
	for mark: Latch in _latches.values():
		mark.steps = 0


func tick(delta: float) -> void:
	_now += delta
	if _latches.is_empty() or _now < _last_prune + 1.0:
		return
	_last_prune = _now
	for id: int in _latches.keys():
		var mark := _latches[id]
		if not is_instance_id_valid(id) or (_now > mark.until and _now >= mark.rearm_at):
			_latches.erase(id)


func effect_for_hand(offhand: bool) -> StringName:
	return off_effect if offhand else main_effect


func latch_is_ready(target: Node3D) -> bool:
	var mark := _latches.get(target.get_instance_id()) as Latch
	return mark != null and mark.steps == THREE_LIGHT_STEPS and _now <= mark.until


func add_latch_step(target: Node3D, chain_step: int) -> bool:
	if chain_step < 1 or chain_step > 3:
		return false
	var id := target.get_instance_id()
	var mark := _latches.get(id) as Latch
	if mark == null:
		mark = Latch.new()
		_latches[id] = mark
	if _now < mark.rearm_at:
		return false
	if _now > mark.until:
		mark.steps = 0
	var bit := 1 << (chain_step - 1)
	if mark.steps & bit:
		return false
	if mark.steps == 0:
		mark.until = _now + Rules.latch_window
	mark.steps |= bit
	return mark.steps == THREE_LIGHT_STEPS


func consume_latch(target: Node3D) -> void:
	var mark := _latches[target.get_instance_id()]
	mark.steps = 0
	mark.rearm_at = _now + Rules.latch_rearm


func ready(effect: StringName) -> bool:
	return _now >= _rearm_at.get(effect, 0.0)


func spend(effect: StringName, duration: float) -> void:
	_rearm_at[effect] = _now + duration


func record_light_hand(offhand: bool) -> void:
	if not has_pair or not ready(UNMATCHED_PAIR):
		return
	if not offhand:
		_pair_step = 1
		_pair_until = _now + Rules.pair_window
	elif _pair_step == 1 and _now <= _pair_until:
		_pair_step = 2


func record_crossover_hand(offhand: bool, hands: StringName, strike: Dictionary) -> bool:
	if (not has_pair or _pair_step != 2 or _now > _pair_until or hands != Roles.BOTH_HANDS
			or not ready(UNMATCHED_PAIR)):
		return false
	var hand_mask := int(strike.get("legendary_crossover_hands", 0))
	hand_mask |= 2 if offhand else 1
	strike["legendary_crossover_hands"] = hand_mask
	return hand_mask == 3


func consume_crossover() -> void:
	_pair_step = 0
	spend(UNMATCHED_PAIR, Rules.pair_rearm)
