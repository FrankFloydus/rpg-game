extends "res://combat/enemies/enemy.gd"

const DEFAULT_ENRAGE = preload("res://combat/effects/enrage.tres")

const DEFINITION := {
	"id": 0,
	"name": "Grave Thrall",
	"level": 1,
	"family": "thrall",
	"weapon": "knife",
	"skin": "9a8875",
	"cloth": "50403a",
	"accent": "a36643",
	"height": 1.83,
	"width": 0.29,
	"scale": 1.0,
	"part": "marrow",
	"behavior": {
		"positioning": "melee",
		"advance_speed": 0.87,
	},
}

@export_group("Enrage")
## Triggers Enrage when a surviving hit leaves the Thrall at or below this percentage of maximum life.
## Set to 0% to disable automatic Enrage.
@export_range(0.0, 100.0, 0.5, "suffix:%") var enrage_health_threshold := 30.0
## Shared attack-speed and damage bonuses. The Thrall keeps this effect until it dies.
@export var enrage_effect: EnrageEffectDefinition = DEFAULT_ENRAGE

var _health_enrage_triggered := false


func definition() -> Dictionary:
	return DEFINITION


func combat_traits() -> Array[Dictionary]:
	if enrage_health_threshold <= 0.0 or enrage_effect == null:
		return []
	return [{
		"name": enrage_effect.display_name,
		"icon": "enraged",
		"texture": enrage_effect.icon,
		"element": "",
		"tooltip": _enrage_tooltip(),
	}]


func _make_indicators() -> void:
	super._make_indicators()
	if _health_enrage_triggered:
		_update_enrage_indicator()


func on_surviving_damage() -> void:
	if _at_enrage_threshold():
		_apply_enrage(true)


func save_behavior_state() -> Dictionary:
	return {"enraged": true} if _health_enrage_triggered else {}


func restore_behavior_state(state: Dictionary) -> void:
	if bool(state.get("enraged", false)) or (health < max_health and _at_enrage_threshold()):
		_apply_enrage(false)


func _at_enrage_threshold() -> bool:
	return (
		enrage_health_threshold > 0.0
		and health > 0.0
		and health <= max_health * (enrage_health_threshold / 100.0)
	)


func _apply_enrage(log_status: bool) -> void:
	if _health_enrage_triggered or enrage_effect == null:
		return
	if not receive_combat_effect(enrage_effect, INF, 0.0, self, {}):
		return
	_health_enrage_triggered = true
	_update_enrage_indicator()
	if log_status:
		_notify_behavior_changed()
		combat_event.emit({
			"kind": &"status", "side": &"enemy", "actor": display_name, "target": display_name,
			"ability_id": enrage_effect.id, "ability": enrage_effect.display_name,
			"description": _enrage_tooltip(), "detail": "Until defeated",
		})


func _enrage_tooltip() -> String:
	return "At or below %s%% life, gains %s%% attack speed and %s%% damage. Lasts until defeated." % [
		String.num(enrage_health_threshold, 2).trim_suffix(".0"),
		String.num(enrage_effect.attack_speed_bonus_percent, 2).trim_suffix(".0"),
		String.num(enrage_effect.damage_bonus_percent, 2).trim_suffix(".0"),
	]


func _update_enrage_indicator() -> void:
	if is_instance_valid(_title):
		_title.text = _title.text.insert(display_name.length(), " · Enraged")
