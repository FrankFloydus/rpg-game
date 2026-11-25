@tool
extends Resource
## Player guard costs and Stamina recovery. The player and editor share this tuning.

## Stamina regained in one second at the base capacity.
@export_range(0.1, 20.0, 0.05, "or_greater", "suffix:/s") var base_recharge_per_second := 3.2
## Additional recharge per second for each point of maximum Stamina above the base capacity.
@export_range(0.0, 1.0, 0.01, "suffix:/s") var bonus_capacity_recharge := 0.08
## Wait after lowering a guard that has spent Stamina.
@export_range(0.0, 5.0, 0.05, "suffix:s") var guard_release_delay := 0.70
## A hit can extend this minimum wait, even if the player immediately attacks out of guard.
@export_range(0.0, 5.0, 0.05, "suffix:s") var hit_recharge_delay := 0.55
## Initial period without recovery following a guard break.
@export_range(0.0, 10.0, 0.05, "suffix:s") var broken_guard_delay := 2.0
## Lowest amount needed to raise a guard. That guard can still absorb one last affordable or overspending hit.
@export_range(0.1, 12.0, 0.1, "suffix:Stamina") var minimum_to_guard := 1.0
## Flat part of the Stamina cost when a block succeeds.
@export_range(0.0, 12.0, 0.05, "suffix:Stamina") var base_block_cost := 2.0
## Stamina cost per point of the incoming attack's damage.
@export_range(0.0, 3.0, 0.01, "suffix:×") var damage_cost_factor := 1.05
## Fraction of the normal cost while using a shield.
@export_range(0.05, 1.0, 0.01, "suffix:×") var shield_cost_multiplier := 0.75


func recharge_per_second(maximum: float, base_capacity: float) -> float:
	return base_recharge_per_second + maxf(0.0, maximum - base_capacity) * bonus_capacity_recharge
