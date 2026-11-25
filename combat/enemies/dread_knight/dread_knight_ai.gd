extends "res://combat/enemies/enemy.gd"

const DEFINITION := {
	"id": 19,
	"name": "Dread Knight",
	"level": 8,
	"family": "dread",
	"weapon": "greatsword",
	"skin": "696675",
	"cloth": "302c37",
	"accent": "eaa2a6",
	"height": 2.51,
	"width": 0.46,
	"scale": 1.20,
	"part": "black_ichor",
}


func definition() -> Dictionary:
	return DEFINITION
