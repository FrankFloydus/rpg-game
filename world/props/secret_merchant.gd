extends StaticBody3D

var payload := {"kind": "secret_merchant"}
var text := "Trade with the Lantern Broker"
var margin := 0.72
var passage_id := ""
var _discovered := false
var interaction_point: Vector3:
	get:
		return global_basis.z * 0.32 + Vector3.UP * 1.3


func configure(passage: String, revealed: bool) -> void:
	passage_id = passage
	_discovered = revealed


func _ready() -> void:
	$Nameplate.visible = _discovered
	var animator := get_node_or_null("ModelPivot/BrokerModel/AnimationPlayer") as AnimationPlayer
	if animator != null and animator.has_animation(&"Idle"):
		animator.animation_finished.connect(func(clip: StringName) -> void:
			if clip == &"Idle":
				animator.play(&"Idle"))
		animator.play(&"Idle")


func discover() -> void:
	_discovered = true
	$Nameplate.show()


func pick_available() -> bool:
	return _discovered
