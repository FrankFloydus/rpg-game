@tool
class_name SecretChallengeSocket
extends Resource
## A location and firing pattern chosen by the route's designer.

## A digit written once in the route map at this fixture.
@export var glyph := "1"
## Authored floor fixture at this location.
@export_enum("spike_plate", "ember_vent", "miasma_vent") var kind := "spike_plate"
## An optional alternate floor fixture selected by the dungeon seed.
@export_enum("none", "spike_plate", "ember_vent", "miasma_vent") var alternate_kind := "none"
## Faces east (1, 0), west (-1, 0), south (0, 1), or north (0, -1) in the authored rows.
@export var facing := Vector2i.RIGHT
## Delay fraction in the seeded trap sequence, from immediate to the last fixture.
@export_range(0.0, 1.0, 0.05) var phase := 0.0
## Distance across the fixture in the direction the player travels, in metres.
@export_range(0.75, 2.5, 0.05, "suffix:m") var reach := 1.35
## The dungeon seed can leave this socket empty.
@export var optional := false
