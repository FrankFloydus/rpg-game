extends RefCounted
## Tracks deterministic stun buildup, loss of control and recovery immunity for one actor.

const DEFAULT_THRESHOLD := 100.0
const ENEMY_BASE_DURATION := 0.55
const ENEMY_MAX_DURATION := 1.10
const PLAYER_BASE_DURATION := 0.30
const PLAYER_MAX_DURATION := 0.65
const DECAY_DELAY := 2.0
const DECAY_PER_SECOND := 30.0
const IMMUNITY_DURATION := 2.0

var buildup := 0.0
var remaining := 0.0
var _delay := 0.0
var _immunity := 0.0


func add_impact(amount: float, threshold: float, stun_power: float,
		base_duration: float, max_duration: float) -> float:
	if amount <= 0.0 or threshold <= 0.0 or is_stunned() or _immunity > 0.0:
		return 0.0
	buildup += amount
	_delay = DECAY_DELAY
	if buildup < threshold:
		return 0.0
	return start(clampf(base_duration * (1.0 + stun_power / 100.0), 0.0, max_duration))


func start(duration: float) -> float:
	if duration <= 0.0 or is_stunned() or _immunity > 0.0:
		return 0.0
	buildup = 0.0
	_delay = 0.0
	remaining = duration
	_immunity = IMMUNITY_DURATION
	return remaining


func advance(delta: float) -> void:
	var stun_time := minf(remaining, delta)
	remaining -= stun_time
	delta -= stun_time
	var immune_time := minf(_immunity, delta)
	_immunity -= immune_time
	delta -= immune_time
	var delay_time := minf(_delay, delta)
	_delay -= delay_time
	buildup = maxf(0.0, buildup - (delta - delay_time) * DECAY_PER_SECOND)


func is_stunned() -> bool:
	return remaining > 0.0


func clear() -> void:
	buildup = 0.0
	remaining = 0.0
	_delay = 0.0
	_immunity = 0.0
