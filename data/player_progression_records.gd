@tool
extends Resource
## Player level, experience, and attribute coefficients used by CharacterProgression.

@export_group("Life and Attributes")
## Each point stores player level and unmodified maximum Life.
@export var life_by_level: Array[Vector2] = []
## Increase to base damage per point of the ability's scaling attribute. 0.0075 is 0.75%.
@export_range(0.0, 1.0, 0.0001, "or_greater") var damage_per_point := 0.0075
## Additional maximum Stamina per point of Strength.
@export_range(0.0, 10.0, 0.01, "or_greater") var stamina_per_strength := 0.20
## Critical chance percentage points gained per point of Dexterity for Dexterity weapons.
@export_range(0.0, 10.0, 0.01, "or_greater") var critical_chance_per_dexterity := 0.15
## Additional maximum Mana per point of Intelligence.
@export_range(0.0, 10.0, 0.01, "or_greater") var mana_per_intelligence := 0.50

@export_group("Experience")
## XP required for the first level gain, before the per-level increment.
@export_range(1, 10000, 1, "or_greater") var base_xp_cost := 100
## Additional XP added to the next level's price for every level after the first.
@export_range(0, 200, 1, "or_greater") var xp_cost_per_level := 12
## Baseline encounter count used to budget XP per kill at enemy level 1.
@export_range(1, 100, 1, "or_greater") var base_expected_enemies := 28
## Upper limit of expected enemies used to budget XP per kill.
@export_range(1, 200, 1, "or_greater") var max_expected_enemies := 78
## Portion of an enemy level's progression XP budget awarded by individual kills.
@export_range(0.0, 1.0, 0.01) var kill_xp_share := 0.60
## Multipliers to XP per kill by enemy rarity. Normal enemies use 1.0.
@export var kill_rarity_xp: Dictionary = {"magic": 1.35, "rare": 2.0}
## Maximum level gap above an enemy before its kill XP falls to the minimum.
@export_range(1, 100, 1) var trivial_level_gap := 6

@export_group("Level Disparity")
## The first levels of enemy advantage that carry no disparity penalty.
@export_range(0, 100, 1) var grace_levels := 2
## Outgoing damage multiplier applied per level once the enemy is above the grace range.
@export_range(0.0, 1.0, 0.01) var outgoing_per_level := 0.75
## Number of levels beyond the grace range that use the standard outgoing multiplier.
@export_range(0, 20, 1) var standard_outgoing_levels := 3
## Outgoing multiplier per additional level of enemy advantage beyond the standard band.
@export_range(0.0, 1.0, 0.01) var overmatched_outgoing_per_level := 0.46
## Minimum fraction of outgoing damage remaining after all level penalties.
@export_range(0.0, 1.0, 0.001) var minimum_outgoing := 0.005
## Additional incoming damage fraction per level of enemy advantage beyond the grace range.
@export_range(0.0, 1.0, 0.01, "or_greater") var incoming_per_level := 0.05
## Limit of the enemy's incoming-damage bonus. 1.0 means at most double damage.
@export_range(0.0, 10.0, 0.01, "or_greater") var maximum_incoming_bonus := 1.0

