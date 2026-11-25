@tool
extends Resource
## Tuning for defensive legendary perks, shared by gameplay and the Workbench.

@export_group("Counterweight Gate")
## Seconds after a non-breaking block to manually release guard and recover Stamina.
@export_range(0.1, 6.0, 0.01, "suffix:s") var counterweight_release_window := 1.8
## Stamina recovered, up to maximum Stamina. The ordinary recovery delay still applies.
@export_range(0.1, 20.0, 0.1, "suffix:Stamina") var counterweight_refund := 3.0
## Seconds after a refund before another successful block can arm the counterweight.
@export_range(0.1, 60.0, 0.1, "suffix:s") var counterweight_cooldown := 10.0
## Icon shown while a successful block has armed a refund.
@export var counterweight_icon: Texture2D

@export_group("Crown of the Still Bell")
## Percentage by which the first eligible new stun is shortened.
@export_range(0.0, 95.0, 0.5, "suffix:%") var still_bell_reduction := 30.0
## Shortest duration the Crown can bring a stun down to. Existing shorter stuns stay shorter.
@export_range(0.01, 0.65, 0.01, "suffix:s") var still_bell_minimum := 0.15
## Seconds after shortening a stun before the Crown can shorten another.
@export_range(0.1, 60.0, 0.1, "suffix:s") var still_bell_cooldown := 15.0
## Icon marking the Crown's recovery following an eligible stun.
@export var still_bell_icon: Texture2D

@export_group("Stonewake Spurs")
## Percentage increase to land movement while the perk is active.
@export_range(0.0, 60.0, 0.5, "suffix:%") var stonewake_speed_bonus := 15.0
## Seconds the wearer moves faster after a direct hit takes Life.
@export_range(0.1, 8.0, 0.01, "suffix:s") var stonewake_duration := 1.25
## Seconds from the direct hit to the next possible activation.
@export_range(0.1, 60.0, 0.1, "suffix:s") var stonewake_cooldown := 12.0
## Icon shown during the movement boost.
@export var stonewake_icon: Texture2D

@export_group("Hands of the Buttress")
## Minimum percentage of maximum Stamina remaining after blocking a melee hit.
@export_range(0.0, 100.0, 0.5, "suffix:%") var buttress_stamina_threshold := 50.0
## Percentage subtracted from incoming stun duration while the perk is active.
@export_range(0.0, 95.0, 0.5, "suffix:%") var buttress_stun_reduction := 50.0
## Seconds of protection after the qualifying block.
@export_range(0.1, 8.0, 0.01, "suffix:s") var buttress_duration := 1.2
## Seconds before another qualifying melee block can grant protection.
@export_range(0.1, 60.0, 0.1, "suffix:s") var buttress_cooldown := 8.0
## Icon shown while the perk is shortening incoming stuns.
@export var buttress_icon: Texture2D
