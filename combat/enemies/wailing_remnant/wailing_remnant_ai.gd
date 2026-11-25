extends "res://combat/enemies/ranged_enemy.gd"

const DEFINITION := {
	"id": 11,
	"name": "Wailing Remnant",
	"level": 3,
	"family": "wraith",
	"weapon": "talons",
	"skin": "83aaa6",
	"cloth": "344e53",
	"accent": "8fe4d8",
	"height": 2.03,
	"width": 0.33,
	"scale": 1.0,
	"part": "wraith_dust",
	"ranged": true,
}


func definition() -> Dictionary:
	return DEFINITION
