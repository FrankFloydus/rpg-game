class_name HearthSoundCatalogue
extends Resource
## The sound assignments for Hearth Below. Each inspector entry can contain several audio files.

const SoundCue = preload("res://systems/sound_cue.gd")

@export_group("Weapon Swings")
## Light swings with one-handed swords and daggers.
@export var light_blade_swing: SoundCue
## Two-handed sword swings and heavier one-handed blade attacks.
@export var heavy_blade_swing: SoundCue
## Mace and axe swings.
@export var blunt_swing: SoundCue
## Bare-handed attacks.
@export var unarmed_swing: SoundCue

@export_group("Combat")
## Player hit confirmation when an attack deals positive damage. Heavier weapons play it lower and louder.
@export var hit: SoundCue
## Feedback on a damaging hit received by the player.
@export var player_hit: SoundCue
## Guard contact, including hits that exhaust Stamina and break guard.
@export var block: SoundCue
## One-shot at the release of a player spell or staff cast.
@export var spell_cast: SoundCue
## Player feedback when an enemy is defeated.
@export var kill: SoundCue
## Player defeat cue, including the Training Ground reset.
@export var death: SoundCue
## Reserved catalogue cue for a drink event.
@export var drink: SoundCue

@export_group("Movement")
## Grounded foot contact at walking pace.
@export var walk: SoundCue
## Heavier grounded foot contact while sprinting.
@export var sprint: SoundCue
## Grounded push-off at the start of a jump.
@export var jump: SoundCue
## Weight returning to the ground after genuine airtime.
@export var land: SoundCue
## Fallback when the walk or sprint cue has no playable clip.
@export var step: SoundCue

@export_group("Travel and Loot")
## Travel cue for portal transitions, including entering and leaving the Training Ground.
@export var portal: SoundCue
## Loot feedback used for pickups and unlocked rewards.
@export var loot: SoundCue

@export_group("Equipment and Trade")
## Generic sound for a completed purchase or sale. Inventory interactions may use their item placement cue.
@export var trade: SoundCue
## Confirms a completed crafting transaction.
@export var craft: SoundCue
## Equipment change confirmation outside the inventory grid.
@export var equip: SoundCue
## Feedback when an action fails or a requirement blocks it.
@export var error: SoundCue

@export_group("Item Handling")
## An item is lifted onto the cursor.
@export var item_grab: SoundCue
## A light, short metal blade settles into a slot.
@export var item_place_dagger_1h: SoundCue
## A one-handed blade settles into a slot.
@export var item_place_sword_1h: SoundCue
## A heavy two-handed blade settles into a slot.
@export var item_place_sword_2h: SoundCue
## A one-handed axe settles into a slot.
@export var item_place_axe_1h: SoundCue
## A heavy axe settles into a slot.
@export var item_place_axe_2h: SoundCue
## A one-handed mace settles into a slot.
@export var item_place_mace_1h: SoundCue
## A heavy mace settles into a slot.
@export var item_place_mace_2h: SoundCue
## A wooden or bound staff settles into a slot.
@export var item_place_staff: SoundCue
## A shield settles into a slot.
@export var item_place_shield: SoundCue
## A caster focus settles into a slot.
@export var item_place_focus: SoundCue
## A caster orb settles into a slot.
@export var item_place_orb: SoundCue
## A helm settles into a slot.
@export var item_place_helm: SoundCue
## Body armour settles into a slot.
@export var item_place_chest: SoundCue
## Gloves settle into a slot.
@export var item_place_gloves: SoundCue
## Boots settle into a slot.
@export var item_place_boots: SoundCue
## A belt settles into a slot.
@export var item_place_belt: SoundCue
## An amulet settles into a slot.
@export var item_place_amulet: SoundCue
## A ring settles into a slot.
@export var item_place_ring: SoundCue
## A crafting material or bundle settles into a slot.
@export var item_place_material: SoundCue
## A treasure or route key settles into a slot.
@export var item_place_key: SoundCue
## An identification scroll settles into a slot.
@export var item_place_scroll: SoundCue
## A physical card settles into a slot.
@export var item_place_card: SoundCue
## Fallback for item types without an assigned cue.
@export var item_place_generic: SoundCue

@export_group("Cards")
## Plays once when a new card is highlighted.
@export var card_hover: SoundCue
## Default for cards that restore Life.
@export var card_use_heal: SoundCue
## Default for fire bursts and other primarily fire cards.
@export var card_use_fire: SoundCue
## Default for cold bursts and chills.
@export var card_use_cold: SoundCue
## Default for lightning and shock-like effects.
@export var card_use_lightning: SoundCue
## Default for direct physical bursts.
@export var card_use_physical: SoundCue
## Default for temporary offensive buffs.
@export var card_use_buff: SoundCue
## Default for protection and stamina recovery.
@export var card_use_guard: SoundCue
## Default for cards that conjure allies.
@export var card_use_summon: SoundCue

@export_group("Breakables")
## Spatial cue played at a wooden crate when it breaks.
@export var crate_break: SoundCue
## Spatial cue shared by breakable pottery and ceramic urns.
@export var pottery_break: SoundCue

@export_group("Ambience")
## Loop while in Cinderhold Refuge. Playback uses the first assigned clip and crossfades on zone changes.
@export var hub_ambience: SoundCue
## Loop in the Training Ground. Playback uses the first assigned clip and crossfades on zone changes.
@export var training_ambience: SoundCue


func sound_for(event: StringName) -> SoundCue:
	return get(event) as SoundCue
