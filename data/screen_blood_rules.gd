@tool
extends Resource
## Trigger and presentation tuning for Crimson Carnage's first-person splatters.

@export_group("Triggers")
## Show the lens effect after a blood-bearing direct hit takes Life.
@export var received_hits := true
## Show blood from fleshy deaths close to the first-person camera.
@export var nearby_deaths := true
## Maximum camera distance to the center of a dying enemy.
@export_range(0.1, 8.0, 0.05, "suffix:m") var nearby_death_distance := 3.0
## Restrict death splatters to enemies within the visible camera frustum.
@export var visible_deaths_only := false
## Minimum interval between overlapping close death splatters.
@export_range(0.0, 2.0, 0.05, "suffix:s") var nearby_death_interval := 0.0

@export_group("Drops")
## Seconds after a trigger at which to emit each batch.
@export var burst_delays := PackedFloat32Array([0.0, 0.05, 0.15])
## Number of individually randomized drops in every timed batch.
@export_range(0, 24, 1) var drops_per_burst := 6
## Minimum and maximum drop lifetime in seconds.
@export var drop_lifetime := Vector2(3.0, 5.0)
## Minimum and maximum drop height as fractions of the viewport height.
@export var drop_size := Vector2(0.010, 0.052)
## Minimum and maximum height-to-width ratio of the drop.
@export var drop_aspect := Vector2(1.2, 1.85)
## Minimum and maximum initial opacity randomly assigned to each drop.
@export var drop_opacity := Vector2(0.32, 0.92)
## Minimum and maximum fall speed in viewport heights per second.
@export var drop_fall_speed := Vector2(0.004, 0.008)
## Color multiplied by each falling drop texture.
@export var drop_tint := Color(0.15912652, 6.768387e-08, 3.308989e-08, 1.0)
## Softens edges within each falling drop mask.
@export_range(0.0, 2.0, 0.05) var drop_softness := 0.9

@export_group("Edge spray")
## Number of broad smears placed near the edges per spray event.
@export_range(0, 12, 1) var edge_smears := 3
## Quad size in fractions of half the viewport diagonal.
@export var smear_size := Vector2(0.30, 0.60)
## Distance from screen center, with 0.5 at the center of an edge.
@export var smear_ring_radius := Vector2(0.40, 0.50)
## Minimum and maximum seconds before an edge smear fades away.
@export var smear_lifetime := Vector2(3.0, 4.0)
## Color and starting alpha applied to the edge spray texture.
@export var edge_tint := Color(0.065, 0.014, 0.022, 0.85)
## Texture mip level sampled by the edge spray shader. Higher values soften the pattern.
@export_range(0.0, 6.0, 0.1) var smear_softness_mip := 4.4
## Boosts coverage in partially transparent areas of the edge spray mask.
@export_range(1.0, 12.0, 0.1) var smear_coverage_gain := 5.7

@export_group("Composition")
## Overall opacity multiplier for every mark.
@export_range(0.0, 1.0, 0.01) var opacity := 0.82
## Older marks are retired as new ones pass this limit.
@export_range(1, 128, 1) var mark_limit := 64
