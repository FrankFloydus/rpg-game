@tool
extends Resource
## Tuning shared by dungeon creation, sealed instances and the Training Ground.

## Seconds before a cleared dungeon seals after the player first leaves it.
@export_range(1.0, 120.0, 1.0, "or_greater", "suffix:s") var cleared_grace_seconds := 30.0
## Seconds an uncleared dungeon can be reentered after character logout.
@export_range(1.0, 3600.0, 1.0, "or_greater", "suffix:s") var logout_grace_seconds := 480.0
## Starting depth at which a newly generated dungeon gets a third connected floor.
@export_range(2, 50, 1, "or_greater") var third_floor_depth := 7
## Chance a newly assembled expedition climbs instead of descending.
@export_range(0.0, 1.0, 0.01) var ascending_chance := 0.45
## How long debug melee collision boxes stay visible in the Training Ground.
@export_range(0.1, 10.0, 0.1, "suffix:s") var player_trace_seconds := 2.0
## Time after death during which a ragdoll remains and can be raised.
@export_range(120.0, 600.0, 1.0, "or_greater", "suffix:s") var corpse_lifetime_seconds := 120.0

@export_group("Encounter Pacing")
## Inclusive minimum and maximum live enemies in the first chamber of Depth I.
@export var opening_chamber_size := Vector2i(1, 2)
## Maximum enemies in an ordinary room on Depth I's entry floor.
@export_range(2, 7, 1) var opening_floor_pack_cap := 3
## Chance to reserve a later room's pack until the player walks into the room.
@export_range(0.0, 1.0, 0.01) var threshold_ambush_chance := 0.84
## Chance an accessible unlocked coffer calls in the room's dormant pack.
@export_range(0.0, 1.0, 0.01) var coffer_ambush_chance := 0.72
## Remaining active enemies at or below this count can regroup near the player.
@export_range(1, 8, 1) var straggler_count := 4
## Seconds on clear footing before distant stragglers regroup near the player.
@export_range(0.25, 6.0, 0.05, "suffix:s") var straggler_delay_seconds := 1.40

@export_group("Expedition Events")
## Chance that an expedition reserves a floor for a gate, trial coffer, or Blood Altar.
@export_range(0.0, 1.0, 0.01) var primary_event_chance := 0.78
## Chance of a second major event in an eligible deeper expedition that has a primary event.
@export_range(0.0, 1.0, 0.01) var second_event_chance := 0.36
## First depth eligible for a second major event.
@export_range(3, 50, 1, "or_greater") var second_event_depth := 7
## Chance that an expedition also has a room threshold or a single coffer ambush.
@export_range(0.0, 1.0, 0.01) var incidental_ambush_chance := 0.72
## Share of eligible expeditions that can get a combat-only Grave Legate invasion.
@export_range(0.0, 1.0, 0.01) var legate_incursion_chance := 0.24
## Earliest depth where an unlocked guarded coffer can stage several combat waves.
@export_range(2, 25, 1, "or_greater") var trial_coffer_min_depth := 4
## Chance that a suitable reliquary on a floor becomes a multi-wave encounter.
@export_range(0.0, 1.0, 0.01) var trial_coffer_chance := 0.45
