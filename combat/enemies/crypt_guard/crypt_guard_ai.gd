extends "res://combat/enemies/enemy.gd"

const DEFINITION := {
	"id": 6,
	"name": "Crypt Guard",
	"level": 2,
	"family": "knight",
	"weapon": "shield_sword",
	"skin": "988979",
	"cloth": "4f4539",
	"accent": "a87947",
	"height": 2.02,
	"width": 0.40,
	"scale": 1.05,
	"part": "iron_scale",
}


func definition() -> Dictionary:
	return DEFINITION
