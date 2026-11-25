extends Resource
## Balances the response of a dead enemy to one lethal hit.

@export_group("Body Resistance")
## Capsule radius of the reference body. Wider and taller bodies resist larger reactions.
@export_range(0.10, 1.50, 0.01, "suffix:m") var reference_radius := 0.29
## Reference height, including the rounded ends of the capsule.
@export_range(0.30, 4.00, 0.01, "suffix:m") var reference_height := 1.57
## Controls how rapidly resistance grows as bodies gain volume.
@export_range(0.0, 1.5, 0.01) var volume_exponent := 0.60

@export_group("Edged Weapons")
## Distance within which a precise cut can sever a limb without extra damage past death.
@export_range(0.10, 0.50, 0.01, "suffix:m") var base_cut_radius := 0.27
## Additional resolved damage past zero Life required for each extra limb on a reference body.
@export_range(1.0, 100.0, 0.5) var overkill_per_limb := 10.0
## The most limbs one strike can detach, even with very high damage.
@export_range(1, 5) var max_limbs := 3
## Additional reach along the strike direction at maximum overkill.
@export_range(0.0, 1.50, 0.01, "suffix:m") var maximum_cut_extension := 0.63
## Extra sideways tolerance near a powerful cut, before body resistance.
@export_range(0.0, 0.50, 0.01, "suffix:m") var maximum_cut_radius_bonus := 0.24
## Speed imparted to detached limbs against a reference body. Larger bodies reduce this speed.
@export_range(0.1, 6.0, 0.05, "suffix:m/s") var limb_launch_speed := 1.20

@export_group("Blunt Weapons")
## Initial corpse speed for a one-handed blunt weapon against a reference body.
@export_range(0.1, 8.0, 0.05, "suffix:m/s") var blunt_launch_speed := 2.40
## The base inertia advantage for a two-handed blunt weapon.
@export_range(1.0, 2.5, 0.01) var two_handed_multiplier := 1.60
## Resolved damage past zero Life required to reach the maximum launch boost.
@export_range(1.0, 150.0, 0.5) var blunt_overkill_for_maximum := 28.0
## Maximum fraction added to blunt launch speed for overkill.
@export_range(0.0, 2.0, 0.01) var maximum_blunt_speed_bonus := 0.82

@export_group("Live Displacement")
## Horizontal speed lost each second after a large enemy hit pushes the player.
@export_range(3.0, 40.0, 0.1, "suffix:m/s²") var player_push_deceleration := 15.8
## Maximum starting horizontal speed for the player's physical knockback.
@export_range(1.0, 12.0, 0.1, "suffix:m/s") var maximum_player_push_speed := 6.4
## Seconds before another player knockback can start. Damage is still resolved normally.
@export_range(0.1, 2.0, 0.01, "suffix:s") var player_push_reuse := 0.58
## Minimum fraction of maximum Life a charged blunt hit must deal to push a surviving enemy.
@export_range(0.01, 0.5, 0.01) var blunt_live_minimum_life_share := 0.09
## Fraction of maximum Life at which a surviving enemy receives full blunt push before its size adjustment.
@export_range(0.01, 1.0, 0.01) var blunt_live_full_life_share := 0.28
## Full initial push speed for a charged one-handed blunt weapon against a reference enemy.
@export_range(0.1, 4.5, 0.05, "suffix:m/s") var one_handed_live_push := 2.25
## Full initial push speed for a charged two-handed blunt weapon against a reference enemy.
@export_range(0.1, 4.5, 0.05, "suffix:m/s") var two_handed_live_push := 3.8
## Seconds before a surviving enemy can be pushed by another charged blunt strike.
@export_range(0.1, 2.0, 0.01, "suffix:s") var enemy_push_reuse := 0.65


func body_resistance(radius: float, height: float) -> float:
	# Capsule volume, with the common factor of PI canceled in the ratio.
	var volume := radius * radius * maxf(height - radius * (2.0 / 3.0), radius)
	var reference_volume := reference_radius * reference_radius * (reference_height - reference_radius * (2.0 / 3.0))
	return pow(clampf(volume / maxf(0.0001, reference_volume), 0.25, 6.0), volume_exponent)


func cut_count(overkill: float, resistance: float) -> int:
	var additional := floori(maxf(0.0, overkill) / (overkill_per_limb * resistance))
	return mini(max_limbs, 1 + additional)


func cut_extent(overkill: float, resistance: float) -> Vector2:
	var maximum := overkill_per_limb * resistance * float(maxi(1, max_limbs - 1))
	var strength := clampf(overkill / maximum, 0.0, 1.0)
	var radius := base_cut_radius / pow(resistance, 0.25) + strength * maximum_cut_radius_bonus
	return Vector2(radius, strength * maximum_cut_extension)


func blunt_speed(overkill: float, resistance: float, two_handed: bool) -> float:
	var strength := clampf(overkill / blunt_overkill_for_maximum, 0.0, 1.0)
	var carry := two_handed_multiplier if two_handed else 1.0
	return blunt_launch_speed * carry * (1.0 + strength * maximum_blunt_speed_bonus) / resistance


func surviving_blunt_speed(life_fraction: float, resistance: float, two_handed: bool) -> float:
	if life_fraction < blunt_live_minimum_life_share:
		return 0.0
	var amount := smoothstep(blunt_live_minimum_life_share,
		maxf(blunt_live_minimum_life_share + 0.01, blunt_live_full_life_share), life_fraction)
	var maximum := two_handed_live_push if two_handed else one_handed_live_push
	return maximum * lerpf(0.38, 1.0, amount) / resistance
