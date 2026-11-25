extends "res://combat/enemies/ranged_enemy.gd"

const DEFINITION := {
	"id": 17,
	"name": "Hollow Cantor",
	"level": 6,
	"family": "cantor",
	"weapon": "orb",
	"skin": "8a89a6",
	"cloth": "332b45",
	"accent": "ae90e1",
	"height": 2.24,
	"width": 0.37,
	"scale": 1.1,
	"part": "wraith_dust",
	"ranged": true,
}


func definition() -> Dictionary:
	return DEFINITION
