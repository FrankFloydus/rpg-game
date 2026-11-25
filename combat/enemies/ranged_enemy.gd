@abstract
extends "res://combat/enemies/enemy.gd"

@export_group("Ranged Positioning")
## Preferred firing distance from the target in meters, capped at the ability's attack range.
## A closer target can trigger retreat. Another retreat against the same target becomes
## available when the gap reaches this preferred distance plus 0.75 meters.
@export_range(0.0, 20.0, 0.1, "or_greater", "suffix:m") var preferred_range := DEFAULT_RANGED_PREFERRED_RANGE
## Seconds the enemy tries to retreat from a close target before preparing to fire in place.
## At zero the enemy can fire from close range without retreating, if the shot is clear.
@export_range(0.0, 5.0, 0.05, "or_greater", "suffix:s") var retreat_duration := DEFAULT_RANGED_RETREAT_DURATION


func ranged_positioning() -> Dictionary:
	return {"preferred_range": preferred_range, "retreat_duration": retreat_duration}
