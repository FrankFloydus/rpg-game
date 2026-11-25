extends StaticBody3D
## Iron portcullis that can be interacted with independently of ground loot.

var payload: Dictionary
var interaction_point := Vector3.UP * 1.27
var margin := 1.05
var tint := Color("#e3c391")
var text := ""
var _opened := false

@onready var _ironwork: Node3D = $Ironwork


func configure(gate_id: String, key_name: String, opened: bool) -> void:
	payload = {"kind": "route_gate", "id": gate_id, "key_name": key_name}
	text = "Unlock with " + key_name
	_opened = opened


func _ready() -> void:
	if _opened:
		_ironwork.position.y = 2.85
		collision_layer = 0


func pick_available() -> bool:
	return not _opened


func open() -> void:
	_opened = true
	var rising := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	rising.tween_property(_ironwork, "position:y", 2.85, 0.58).set_trans(Tween.TRANS_CUBIC)
	rising.tween_callback(set_collision_layer_value.bind(1, false))
