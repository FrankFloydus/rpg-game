extends Node3D
## A contact burst plays only after its world position and surface are set.

const SURFACE_COLORS := {
	&"stone": Color(1.0, 0.94, 0.85),
	&"metal": Color(1.0, 0.83, 0.57, 0.63),
	&"arcane": Color(0.51, 0.93, 1.16, 0.73),
	&"arcane_fire": Color(1.08, 0.52, 0.23, 0.75),
	&"arcane_cold": Color(0.51, 1.0, 1.15, 0.64),
	&"arcane_lightning": Color(0.80, 0.62, 1.14, 0.76),
	&"arcane_poison": Color(0.66, 0.98, 0.44, 0.50),
	&"arrow": Color(0.88, 0.77, 0.60, 0.51),
	&"wood": Color(0.94, 0.75, 0.51),
	&"ceramic": Color(1.0, 0.68, 0.48),
}


func play(surface: StringName) -> void:
	set_meta(&"contact_surface", surface)
	var color: Color = SURFACE_COLORS.get(surface, SURFACE_COLORS[&"stone"])
	var arcane := String(surface).begins_with("arcane")
	if surface == &"arrow":
		scale *= 0.61
	elif arcane:
		scale *= 0.86
	$Dust.set_instance_shader_parameter(&"surface_tint", color)
	$ContactFlash.set_instance_shader_parameter(&"surface_tint", color)
	var sparking: ParticleProcessMaterial = $Sparks.process_material
	sparking.color = color
	if surface != &"metal":
		_restart($Dust)
	if surface != &"arrow":
		_restart($ContactFlash)
	if surface in [&"stone", &"metal"] or (arcane and surface != &"arcane_poison"):
		_restart($Sparks)
	if surface == &"stone":
		_restart($Chips)


func _restart(emitter: GPUParticles3D) -> void:
	emitter.restart()
	emitter.emitting = true
