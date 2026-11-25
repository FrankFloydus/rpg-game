@tool
extends Resource
## Expedition-only tuning, independent of actor level, rarity and AI timing.

## Life and attack damage multiplier for depths without an explicit entry.
@export_range(0.05, 10.0, 0.05, "or_greater", "suffix:x") var default_multiplier := 1.0
## Overrides by exact dungeon depth. Training ignores these depths and uses actor level alone.
@export var multipliers: Dictionary[int, float] = {}


func for_depth(depth: int) -> float:
	var fallback := maxf(0.05, default_multiplier) if is_finite(default_multiplier) else 1.0
	if depth < 1:
		return 1.0
	var multiplier := float(multipliers.get(depth, fallback))
	return maxf(0.05, multiplier) if is_finite(multiplier) else fallback
