extends "res://combat/enemies/enemy.gd"

const DEFINITION := {
	"id": 13,
	"name": "Ironbound Reaper",
	"level": 4,
	"family": "reaper",
	"weapon": "scythe",
	"skin": "787276",
	"cloth": "39343f",
	"accent": "a4a2ac",
	"height": 2.31,
	"width": 0.37,
	"scale": 1.15,
	"part": "iron_scale",
}


func definition() -> Dictionary:
	return DEFINITION
