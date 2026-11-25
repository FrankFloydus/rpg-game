@tool
extends Resource
## Balance values for legendary effects triggered by landed melee weapon contacts.

@export_group("Latchknife")
## Seconds allowed to complete three distinct light chain steps and land the charged hit.
@export_range(0.5, 10.0, 0.1, "suffix:s") var latch_window := 2.5
## Additional Physical damage of the charged strike that consumes a completed latch.
@export_range(0.0, 50.0, 0.5, "suffix:%") var latch_damage_bonus := 12.0
## Seconds before the same enemy can begin collecting chain steps again.
@export_range(0.1, 30.0, 0.1, "suffix:s") var latch_rearm := 5.0

@export_group("Stillstone")
## Points restored when a charged blunt hit actually stuns an enemy. Cannot end Guard Break.
@export_range(0.0, 10.0, 0.1) var stillstone_stamina := 2.0
## Seconds between successful Stamina restorations.
@export_range(0.1, 30.0, 0.1, "suffix:s") var stillstone_rearm := 4.0

@export_group("Gravegate")
## Duration of Chill when a charged axe hit interrupts a damaging enemy cast.
@export_range(0.1, 10.0, 0.1, "suffix:s") var gravegate_chill_seconds := 2.0
## Percentage of movement speed removed by the Chill.
@export_range(15.0, 65.0, 1.0, "suffix:%") var gravegate_chill := 18.0
## Seconds between successful interrupts that inflict Chill.
@export_range(0.1, 30.0, 0.1, "suffix:s") var gravegate_rearm := 5.0

@export_group("The Unmatched Pair")
## Seconds allowed to land the crossover after the main-hand light strike.
@export_range(0.5, 15.0, 0.1, "suffix:s") var pair_window := 4.5
## Ward restored when both hands of the crossover land. Capped by the player's Ward.
@export_range(0.0, 10.0, 0.1) var pair_ward := 3.0
## Seconds between successful Ward restorations.
@export_range(0.1, 30.0, 0.1, "suffix:s") var pair_rearm := 6.0
