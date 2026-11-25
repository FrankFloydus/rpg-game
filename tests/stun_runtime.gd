extends SceneTree
## Exercises the shared buildup, recovery and cap independently of actor timing.

const Stun = preload("res://combat/effects/stun_runtime.gd")

var _failures := 0


func _initialize() -> void:
	var enemy := Stun.new()
	_check(enemy.add_impact(65.0, 100.0, 50.0, Stun.ENEMY_BASE_DURATION, Stun.ENEMY_MAX_DURATION) == 0.0,
		"A single heavy hit begins buildup")
	enemy.advance(1.90)
	_check(enemy.buildup == 65.0, "Buildup survives until the full delay elapses")
	enemy.advance(0.35)
	_check(is_equal_approx(enemy.buildup, 57.5), "Buildup decays only after the delay")
	var duration := enemy.add_impact(65.0, 100.0, 50.0, Stun.ENEMY_BASE_DURATION, Stun.ENEMY_MAX_DURATION)
	_check(is_equal_approx(duration, 0.825) and enemy.is_stunned() and enemy.buildup == 0.0,
		"The threshold spends accumulated points and Stun Power extends the duration")
	_check(enemy.add_impact(100.0, 100.0, 0.0, Stun.ENEMY_BASE_DURATION, Stun.ENEMY_MAX_DURATION) == 0.0,
		"New hits cannot extend an ongoing stun")
	enemy.advance(duration + 1.90)
	_check(not enemy.is_stunned() and enemy.start(0.5) == 0.0 and enemy.buildup == 0.0,
		"Recovery immunity starts after the full stun")
	enemy.advance(0.11)
	_check(enemy.add_impact(120.0, 100.0, 300.0, Stun.ENEMY_BASE_DURATION, Stun.ENEMY_MAX_DURATION) == 1.10,
		"Stun buildup can resume after immunity and obeys the enemy duration cap")
	var player := Stun.new()
	_check(player.add_impact(120.0, 100.0, 300.0, Stun.PLAYER_BASE_DURATION, Stun.PLAYER_MAX_DURATION) == 0.65,
		"The player has a shorter stun duration cap")
	player.clear()
	_check(not player.is_stunned() and player.start(0.3) == 0.3, "Clearing resets both stun and immunity")
	print("Hearth Below stun runtime: 9 checks, %d failures" % _failures)
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
