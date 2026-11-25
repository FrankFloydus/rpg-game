# Workbench and runtime data

Hearth Workbench is a Godot editor plugin for changing the same resources that Hearth Below reads in play. It owns the editing workflow. The resource and its runtime consumer own what a value means.

## Find the source

Open **Workbench** from the editor toolbar or **Project > Tools > Hearth Workbench**. The details pane shows the resource or scene path. Use that path to inspect the exported property and trace what it changes. Several records and even several categories can share one source file.

[The plugin](../../addons/hearth_workbench/plugin.gd) registers the toolbar and custom Inspector, and [the catalogue](../../addons/hearth_workbench/workbench_catalog.gd) defines the categories. [The Workbench window](../../addons/hearth_workbench/workbench_window.gd) routes selection to these editors.

| Catalogue entry | Editor and source |
| --- | --- |
| A resource path | The native Godot Inspector edits the exported properties of the draft. Inventory Item Appearance adds a live sample above that Inspector. |
| A path with `field` | A custom form edits one indexed array entry or keyed dictionary record. Affix Tiers pairs levels and multipliers from the same resource. |
| A path with `fields` | A custom form edits only the listed exported properties. The loot depth and merchant pages are views into the same loot resource. |
| A resource directory | The catalogue lists `.tres` resources that use the requested script class or a subclass. Abilities, effects, and weapon bob styles use this route. |
| A scene or scene directory | **Open Scene** opens the owning `.tscn` in Godot. **Open AnimationPlayer** is available on supported scenes. Save the scene or owning animation resource through Godot. Enemy discovery expects `combat/enemies/<folder>/<folder>.tscn`. |

Catalogue discovery and runtime registration are separate steps. A new enemy scene can appear in the Workbench before it is registered in [the enemy catalogue](../../combat/enemies/enemy_catalog.gd). A new preset must be referenced by a scene, loadout, or runtime owner before combat uses it.

## Drafts, saves, and reloads

- Drafts are keyed by source path. **Save Changes** writes all edits to the selected source file. Switching records or hiding the window keeps the draft in the editor session.
- `_load_source()` loads the draft with `CACHE_MODE_IGNORE`. The Workbench records its SHA-256 and can replace an unmodified draft when it next reads a changed file. A dirty draft is kept when its source changes externally. Save checks the source hash and reports the conflict, so preserve the desired edits and reconcile them before saving again.
- Custom edits explicitly mark their source dirty. The native Inspector reports committed edits. The Workbench also observes `Resource.changed` on owned subresources, such as an embedded Curve, including resources inside serialized arrays and dictionaries. The observer distinguishes resources belonging to another file.
- Validation runs before `ResourceSaver.save()`. A successful save refreshes the editor process's canonical resource with `CACHE_MODE_REPLACE`, clears that source's draft state, updates the editor filesystem, and builds a new draft from disk. **Reload** confirms discarding the selected source's edits, then reads its canonical resource and draft again.
- Save the resource that contains the property. Inline subresource changes belong to their containing file. An external effect or shared bob style has its own record and save operation. For example, changing an ability's on-hit effect selection saves the link in the ability, and changing the selected effect's duration belongs to the effect preset. A card's optional cue is duplicated into the card draft so editing its gain leaves the shared cue alone.
- A game run has its own process and can build derived tables at startup. Start a fresh run when verifying gameplay changes. Inventory appearance supports a specific live path for editor-launched play. While the inventory is visible, the game checks the saved appearance file periodically and redraws when it changes. See [the inventory panel](../../ui/inventory_ui.gd), [the shared painter](../../ui/inventory_appearance.gd), and [the Workbench sample](../../ui/inventory_appearance_preview.gd).

## Forms and inspection

[Custom forms](../../addons/hearth_workbench/workbench_fields.gd) bind the record's existing types. Percent spin boxes for loot and relevant card fields display percentage points and write fractions. Card rarity weights are relative weights. Effect chance is an exported percentage on the effect preset. Preserve `int`, `float`, `StringName`, `Vector2i`, and typed container shapes across the form callback and its serialized value. Existing records may omit optional keys, so check the runtime fallback when adding a control.

[The Inspector plugin](../../addons/hearth_workbench/workbench_inspector.gd) supplies behavior and element choices, hit profiles, effect links, and asset previews. [The ability schema](../../addons/hearth_workbench/workbench_ability_schema.gd) describes the visible controls for each shape. Update it alongside the consumer when a profile key changes. Some specialized ability scripts own the shape and lock that control. Keep IDs stable. IDs are used by save data, links between records, loadouts, or cooldowns. Fields displayed as rules can be read-only. For example, the application rule in [the Bleed definition](../../combat/effects/bleed_effect_definition.gd) describes its Physical-hit requirement and is computed by its script. Preserve read-only and usage flags when testing or editing these fields.

[The viewport preview](../../addons/hearth_workbench/workbench_preview.gd) displays an isolated scene with scripts and scene connections removed. It can replay particle emitters, orbit the model, and sample animation poses. Verify AI, damage, and timing in play. Gear previews resolve their icon through [ItemArt](../../ui/item_art.gd) and their held model through [HeldItemModels](../../data/items/held_item_models.gd). Card illustration is read from the card art ID. The inventory sample uses the same placed, hover, drop, and equipment-fit painters as the game, including the placed-fill alpha blend against the slot well.

[Weapon timing](../../addons/hearth_workbench/workbench_weapon_timing.gd) reads actual clips, including dual-wield variants, and allows scrubbing saved markers. Change weapon track and marker data in the owning AnimationPlayer, then check [attack animation resolution](../../combat/attack_animation.gd) and [the player attack loop](../../player/player.gd). For enemy windup and recovery, trace the ability's `runtime_profile()` and the enemy consumer. The clip preview shows poses, while the runtime can retime playback from gameplay values and floor-warning rules.

## Runtime ownership

| Question | Authored source | Runtime consumer |
| --- | --- | --- |
| Item families, base stats and implicits, footprints, item-level power | [Gear records](../../data/items/gear_records.tres) and [schema](../../data/items/gear_records.gd) | [Base data](../../data/items/bases.gd) and [Items](../../systems/items.gd). Per-base footprints take priority over family defaults. |
| Prefixes, suffixes, stat ranges, tiers, materials, and recipes | [Affix records](../../data/items/affix_records.tres) and [schema](../../data/items/affix_records.gd) | [Affix data](../../data/items/affixes.gd) and [Items](../../systems/items.gd). An omitted `slots` field means any slot. A present list restricts eligibility. Material level gates the generic random pool. Enemy-specific part drops come from the assigned part. |
| Rare item naming and legendary generation | [Rare name pools](../../data/items/item_name_records.tres) and [legendary records](../../data/items/legendary_records.tres) | [Rare name selection](../../data/items/item_name_records.gd), [legendary table](../../data/items/legendaries.gd), and [Items](../../systems/items.gd). Legendary entries reference stable gear base IDs. |
| Item and card drops, depth endpoints, coffer rewards, hub merchant stock | [Loot records](../../data/items/loot_records.tres) and [schema](../../data/items/loot_records.gd) | [Items](../../systems/items.gd), [CardCatalog](../../data/card_catalog.gd), and the reward paths in [main](../../main.gd). |
| Card details, activation, and sound | Card definitions in [loot records](../../data/items/loot_records.tres) and [sound catalogue](../../assets/audio/sound_catalogue.tres) | [Card effects](../../combat/cards/card_effects.gd), [card catalogue](../../data/card_catalog.gd), and [GameAudio](../../systems/game_audio.gd). Entry data and the selected effect script together determine behavior. |
| Player level, base Life, XP, attributes, level disparity | [Progression records](../../data/player_progression_records.tres) and [schema](../../data/player_progression_records.gd) | [CharacterProgression](../../systems/character_progression.gd), [Items](../../systems/items.gd), and [player](../../player/player.gd). |
| Enemy base Life, damage, movement, loadouts, and level curves | [Enemy scenes](../../combat/enemies/), [enemy catalogue](../../combat/enemies/enemy_catalog.gd), and [enemy scaling](../../combat/enemies/enemy_scaling.tres) | [Enemy stat resolver](../../combat/enemies/enemy_stat_resolver.gd) and [enemy runtime](../../combat/enemies/enemy.gd). |
| Expedition-specific depth difficulty | [Depth difficulty](../../data/depth_difficulty.tres) and [schema](../../data/depth_difficulty.gd) | [Expedition spawn setup](../../main.gd) applies the exact-depth multiplier to enemy Life and damage. Training uses actor level separately. |
| Ability timing, damage, geometry, icons, and on-hit effects | [Ability definitions](../../combat/abilities/), [effect definitions](../../combat/effects/), and the loadouts in their owning scenes | [Enemy runtime](../../combat/enemies/enemy.gd) or [player](../../player/player.gd) with [Bestiary metadata](../../data/bestiary.gd) feeding the Bestiary and Combat Log. |
| Weapon damage coefficients, attack tempo, stamina, and aim or gait behavior | [Weapon balance](../../data/player_weapon_balance.tres), [attack tempo](../../data/attack_tempo.tres), [stamina](../../data/stamina_rules.tres), [player scene](../../player/player.tscn), and [weapon motion resources](../../player/weapon_sway/) | [Weapon roles](../../combat/weapons/weapon_roles.gd), [player](../../player/player.gd), and [the weapon rig](../../player/weapon_sway/crimson_weapon_rig.gd). |
| Telegraphs, hit reactions, severance, rarity tint, and camera blood | [Telegraph rules](../../data/telegraph_rules.tres), [combat feedback](../../data/combat_feedback.tres), [impact feedback](../../data/impact_feedback.tres), [rarity style](../../data/enemy_rarity_style.tres), and [screen blood rules](../../data/screen_blood_rules.tres) | [Enemy runtime](../../combat/enemies/enemy.gd), [enemy model](../../combat/enemies/enemy_model.gd), [dungeon hazards](../../world/dungeon_hazard.gd), [impact dismemberment](../../combat/effects/impact_dismemberment.gd), and [camera feedback](../../player/effects/camera/camera_feedback.gd). |
| Legendary special behavior | [Melee](../../data/weapon_legendary_rules.tres), [defensive](../../data/defensive_legendary_rules.tres), [caster](../../data/caster_legendary_rules.tres), and [exploration](../../data/legendary_exploration_rules.tres) resources | [Melee legendary runtime](../../combat/weapons/legendary_weapon_runtime.gd), [defensive runtime](../../combat/effects/defensive_legendary_runtime.gd), [caster effects](../../combat/effects/caster_legendary_effects.gd), and [wall clues](../../world/dungeon_wall_clues.gd). A new effect ID needs its runtime implementation. |
| Expedition pacing, events, altar, and hidden merchant | [Expedition rules](../../data/expedition_rules.tres), [blood altar rules](../../data/blood_altar_rules.tres), and [secret merchant rules](../../data/secret_merchant_rules.tres) | [Dungeon](../../world/dungeon.gd), [expedition features](../../world/expedition_features.gd), [main](../../main.gd), and [merchant generation in Items](../../systems/items.gd). |
| Pack, stash, merchant, and equipment item states | [Inventory item appearance](../../data/inventory_item_style.tres) and [schema](../../data/inventory_item_style.gd) | [Shared inventory painter](../../ui/inventory_appearance.gd), [inventory grids](../../ui/inventory_grid.gd), [equipment slots](../../ui/inventory_equipment_slot.gd), and [carry preview](../../ui/inventory_carry.gd). |

## Invariants and compatibility

[Workbench validation](../../addons/hearth_workbench/workbench_validation.gd) is a preflight for the edited source. External edits to `.tres` files bypass it. Verify runtime behavior and saved data separately.

- **Gear and progression.** Gear families need legal slots and grid dimensions. Base damage minima must be at most their maxima. Power curve levels must increase and multipliers must be positive. Player Life points also need increasing levels and positive values.
- **Affixes and recipes.** Keep minimum tier levels in ascending order and multipliers positive. The display labels count down toward Tier 1 as strength increases. Stat roll minima must fit their maxima. The recipe's affix ID must exist on its declared prefix or suffix side.
- **Legendaries and loot.** Legendary bases and fixed-stat tiers must exist. Positive finite weights and ordered roll bounds matter. With a Normal minimum, Magic and Rare share one roll, so their chances sum to at most 100%. With a Magic minimum, only the Rare chance among those two can change the result. With a Rare minimum, both are dormant. The Legendary roll is separate and still subject to eligibility. The form keeps currently dormant values available if the minimum is later lowered.
- **Ability profiles.** Validate the resolved `runtime_profile()`. Keep required attack shapes, positive ranges, a smaller ring inner radius than outer reach, and positive lane widths. AI start range and hit footprint can be tuned separately. An enemy's defined shapes and gameplay events must still resolve when placed in a real loadout.
- **Depth difficulty.** Use integer depth keys and float multipliers. The runtime uses the default for missing keys, guards against non-finite values, and clamps positive expedition depths to a minimum multiplier. The enemy level curves and rarity multipliers still apply in their own stages.
- **Seeded rolls and old saves.** Godot can reorder dictionary keys on save. Keep `card_order` and `material_order` coherent with additions and deletions. Preserve IDs and positional catalogue entries relied on by existing checkpoints, and preserve legacy restoration paths in [Items](../../systems/items.gd), [the original affix ranges](../../data/items/original_affix_ranges.gd), and [enemy stat restoration](../../combat/enemies/enemy_stat_resolver.gd). For a migration, test a previously saved item or run as well as a new roll.

## Verification

See [engineering and verification](engineering-and-verification.md) for project-wide setup and test guidance.

Use an isolated project copy for editor save probes that deliberately change values. Open the actual Workbench control, make a distinctive valid edit, confirm the selected source path and dirty state, and press **Save Changes**. Check the on-disk resource with a cache-ignoring load, the intended cache consumer in the editor process, and the value shown after **Reload**. Test that unrelated records remain intact in shared resources. For nested changes use the actual embedded resource or Inspector control. For scene entries, open the scene from Workbench, save it in Godot, and instantiate it from disk. For a conflict test, edit the same file externally while its Workbench draft is dirty and check that the original draft can still be reviewed.

Use a separate game process as a runtime check. Examples from the project root, with Godot 4.7 on PATH:

```powershell
godot --headless --path . --script res://tests/inventory_revision.gd
godot --headless --path . --script res://tests/item_rarity_matrix.gd
godot --headless --path . --script res://tests/character_progression.gd
godot --headless --path . --script res://tests/combat_timeline_editing.gd
godot --path . --script res://tests/inventory_appearance_render.gd
```

Use [the loot balance matrix](../../tests/balance_loot_matrix.gd) for seeded loot and merchant comparisons, [legendary rolls](../../tests/legendary_rolls.gd) for eligibility and fixed stats, [deck cards](../../tests/deck_cards.gd) for card behavior, [Training Ground](../../tests/training_ground.gd) for runtime enemy authoring, and [expedition events](../../tests/expedition_events.gd) or [secret broker trade](../../tests/secret_broker_trade.gd) for those rules. The inventory appearance render check needs a native renderer for pixel readback. Inspect the editor preview and game for tint, transparency, and state changes when modifying the painter. Compile and headless data checks address different parts of the contract.
