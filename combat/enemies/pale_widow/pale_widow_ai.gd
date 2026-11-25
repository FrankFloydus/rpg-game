extends "res://combat/enemies/ranged_enemy.gd"

const DEFINITION := {
	"id": 7,
	"name": "Pale Widow",
	"level": 2,
	"family": "widow",
	"weapon": "fangs",
	"skin": "8f8672",
	"cloth": "676655",
	"accent": "8dab5b",
	"height": 0.87,
	"width": 0.33,
	"scale": 1.1,
	"part": "venom_sac",
	"ranged": true,
}


func definition() -> Dictionary:
	return DEFINITION
