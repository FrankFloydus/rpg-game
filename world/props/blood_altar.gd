extends Node3D

var payload := {"kind": "blood_altar"}
var text := "Blood Altar"
var interaction_point := Vector3.UP * 1.56
var margin := 0.64
var _spent := false


func configure(spent: bool) -> void:
	_spent = spent


func _ready() -> void:
	if _spent:
		spend()


func pick_available() -> bool:
	return not _spent


func spend() -> void:
	_spent = true
	$BloodLight.hide()
	$Offering.hide()
