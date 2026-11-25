extends "res://combat/enemies/enemy.gd"

const DEFINITION := {
	"id": 15,
	"name": "Thornback",
	"level": 5,
	"additional_moves_level": 1,
	"family": "thornback",
	"weapon": "fangs",
	"skin": "81746c",
	"cloth": "3b2c2b",
	"accent": "d3ad7e",
	"height": 1.13,
	"width": 0.40,
	"scale": 1.20,
	"part": "horn_fragment",
}


func definition() -> Dictionary:
	return DEFINITION
