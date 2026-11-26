@tool
extends Resource
## Drop probabilities and rarity weights shared by the loot and deck systems.

## Minimum item rarity and the probabilities for higher rarities, by source.
@export var item_profiles: Dictionary = {}
@export var card_chances: Dictionary = {}
@export var card_weights: Dictionary = {}
@export var cards: Dictionary = {}
## Keeps existing seeded card rolls in the authored order after a save.
@export var card_order: PackedStringArray = []
@export_range(0.0, 1.0, 0.001) var legendary_card_eligibility := 0.12
@export_range(1, 100, 1) var vendor_upgrade_level := 12
@export_range(0.0, 1.0, 0.0001) var vendor_rare_chance := 0.0035
## Highest level used for the hub vendor's gear levels and shop markup.
@export_range(1, 100, 1) var vendor_max_depth := 25
## Additional fraction of base price added for each level above one, up to the vendor cap.
@export_range(0.0, 0.25, 0.001) var vendor_price_per_depth := 0.034


