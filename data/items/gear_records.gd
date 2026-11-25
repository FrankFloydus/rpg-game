@tool
extends Resource
## Item families, base entries, and the level curve used by every item roll.

@export var types: Dictionary = {}
@export var base_footprints: Dictionary = {}
@export var bases: Array[Dictionary] = []
## Each point stores level, attack multiplier, and defense multiplier.
@export var power_by_level: Array[Vector3] = []

