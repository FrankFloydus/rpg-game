extends "res://combat/enemies/enemy.gd"

const DEFINITION := {
	"id": 10,
	"name": "Mire Husk",
	"level": 3,
	"family": "husk",
	"weapon": "club",
	"skin": "728065",
	"cloth": "424830",
	"accent": "86a657",
	"height": 1.88,
	"width": 0.37,
	"scale": 1.0,
	"part": "grave_moss",
}


func definition() -> Dictionary:
	return DEFINITION
