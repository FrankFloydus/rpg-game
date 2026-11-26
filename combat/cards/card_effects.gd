extends RefCounted
## Runtime durations use simulation time, including the card hand's slow motion.

signal display_changed

const Catalog := preload("res://data/card_catalog.gd")

var _strikes := 0
var _strike_bonus := 0.0
var _strike_time := 0.0
var _timed_bonus := 0.0
var _timed_duration := 0.0
var _protection := 0.0
var _protection_time := 0.0


func apply_buffs(card: Dictionary) -> void:
	if card.has("strikes"):
		_strikes = card.strikes
		_strike_bonus = card.strike_bonus
		_strike_time = card.strike_time
	if card.has("timed_bonus"):
		_timed_bonus = card.timed_bonus
		_timed_duration = card.timed_duration
	if card.has("protection"):
		_protection = card.protection
		_protection_time = card.protection_time
	if card.has("strikes") or card.has("timed_bonus") or card.has("protection"):
		display_changed.emit()


func advance(delta: float) -> void:
	var previous := _display_seconds()
	_strike_time = maxf(0.0, _strike_time - delta)
	_timed_duration = maxf(0.0, _timed_duration - delta)
	_protection_time = maxf(0.0, _protection_time - delta)
	if previous != _display_seconds():
		display_changed.emit()


func attack_multiplier() -> float:
	var oath := _strike_bonus if _strike_time > 0.0 and _strikes > 0 else 0.0
	var benediction := _timed_bonus if _timed_duration > 0.0 else 0.0
	return 1.0 + oath + benediction


func weapon_landed() -> void:
	if _strike_time > 0.0 and _strikes > 0:
		_strikes -= 1
		display_changed.emit()


func incoming_multiplier() -> float:
	return 1.0 - _protection if _protection_time > 0.0 else 1.0


func active_statuses() -> Array[Dictionary]:
	var active: Array[Dictionary] = []
	if _strike_time > 0.0 and _strikes > 0:
		active.append(_status("iron_oath", _strike_time, _strikes))
	if _timed_duration > 0.0:
		active.append(_status("sable_benediction", _timed_duration))
	if _protection_time > 0.0:
		active.append(_status("lantern_ward", _protection_time))
	return active


func _display_seconds() -> Vector3i:
	return Vector3i(ceili(_strike_time) if _strikes > 0 else 0, ceili(_timed_duration), ceili(_protection_time))


static func _status(card_id: String, remaining: float, charges := -1) -> Dictionary:
	var card: Dictionary = Catalog.CARDS[card_id]
	return {"id": StringName(card_id), "name": card.name, "description": card.description,
		"card_art": int(card.art), "beneficial": true, "remaining": remaining, "charges": charges}


func snapshot() -> Dictionary:
	return {"strikes": _strikes, "strike_time": _strike_time,
		"benediction": _timed_duration, "ward": _protection_time}


func restore(saved: Dictionary) -> void:
	_strikes = clampi(int(saved.get("strikes", 0)), 0, 3)
	_strike_time = clampf(float(saved.get("strike_time", 0.0)), 0.0, 20.0)
	_timed_duration = clampf(float(saved.get("benediction", 0.0)), 0.0, 12.0)
	_protection_time = clampf(float(saved.get("ward", 0.0)), 0.0, 10.0)
	_strike_bonus = Catalog.CARDS.iron_oath.strike_bonus
	_timed_bonus = Catalog.CARDS.sable_benediction.timed_bonus
	_protection = Catalog.CARDS.lantern_ward.protection
	display_changed.emit()
