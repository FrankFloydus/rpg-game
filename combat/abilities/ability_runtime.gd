extends RefCounted
## Tracks when each ability becomes available to one caster.


var _time := 0.0
var _ready_at: Dictionary[StringName, float] = {}


func advance(delta: float) -> void:
	_time += delta


func remaining(ability: AbilityDefinition) -> float:
	if ability == null:
		return 0.0
	return maxf(0.0, _ready_at.get(ability.id, 0.0) - _time)


func can_start(ability: AbilityDefinition, available_mana: float) -> bool:
	return ability != null and not ability.id.is_empty() \
		and available_mana >= ability.mana_cost and remaining(ability) <= 0.000001


func try_commit(ability: AbilityDefinition, available_mana: float, spend_mana: Callable,
		cooldown_seconds_override := -1.0) -> bool:
	if not can_start(ability, available_mana):
		return false
	if ability.mana_cost > 0.0 and not spend_mana.is_valid():
		return false
	var seconds := ability.cooldown if cooldown_seconds_override < 0.0 else cooldown_seconds_override
	if seconds > 0.0:
		_ready_at[ability.id] = _time + seconds
	if ability.mana_cost > 0.0:
		spend_mana.call(ability.mana_cost)
	return true


func clear() -> void:
	_ready_at.clear()
	_time = 0.0
