extends "res://combat/enemies/ranged_enemy.gd"

const DEFINITION := {
	"id": 1,
	"name": "Ossuary Archer",
	"level": 1,
	"family": "skeleton",
	"weapon": "bow",
	"skin": "bdad93",
	"cloth": "463a36",
	"accent": "a88d5c",
	"height": 1.82,
	"width": 0.25,
	"scale": 0.96,
	"part": "bone_shard",
	"ranged": true,
}


func definition() -> Dictionary:
	return DEFINITION
