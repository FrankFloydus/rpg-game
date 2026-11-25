extends RefCounted
## State for reactive defensive equipment. Conditions and recovery are evaluated at the hit.

const Rules := preload("res://data/defensive_legendary_rules.tres")
const COUNTERWEIGHT := "counterweight_gate"
const STILL_BELL := "still_bell"
const STONEWAKE := "stonewake_spurs"
const BUTTRESS := "buttress_hands"

var _active: Dictionary[String, float] = {}
var _cooldowns: Dictionary[String, float] = {}


func on_block(effects: Array[String], stamina_fraction: float, exhausted: bool, melee: bool) -> bool:
	if exhausted:
		return _active.erase(COUNTERWEIGHT)
	var changed := false
	if _available(effects, COUNTERWEIGHT):
		_active[COUNTERWEIGHT] = Rules.counterweight_release_window
		changed = true
	if melee and stamina_fraction * 100.0 >= Rules.buttress_stamina_threshold and _available(effects, BUTTRESS):
		_active[BUTTRESS] = Rules.buttress_duration
		_cooldowns[BUTTRESS] = Rules.buttress_cooldown
		changed = true
	return changed


func release_counterweight(manual: bool, equipped: bool) -> float:
	if not _active.erase(COUNTERWEIGHT) or not manual or not equipped:
		return 0.0
	_cooldowns[COUNTERWEIGHT] = Rules.counterweight_cooldown
	return Rules.counterweight_refund


func has_counterweight() -> bool:
	return _active.has(COUNTERWEIGHT)


func on_life_hit(effects: Array[String]) -> bool:
	if not _available(effects, STONEWAKE):
		return false
	_active[STONEWAKE] = Rules.stonewake_duration
	_cooldowns[STONEWAKE] = Rules.stonewake_cooldown
	return true


func movement_multiplier() -> float:
	return 1.0 + Rules.stonewake_speed_bonus * 0.01 if _active.has(STONEWAKE) else 1.0


func stun_duration(effects: Array[String], duration: float) -> float:
	if _active.has(BUTTRESS):
		duration *= 1.0 - Rules.buttress_stun_reduction * 0.01
	if _available(effects, STILL_BELL) and duration > Rules.still_bell_minimum and Rules.still_bell_reduction > 0.0:
		_cooldowns[STILL_BELL] = Rules.still_bell_cooldown
		duration = maxf(Rules.still_bell_minimum, duration * (1.0 - Rules.still_bell_reduction * 0.01))
	return duration


func advance(delta: float) -> bool:
	var changed := false
	for perk: String in _active.keys():
		var before := _active[perk]
		var after := maxf(0.0, before - delta)
		changed = changed or ceili(before) != ceili(after)
		if after > 0.0:
			_active[perk] = after
		else:
			_active.erase(perk)
	for perk: String in _cooldowns.keys():
		var before := _cooldowns[perk]
		var after := maxf(0.0, before - delta)
		if perk == STILL_BELL:
			changed = changed or ceili(before) != ceili(after)
		if after > 0.0:
			_cooldowns[perk] = after
		else:
			_cooldowns.erase(perk)
	return changed


func clear() -> bool:
	var changed := not _active.is_empty() or _cooldowns.has(STILL_BELL)
	_active.clear()
	_cooldowns.clear()
	return changed


func update_equipped(effects: Array[String]) -> bool:
	var lost_active := false
	for perk: String in _active.keys():
		if not effects.has(perk):
			_active.erase(perk)
			lost_active = true
	return lost_active or _cooldowns.has(STILL_BELL)


func is_still_bell_recovering() -> bool:
	return _cooldowns.has(STILL_BELL)


func append_statuses(statuses: Array[Dictionary], effects: Array[String]) -> void:
	_append_status(statuses, COUNTERWEIGHT, "Counterweight Ready", _active.get(COUNTERWEIGHT, 0.0),
		Rules.counterweight_icon, "Release guard to restore %s Stamina." % String.num(Rules.counterweight_refund, 2))
	_append_status(statuses, STONEWAKE, "Stonewake", _active.get(STONEWAKE, 0.0),
		Rules.stonewake_icon, "Move %s%% faster on land." % String.num(Rules.stonewake_speed_bonus, 2))
	_append_status(statuses, BUTTRESS, "Buttress", _active.get(BUTTRESS, 0.0),
		Rules.buttress_icon, "%s%% shorter incoming stuns." % String.num(Rules.buttress_stun_reduction, 2))
	if effects.has(STILL_BELL):
		_append_status(statuses, STILL_BELL, "Still Bell Recovering", _cooldowns.get(STILL_BELL, 0.0),
			Rules.still_bell_icon, "The Crown can shorten another stun when this timer expires.")


func _available(effects: Array[String], key: String) -> bool:
	return effects.has(key) and not _cooldowns.has(key)


func _append_status(statuses: Array[Dictionary], id: String, name: String, time: float, icon: Texture2D,
		description: String) -> void:
	if time > 0.0:
		statuses.append({"id": StringName(id), "name": name, "remaining": time, "icon": icon,
			"description": description, "beneficial": true})
