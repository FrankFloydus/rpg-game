extends RefCounted
## Routes inventory gestures to the audio service scoped to the current game.

const GameServices := preload("res://systems/game_services.gd")


static func grab(context: Node) -> void:
	var audio := GameServices.audio_for(context)
	if audio != null:
		audio.cue(&"item_grab")


static func place(context: Node, item: Dictionary) -> void:
	var audio := GameServices.audio_for(context)
	if audio != null:
		audio.place_item(item)
