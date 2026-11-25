extends "res://combat/enemies/enemy.gd"

const DEFINITION := {
	"id": 4,
	"name": "Rotmouth",
	"level": 1,
	"family": "ghoul",
	"weapon": "talons",
	"skin": "7a7b50",
	"cloth": "453c31",
	"accent": "b89b51",
	"height": 1.63,
	"width": 0.37,
	"scale": 0.95,
	"part": "ghoul_tongue",
}


func definition() -> Dictionary:
	return DEFINITION
