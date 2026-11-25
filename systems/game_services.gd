extends Node
## Typed access to live services whose lifetime belongs to the composing scene.

const AudioService := preload("res://systems/game_audio.gd")

var audio: AudioService:
	get:
		return _audio_scopes.back() if not _audio_scopes.is_empty() else null

var _audio_scopes: Array[AudioService] = []


static func from_context(context: Node) -> Node:
	var tree := context.get_tree()
	return tree.root.get_node_or_null("Services") if tree != null else null


static func audio_for(context: Node) -> AudioService:
	var services := from_context(context)
	return services.audio if services != null else null


func register_audio(service: AudioService) -> void:
	if not _audio_scopes.has(service):
		_audio_scopes.append(service)


func unregister_audio(service: AudioService) -> void:
	_audio_scopes.erase(service)
