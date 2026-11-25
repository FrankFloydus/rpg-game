extends "res://combat/enemies/enemy.gd"

const DEFINITION := {
	"id": 3,
	"name": "Barrow Crawler",
	"level": 1,
	"family": "spider",
	"weapon": "fangs",
	"skin": "684c41",
	"cloth": "2a2024",
	"accent": "ce482e",
	"height": 0.73,
	"width": 0.27,
	"scale": 0.90,
	"part": "spider_silk",
}


func definition() -> Dictionary:
	return DEFINITION
