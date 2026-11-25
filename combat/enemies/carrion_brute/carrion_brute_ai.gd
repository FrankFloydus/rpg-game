extends "res://combat/enemies/enemy.gd"

const DEFINITION := {
	"id": 12,
	"name": "Carrion Brute",
	"level": 4,
	"family": "brute",
	"weapon": "hook",
	"skin": "8e6d66",
	"cloth": "4a302e",
	"accent": "a64037",
	"height": 2.21,
	"width": 0.48,
	"scale": 1.19,
	"part": "plague_gland",
}


func definition() -> Dictionary:
	return DEFINITION
