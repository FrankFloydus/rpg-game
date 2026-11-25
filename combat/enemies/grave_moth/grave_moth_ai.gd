extends "res://combat/enemies/ranged_enemy.gd"

const DEFINITION := {
	"id": 9,
	"name": "Grave Moth",
	"level": 3,
	"family": "moth",
	"weapon": "spores",
	"skin": "685260",
	"cloth": "443a42",
	"accent": "db8d66",
	"height": 1.6,
	"width": 0.30,
	"scale": 1.0,
	"part": "carrion_eye",
	"ranged": true,
}


func definition() -> Dictionary:
	return DEFINITION
