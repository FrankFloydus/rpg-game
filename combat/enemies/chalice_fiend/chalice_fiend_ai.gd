extends "res://combat/enemies/ranged_enemy.gd"

const DEFINITION := {
	"id": 18,
	"name": "Chalice Fiend",
	"level": 7,
	"family": "fiend",
	"weapon": "scepter",
	"skin": "8c4341",
	"cloth": "3d282c",
	"accent": "f7af58",
	"height": 2.16,
	"width": 0.42,
	"scale": 1.10,
	"part": "cursed_ember",
	"ranged": true,
}


func definition() -> Dictionary:
	return DEFINITION
