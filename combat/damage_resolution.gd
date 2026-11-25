extends RefCounted
## Converts fully mitigated damage to the whole amount applied to combat resources.


static func hit(amount: float) -> int:
	return maxi(0, roundi(amount))


static func tick(amount: float, state: Dictionary) -> int:
	# Keep the rounding difference so cumulative damage is independent of tick size.
	var total := amount + float(state.get("damage_remainder", 0.0))
	var whole := hit(total)
	state["damage_remainder"] = total - whole
	return whole
