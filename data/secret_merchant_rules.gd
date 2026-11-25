@tool
extends Resource
## Controls the rare dungeon merchant's appearance, inventory quality and prices.

## Earliest dungeon depth where the Lantern Broker can appear.
@export_range(10, 100, 1) var minimum_depth := 10
## Chance that a reserved primary expedition event is assigned to the Lantern Broker.
@export_range(0.0, 1.0, 0.001) var share_of_primary_events := 0.13
## Chance that one generated Lantern Broker catalogue includes a Legendary.
@export_range(0.0, 0.1, 0.001) var legendary_chance := 0.005
## Item-level band ending at the player's highest reached depth, including the current depth.
@export_range(1, 15, 1) var item_level_window := 5
## Number of offers generated before fitting them to the merchant grid.
@export_range(3, 15, 1) var stock_count := 7
## Price multiplier for the Broker's rare equipment.
@export_range(1.0, 12.0, 0.05, "suffix:x") var rare_price := 2.25
## Price multiplier for the occasional legendary offer.
@export_range(1.0, 30.0, 0.05, "suffix:x") var legendary_price := 5.5
