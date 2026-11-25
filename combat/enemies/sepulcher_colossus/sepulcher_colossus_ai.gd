extends "res://combat/enemies/enemy.gd"

const DEFINITION := {
	"id": 16,
	"name": "Sepulcher Colossus",
	"level": 5,
	"family": "golem",
	"weapon": "fists",
	"skin": "797873",
	"cloth": "484745",
	"accent": "d99d62",
	"height": 2.50,
	"width": 0.49,
	"scale": 1.19,
	"part": "iron_scale",
}


func definition() -> Dictionary:
	return DEFINITION
