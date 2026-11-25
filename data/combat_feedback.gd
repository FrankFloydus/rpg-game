@tool
extends Resource
## Visual reactions driven by confirmed enemy hits.

@export_group("Four-Way Hit Reactions")
## Time for a surviving enemy to recoil and recover, in seconds.
@export_range(0.06, 0.8, 0.01, "suffix:s") var reaction_duration := 0.24
## Maximum visible body tilt when hit from the front, rear or sides.
@export_range(0.0, 35.0, 0.5, "suffix:°") var reaction_tilt := 11.0
## How far the visible model shifts with the hit while its feet retain gameplay collision.
@export_range(0.0, 0.30, 0.005, "suffix:m") var reaction_travel := 0.095
## Additional articulation on a rig's torso and head relative to the body tilt.
@export_range(0.0, 1.0, 0.02) var reaction_joint_share := 0.36
## Strength of hits from the front, rear, left and right, respectively.
@export var direction_weights := Vector4(1.0, 0.87, 1.0, 1.0)
## Multiplier for the visible reaction when a charged hit lands.
@export_range(0.5, 2.0, 0.05) var charged_reaction_factor := 1.26
## Optional keyed curve over the reaction's normalized time. Its first and last value should be zero.
@export var reaction_curve: Curve

@export_group("Enemy Status Particles")
## Loop attached while Thornback's spikes reflect melee hits.
@export var thornback_guard_loop: PackedScene


func response_at(phase: float) -> float:
	if reaction_curve != null:
		return reaction_curve.sample_baked(phase)
	return smoothstep(0.0, 0.19, phase) * (1.0 - smoothstep(0.19, 1.0, phase))
