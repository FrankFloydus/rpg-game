extends "res://combat/enemies/enemy.gd"

const DEFINITION := {
	"id": 2,
	"name": "Ashen Hound",
	"level": 1,
	"family": "hound",
	"weapon": "fangs",
	"skin": "50423e",
	"cloth": "282227",
	"accent": "e68b4c",
	"height": 0.89,
	"width": 0.28,
	"scale": 0.95,
	"part": "horn_fragment",
}


func definition() -> Dictionary:
	return DEFINITION
