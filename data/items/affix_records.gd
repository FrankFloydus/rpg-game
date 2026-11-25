@tool
extends Resource
## Shared affix, crafting, and tier tables used by item generation and save restoration.

@export var tier_levels: Array[int] = []
@export var tier_multipliers: Array[float] = []
@export var prefixes: Array[Dictionary] = []
@export var suffixes: Array[Dictionary] = []
@export var materials: Dictionary = {}
## Keeps existing material rolls deterministic after the resource is saved.
@export var material_order: PackedStringArray = []
@export var recipes: Array[Dictionary] = []

