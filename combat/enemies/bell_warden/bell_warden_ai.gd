extends "res://combat/enemies/enemy.gd"

const DEFINITION := {
	"id": 21, "name": "Bell Warden", "level": 3, "family": "bell_warden",
	"weapon": "bell", "height": 1.93, "width": 0.46, "scale": 1.0, "part": "iron_scale",
	"additional_moves_level": 1,
}


func definition() -> Dictionary:
	return DEFINITION
