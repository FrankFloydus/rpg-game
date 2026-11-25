extends "res://combat/enemies/enemy.gd"

const DEFINITION := {
	"id": 27,
	"name": "Crypt Scurrer",
	"level": 3,
	"family": "scurrer",
	"weapon": "jaw",
	"skin": "706254",
	"cloth": "534538",
	"accent": "bca587",
	"height": 0.44,
	"width": 0.19,
	"scale": 1.0,
	"part": "carrion_eye",
	"spawn_in_pool": false,
}

@export_group("Swarm")
## Gap between short movement bursts while the scurrer approaches its attack slot.
@export_range(0.4, 3.0, 0.01, "suffix:s") var burst_interval := 0.92
## Duration of each movement burst.
@export_range(0.05, 0.5, 0.01, "suffix:s") var burst_duration := 0.22
## Movement multiplier during the brief burst.
@export_range(1.0, 1.6, 0.01, "suffix:x") var burst_speed := 1.24
## Maximum individual variation added to the bite windup in a pack.
@export_range(0.0, 0.25, 0.01, "suffix:s") var bite_stagger := 0.10


func definition() -> Dictionary:
	return DEFINITION


func _movement_speed() -> float:
	var speed := super._movement_speed()
	if not _engaged or _attack_phase != AttackPhase.READY or not _has_move_goal:
		return speed
	var cycle := fposmod(_combat_time + _rest_offset * 7.0, burst_interval)
	var weight := smoothstep(0.0, 0.055, cycle) * (1.0 - smoothstep(burst_duration - 0.05, burst_duration, cycle))
	return speed * lerpf(1.0, burst_speed, weight)


func _begin_attack(direction: Vector3) -> void:
	super._begin_attack(direction)
	var offset := clampf(inverse_lerp(0.03, 0.16, _rest_offset), 0.0, 1.0)
	_windup_total += offset * bite_stagger
	_attack_remaining = _windup_total
