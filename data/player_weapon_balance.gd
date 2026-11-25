@tool
extends Resource
## Per-contact weapon tuning, applied to the whole hit before level and mitigation.

@export_group("Two-handed Melee")
## Additional damage multiplier on charged swords, axes and maces. The base attack still supplies its charge bonus.
@export_range(0.0, 2.0, 0.01, "suffix:x") var two_handed_charge := 0.88
## Share of the first target's damage that a sweeping two-handed attack deals to each later target.
@export_range(0.0, 1.0, 0.01, "suffix:x") var two_handed_cleave := 0.50

@export_group("Staff")
## Share of the primary bolt's damage dealt by Forked Staff Bolt to its secondary target.
@export_range(0.0, 1.0, 0.01, "suffix:x") var staff_fork_damage := 0.50
