extends Node3D
## The cocoon shell and the cast timer share the enemy's world position.

@export var hit_material: Material = preload("res://combat/effects/cocoon_hit_material.tres")

@onready var cast_indicator: MeshInstance3D = $CastTimer
@onready var _silk_surfaces := $WovenShell.find_children("*", "MeshInstance3D", true, false)
@onready var _countdown: Label3D = $HatchCountdown
var _shown_tenths := -1
var _hit_time := 0.0


func _ready() -> void:
	cast_indicator.set_instance_shader_parameter("health_fraction", 0.0)
	set_process(false)


func _process(delta: float) -> void:
	_hit_time -= delta
	if _hit_time <= 0.0:
		_set_silk_overlay(null)
		set_process(false)


func update_hatch(remaining: float, duration: float) -> void:
	var progress := clampf(1.0 - remaining / maxf(duration, 0.001), 0.0, 1.0)
	cast_indicator.set_instance_shader_parameter("health_fraction", progress)
	var tenths := ceili(maxf(0.0, remaining) * 10.0 - 0.0001)
	if _shown_tenths != tenths:
		_shown_tenths = tenths
		_countdown.text = "Hatching %.1fs" % (float(tenths) * 0.1)


func hide_hatch() -> void:
	cast_indicator.hide()
	_countdown.hide()


func flash_hit() -> void:
	_set_silk_overlay(hit_material)
	_hit_time = 0.12
	set_process(true)


func _set_silk_overlay(material: Material) -> void:
	for surface: MeshInstance3D in _silk_surfaces:
		surface.material_overlay = material
