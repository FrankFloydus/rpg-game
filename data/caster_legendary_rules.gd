@tool
extends Resource
## Tuning for the caster and summon legendary effects.

@export_group("Rime That Rings")
## Base duration of Chill applied by a staff hit, before the target's level difference.
@export_range(0.1, 8.0, 0.1, "suffix:s") var rime_chill_seconds := 2.4
## Delay before a second fracture can trigger.
@export_range(0.0, 20.0, 0.1, "suffix:s") var rime_cooldown := 3.0
## Maximum distance from the initial enemy to a secondary target.
@export_range(0.5, 6.0, 0.1, "suffix:m") var rime_radius := 2.6
## Maximum number of additional enemies damaged by the fracture.
@export_range(1, 8) var rime_targets := 3
## Fraction of the resolved staff hit used as Cold damage for each secondary enemy.
@export_range(0.05, 2.0, 0.05) var rime_damage_factor := 0.70

@export_group("Tithe of Sparks")
## Mana spent on committed staff abilities to prime an arc.
@export_range(1.0, 100.0, 1.0, "suffix:Mana") var tithe_mana := 38.0
## Delay before another primed hit can create lightning arcs.
@export_range(0.0, 25.0, 0.1, "suffix:s") var tithe_cooldown := 5.0
## Maximum distance from the initial enemy to a secondary target.
@export_range(0.5, 8.0, 0.1, "suffix:m") var tithe_radius := 4.0
## Maximum number of additional enemies struck by the arc.
@export_range(1, 8) var tithe_targets := 2
## Fraction of the resolved staff hit used as Lightning damage for each arc.
@export_range(0.05, 2.0, 0.05) var tithe_damage_factor := 0.55

@export_group("Cairn Oath")
## How long the lone Oathbound guard serves when there is no active card summon.
@export_range(1.0, 40.0, 0.5, "suffix:s") var cairn_guard_seconds := 10.0
## Additional service granted to the existing Oathbound Three.
@export_range(0.5, 12.0, 0.5, "suffix:s") var cairn_extension_seconds := 3.0
