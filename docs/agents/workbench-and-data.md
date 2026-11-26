# Workbench and runtime data

Hearth Workbench is a Godot editor plugin for changing the same resources that Hearth Below reads in play. It owns the editing workflow. The resource and its runtime consumer own what a value means.

## Find the source

Open **Workbench** from the editor toolbar or **Project > Tools > Hearth Workbench**. The workspace starts in **Weapons & Player → Weapons**. The sidebar groups sections by authoring task. Pick a record beside it, then use the main pane to edit or preview it. Weapon records have separate **Model**, **Attack timing**, and, for supported weapons, **Hit feedback** tabs. Hover the source description or the status line to identify the file behind the current view. Several records and sections can share one file.

| Action | Shortcut |
| --- | --- |
| **Quick find** searches all sections, record names and IDs, settings, and available actions. Try `mace hit shake`, `attack tempo`, or a property name. | **Ctrl+K**, then **↑/↓** and **Enter**. **Esc** closes the search. |
| **Filter records** narrows the current section by name or ID. On a single native resource page, this shortcut focuses **Filter properties**. Use **Expand** and **Collapse** to control native property groups. | **Ctrl+F** |
| **Browse** toggles the sidebar and record list to make room for the current editor. | **Ctrl+B** |
| **Save** writes the active source. The footer identifies the scope of the edit and shows pending drafts across sources. | **Ctrl+S** |

[The plugin](../../addons/hearth_workbench/plugin.gd) registers the toolbar and custom Inspector. [The catalogue](../../addons/hearth_workbench/workbench_catalog.gd) owns stable section IDs, labels and descriptions. [The window](../../addons/hearth_workbench/workbench_window.gd) binds [the workspace layout](../../addons/hearth_workbench/workbench_layout.tscn), [theme](../../addons/hearth_workbench/workbench_style.gd), and [Quick find](../../addons/hearth_workbench/workbench_quick_find.gd) to the catalogue and draft editors.

| Catalogue entry | Editor and source |
| --- | --- |
| A resource path | The native Godot Inspector edits the exported properties of the draft with source-authored tooltips and a property filter. Inventory Appearance adds a live sample. |
| A path with `field` | A custom form edits one indexed array entry or keyed dictionary record. Affix Tiers pairs levels and multipliers from the same resource. |
| A path with `fields` | A custom form edits only the listed exported properties. The loot depth and merchant pages are views into the same loot resource. |
| A resource directory | The catalogue lists `.tres` resources that use the requested script class or a subclass. Abilities, effects, and weapon bob styles use this route. |
| A scene or scene directory | **Open Scene** opens the owning `.tscn` in Godot. **Open AnimationPlayer** is available on supported scenes. Save the scene or owning animation resource through Godot. Enemy discovery expects `combat/enemies/<folder>/<folder>.tscn`. |

Catalogue discovery and runtime registration are separate steps. A new enemy scene can appear in the Workbench before it is registered in [the enemy catalogue](../../combat/enemies/enemy_catalog.gd). A new preset must be referenced by a scene, loadout, or runtime owner before combat uses it.

## Drafts, saves, and reloads

- Drafts are keyed by source path. **Save** writes all edits to the selected source file, even when they were made in different records from that file. Switching records or hiding the window keeps the draft in the editor session.
- `_load_source()` loads the draft with `CACHE_MODE_IGNORE`. The Workbench records its SHA-256 and can replace an unmodified draft when it next reads a changed file. A dirty draft is kept when its source changes externally. Save checks the source hash and reports the conflict, so preserve the desired edits and reconcile them before saving again.
- Custom edits explicitly mark their source dirty. The native Inspector reports committed edits. The Workbench also observes `Resource.changed` on owned subresources, such as an embedded Curve, including resources inside serialized arrays and dictionaries. The observer distinguishes resources belonging to another file.
- Validation runs before `ResourceSaver.save()`. A successful save refreshes the editor process's canonical resource with `CACHE_MODE_REPLACE`, clears that source's draft state, updates the editor filesystem, and builds a new draft from disk. **Reload** asks before discarding a dirty draft. A clean source reloads immediately.
- Save the resource that contains the property. Inline subresource changes belong to their containing file. An external effect or shared bob style has its own record and save operation. For example, changing an ability's on-hit effect selection saves the link in the ability, and changing the selected effect's duration belongs to the effect preset. A card's optional cue is duplicated into the card draft so editing its gain leaves the shared cue alone.
- A game run has its own process and can build derived tables at startup. Start a fresh run when verifying gameplay changes. Inventory appearance supports a specific live path for editor-launched play. While the inventory is visible, the game checks the saved appearance file periodically and redraws when it changes. See [the inventory panel](../../ui/inventory_ui.gd), [the shared painter](../../ui/inventory_appearance.gd), and [the Workbench sample](../../ui/inventory_appearance_preview.gd).

## Forms and inspection

[Custom forms](../../addons/hearth_workbench/workbench_fields.gd) bind the record's existing types and group related controls. Hover a property label or input for its meaning and unit. [Property help](../../addons/hearth_workbench/workbench_property_help.gd) owns descriptions for dictionary-backed fields. Exported Resource properties use their script's `##` documentation. Percent spin boxes for loot and relevant card fields display percentage points and write fractions. Card rarity weights are relative weights. Effect chance is an exported percentage on the effect preset. Preserve `int`, `float`, `StringName`, `Vector2i`, and typed container shapes across the form callback and its serialized value. Existing records may omit optional keys, so check the runtime fallback when adding a control.

[The Inspector plugin](../../addons/hearth_workbench/workbench_inspector.gd) supplies behavior and element choices, hit profiles, effect links, and asset previews. For an ability, expand **Execution** and open **Hit shape and targeting**. The footprint shows the caster, hit area, and AI start range. [The ability schema](../../addons/hearth_workbench/workbench_ability_schema.gd) owns the controls for each shape. Update it alongside the consumer when a profile key changes. Some specialized ability scripts own the shape and lock that control. Keep IDs stable. IDs are used by save data, links between records, loadouts, or cooldowns. Fields displayed as rules can be read-only. For example, the application rule in [the Bleed definition](../../combat/effects/bleed_effect_definition.gd) describes its Physical-hit requirement and is computed by its script. Preserve read-only and usage flags when testing or editing these fields.

[The viewport preview](../../addons/hearth_workbench/workbench_preview.gd) displays an isolated scene with scripts and scene connections removed. It can replay particle emitters, orbit the model, and sample animation poses. Verify AI, damage, and timing in play. Gear previews resolve their icon through [ItemArt](../../ui/item_art.gd) and their held model through [HeldItemModels](../../data/items/held_item_models.gd). Card illustration is read from the card art ID. The inventory sample uses the same placed, hover, drop, and equipment-fit painters as the game, including the placed-fill alpha blend against the slot well.

[Weapon timing](../../addons/hearth_workbench/workbench_weapon_timing.gd) reads actual clips, including dual-wield variants, and allows scrubbing saved markers. Change weapon track and marker data in the owning AnimationPlayer, then check [attack animation resolution](../../combat/attack_animation.gd) and [the player attack loop](../../player/player.gd). For enemy windup and recovery, trace the ability's `runtime_profile()` and the enemy consumer. The clip preview shows poses, while the runtime can retime playback from gameplay values and floor-warning rules.

For the mace, open **Weapons → Mace 2H → Attack timing** and choose a light swing. `Input Buffer` is the outgoing link gate. Move it later to slow down the chain. `Combo Exit` controls the outgoing follow-through pose and `Combo Entry` controls the incoming windup pose. Leave the trace markers in place when tuning the handoff. To change how long a click stays queued, open **Weapons & Player → Movement & charge → Open scene** and edit **Mace Followup Buffer Seconds** under **Abilities** on the Player node.

In the same Player scene, **Movement → Mace Surge Speed Multiplier** sets the peak ground speed target for held movement during mace swings. The default is `1.40×`, and `1.00×` removes the above-normal speed burst while retaining the opening brace. Save the Player scene and test a tap and a charged release while moving in the Training Ground.

On each mace attack, `Terrain Start` arms the surface checks. Charges can catch a close surface during that approach and stop once they reach `Impact`, if the surface still blocks the head. `Impact` also supplies the pose for the catch. `Trace Start` controls when enemy tracing opens. Scrub to the main cut before tuning and verify a direct and a grazing contact in the Training Ground. [Mace contacts](combat-and-player.md#two-handed-mace-contacts)

### Tune melee reach and cleave

Open **Weapons & Player → Melee contact**, select the weapon family, then use **Light** or **Charged**. **Reach assist cap** sets the maximum extension past the scaled animated span. **Target reach** bounds that extension from gameplay aim. **Sweep width** and **Sweep height** set the damage volume dimensions. Increase the selected family's assist cap if its trace already reaches the cap. The mace's physical wall stop uses the separate head markers and its own collision query. **Attack timing** controls the slice of the animation where the live sweep runs.

The same profile sets independent **Damage cleave budget** and **Stagger cleave budget** at reference attack power. The item attack-power curve and the attack's scaling attribute determine live power. **Slide through armor** allows an armored contact to consume mass and continue while the remaining budget permits. **Weapons & Player → Melee rules** owns the shared contact cone, downcut target preference, refuge sweep multipliers, cleave power scaling and adjusted mass. Both pages save [the melee contact resource](../../data/melee_contact.tres).

Save, reload, and test the selected swing in a new game process. From the Training Ground's **Weaponry** tab, turn on **Show Player Weapon Traces** and choose a **Contact Preset**. **Training** uses full reach with solid stops, **Carry Through** uses full reach with wall effects, and **Refuge** uses the shorter, narrower sweep with solid stops.

### Edit curves directly

Use the plot to select and drag a point. Double-click the plot or press **Insert** to add a point. Press **Enter** to cycle points, the arrows to nudge the selection, **Shift** with the arrows for a larger nudge, **Delete** to remove it, or **Esc** to cancel a drag. The fields under the plot let you set the selected point precisely. Godot Curve resources also expose tangent handles and tangent modes. Owned subresources are updated in the draft and use the same Save and Reload path as other edits. External Curve assets open through their source. [Curve editor](../../addons/hearth_workbench/workbench_curve_editor.gd) and [Inspector integration](../../addons/hearth_workbench/workbench_curve_property.gd)

**Progression → Life by level** edits the existing linearly interpolated level and Life values as a plot. **Progression → Item power by level** edits the attack and defense multiplier curves at shared levels. Inserting a level calculates its other multiplier from the existing curve. Moving a point keeps the other multiplier at that level, and removing a level removes it from both curves. The graphs preserve the typed data and runtime interpolation. [Paired curves](../../addons/hearth_workbench/workbench_power_curves.tscn)

Defensive item power now grows more strongly above item level 10, reaching `1.32×` at 15 and `2.18×` at 30. This applies to core armor, Ward, maximum Life, and maximum Stamina. New affixes retain the existing partial power rule. Existing gear restores the authored defensive base and implicit values once while keeping its rolled affixes. **Weapons & Player → Weapon damage** owns the two-handed charge multiplier. In **Cards**, Red Mercy restores `35%` of maximum Life and The Last Hearth restores `55%` and deals `250%` average weapon damage plus 5 as Fire. Their description and values share the [loot records](../../data/items/loot_records.tres).

### Tune weapon hit shake

Open **Weapons & Player → Weapons**, select **Mace 2H** or another supported weapon, then open **Hit feedback**. Choose **Contact**, **Attack** (Light or Charged), and **Direction**. The two-handed mace offers left and right lateral swings plus down-left and down-right lights. Flesh and breakables have their own profiles, alongside stone, metal, and solid wood. The two-handed mace also has profiles for armor, guard, and reaching the cleave limit.

Edit **Pitch**, **Yaw**, and **Roll** in degrees and **Duration** in seconds. The first-person preview replays the selected impact when a value changes. On **Breakable**, **Stone**, **Metal**, or **Wood**, choose **Response → Hard stop** or **Carry through**. The hard stop represents a stopping prop or an eligible Refuge wall. Carry-through represents a hit-through prop or a wall in the Carry Through practice preset. The response selector changes the preview alone and shares the saved tuning for that material. A wall contact in the Carry Through preset keeps the swing moving and plays world effects, and a hit-through prop applies its camera kick on a charged strike.

The preview samples the swing near its authored `Impact` to drive the test hit's position and direction. A mace hard stop uses the gameplay rebound and arm solve. Other weapons blend from contact into idle. The preview supplies its own contact surface to replay a consistent hit. The weapon rebound also plays with the shake axes set to zero. **Replay hit** triggers the impact immediately and **Loop** controls repetition.

Profiles are saved by weapon family, contact, attack weight, and authored direction in [weapon hit shake](../../data/weapon_hit_shake.tres). A direction with no override inherits the shared weapon/contact/weight values, then the [built-in defaults](../../data/weapon_hit_shake.gd), which distinguish mace lateral swings, downcuts and charges. The form shows where the current values come from. **Reset direction** removes the selected override in the draft. **Save** applies the draft and **Reload** reads it back. Use the weapon's **Attack timing** tab to find its marker tracks in the owning AnimationPlayer.

The mace's pitch, yaw and roll strengths scale separate recoil phases. To compare the bank and recovery, try **Stone → Light → Left** and **Stone → Light → Down Left**, then switch to **Flesh → Charged** for the quicker breakthrough kick. **Guard** in this panel refers to a strike that meets an enemy guard. The preview uses a synthetic contact normal. Verify a real hit in the Training Ground for the strength at the angle you expect to play.

For the charged leftward solid catch, the preview also uses the live rebound's sleeve blend. Inspect the forearm on the way into the catch and during its hold. The preview's synthetic hit is useful for the deformation check. Use a close pillar in the Training Ground to check the surface fit and wrist framing.

## Runtime ownership

| Question | Authored source | Runtime consumer |
| --- | --- | --- |
| Item families, base stats and implicits, footprints, item-level power | [Gear records](../../data/items/gear_records.tres) and [schema](../../data/items/gear_records.gd) | [Base data](../../data/items/bases.gd) and [Items](../../systems/items.gd). Per-base footprints take priority over family defaults. |
| Prefixes, suffixes, stat ranges, tiers, materials, and recipes | [Affix records](../../data/items/affix_records.tres) and [schema](../../data/items/affix_records.gd) | [Affix data](../../data/items/affixes.gd) and [Items](../../systems/items.gd). An omitted `slots` field means any slot. A present list restricts eligibility. Material level gates the generic random pool. Enemy-specific part drops come from the assigned part. |
| Rare item naming and legendary generation | [Rare name pools](../../data/items/item_name_records.tres) and [legendary records](../../data/items/legendary_records.tres) | [Rare name selection](../../data/items/item_name_records.gd), [legendary table](../../data/items/legendaries.gd), and [Items](../../systems/items.gd). Legendary entries reference stable gear base IDs. |
| Gear and card tier profiles, crafting materials, and hub merchant stock | [Loot records](../../data/items/loot_records.tres) and [schema](../../data/items/loot_records.gd) | [Items](../../systems/items.gd), [CardCatalog](../../data/card_catalog.gd), and the reward paths in [main](../../main.gd). |
| Card details, activation, and sound | Card definitions in [loot records](../../data/items/loot_records.tres) and [sound catalogue](../../assets/audio/sound_catalogue.tres) | [Card effects](../../combat/cards/card_effects.gd), [card catalogue](../../data/card_catalog.gd), and [GameAudio](../../systems/game_audio.gd). Entry data and the selected effect script together determine behavior. |
| Player level, base Life, XP, attributes, level disparity | [Progression records](../../data/player_progression_records.tres) and [schema](../../data/player_progression_records.gd) | [CharacterProgression](../../systems/character_progression.gd), [Items](../../systems/items.gd), and [player](../../player/player.gd). |
| Enemy base Life, damage, movement, loadouts, and level curves | [Enemy scenes](../../combat/enemies/), [enemy catalogue](../../combat/enemies/enemy_catalog.gd), and [enemy scaling](../../combat/enemies/enemy_scaling.tres) | [Enemy stat resolver](../../combat/enemies/enemy_stat_resolver.gd) and [enemy runtime](../../combat/enemies/enemy.gd). |
| Ability timing, damage, geometry, icons, and on-hit effects | [Ability definitions](../../combat/abilities/), [effect definitions](../../combat/effects/), and the loadouts in their owning scenes | [Enemy runtime](../../combat/enemies/enemy.gd) or [player](../../player/player.gd) with [Bestiary metadata](../../data/bestiary.gd) feeding the Bestiary and Combat Log. |
| Weapon damage coefficients, attack tempo, stamina, and aim or gait behavior | [Weapon balance](../../data/player_weapon_balance.tres), [attack tempo](../../data/attack_tempo.tres), [stamina](../../data/stamina_rules.tres), [player scene](../../player/player.tscn), and [weapon motion resources](../../player/weapon_sway/) | [Weapon roles](../../combat/weapons/weapon_roles.gd), [player](../../player/player.gd), and [the weapon rig](../../player/weapon_sway/crimson_weapon_rig.gd). |
| Melee sweep geometry, target preference, and damage or stagger cleave | [Melee contact](../../data/melee_contact.tres) and [schema](../../data/melee_contact.gd) | [Melee sweep](../../player/melee_sweep.gd), [cleave rules](../../combat/weapons/melee_contact_rules.gd), and [player](../../player/player.gd). |
| First-person camera shake from weapon contacts | [Weapon hit shake](../../data/weapon_hit_shake.tres) | [Camera feedback](../../player/effects/camera/camera_feedback.gd) and the [Workbench first-person preview](../../addons/hearth_workbench/workbench_hit_shake_preview.gd). |
| Telegraphs, hit reactions, severance, rarity tint, and camera blood | [Telegraph rules](../../data/telegraph_rules.tres), [combat feedback](../../data/combat_feedback.tres), [impact feedback](../../data/impact_feedback.tres), [rarity style](../../data/enemy_rarity_style.tres), and [screen blood rules](../../data/screen_blood_rules.tres) | [Enemy runtime](../../combat/enemies/enemy.gd), [enemy model](../../combat/enemies/enemy_model.gd), [impact dismemberment](../../combat/effects/impact_dismemberment.gd), and [camera feedback](../../player/effects/camera/camera_feedback.gd). |
| Legendary special behavior | [Melee](../../data/weapon_legendary_rules.tres), [defensive](../../data/defensive_legendary_rules.tres), and [caster](../../data/caster_legendary_rules.tres) resources | [Melee legendary runtime](../../combat/weapons/legendary_weapon_runtime.gd), [defensive runtime](../../combat/effects/defensive_legendary_runtime.gd), and [caster effects](../../combat/effects/caster_legendary_effects.gd). A new effect ID needs its runtime implementation. |
| Enemy corpse and Training trace lifetime | [Combat lifetime rules](../../data/combat_lifetime_rules.tres) | [Enemy runtime](../../combat/enemies/enemy.gd) and [Training trace](../../combat/effects/training_weapon_trace.gd). Edit these settings in **Encounters → Combat lifetimes**. |
| Pack, stash, merchant, and equipment item states | [Inventory item appearance](../../data/inventory_item_style.tres) and [schema](../../data/inventory_item_style.gd) | [Shared inventory painter](../../ui/inventory_appearance.gd), [inventory grids](../../ui/inventory_grid.gd), [equipment slots](../../ui/inventory_equipment_slot.gd), and [carry preview](../../ui/inventory_carry.gd). |

## Invariants and compatibility

[Workbench validation](../../addons/hearth_workbench/workbench_validation.gd) is a preflight for the edited source. External edits to `.tres` files bypass it. Verify runtime behavior and saved data separately.

- **Gear and progression.** Gear families need legal slots and grid dimensions. Base damage minima must be at most their maxima. Power curve levels must increase and multipliers must be positive. Player Life points also need increasing levels and positive values.
- **Affixes and recipes.** Keep minimum tier levels in ascending order and multipliers positive. The display labels count down toward Tier 1 as strength increases. Stat roll minima must fit their maxima. The recipe's affix ID must exist on its declared prefix or suffix side.
- **Legendaries and loot.** Legendary bases and fixed-stat tiers must exist. Positive finite weights and ordered roll bounds matter. With a Normal minimum, Magic and Rare share one roll, so their chances sum to at most 100%. With a Magic minimum, only the Rare chance among those two can change the result. With a Rare minimum, both are dormant. The Legendary roll is separate and still subject to eligibility. The form keeps currently dormant values available if the minimum is later lowered.
- **Ability profiles.** Validate the resolved `runtime_profile()`. Keep required attack shapes, positive ranges, a smaller ring inner radius than outer reach, and positive lane widths. AI start range and hit footprint can be tuned separately. An enemy's defined shapes and gameplay events must still resolve when placed in a real loadout.
- **Seeded rolls and old saves.** Godot can reorder dictionary keys on save. Keep `card_order` and `material_order` coherent with additions and deletions. Preserve IDs and positional catalogue entries relied on by existing checkpoints, and preserve legacy restoration paths in [Items](../../systems/items.gd), [the original affix ranges](../../data/items/original_affix_ranges.gd), and [enemy stat restoration](../../combat/enemies/enemy_stat_resolver.gd). For a migration, test a previously saved item or run as well as a new roll.

## Verification

See [engineering and verification](engineering-and-verification.md) for project-wide setup and test guidance.

Use an isolated project copy for editor save probes that deliberately change values. Launch from the actual Workbench toolbar. Check Quick find keyboard selection, record filtering, and the compact layout. Drag a point in a real Curve, confirm dirty state, then save and reload the owning resource. Set a distinctive value for one direction in Hit feedback and switch to another direction on the same weapon and contact to check inheritance. Check the serialized resource with a cache-ignoring load and the editor's canonical resource as well as the UI. For scene entries, open the scene from Workbench, save it in Godot, and instantiate it from disk. For a conflict test, edit the same file externally while its Workbench draft is dirty and check that the draft is preserved.

Use a separate game process as a runtime check. Examples from the project root, with Godot 4.7 on PATH:

```powershell
godot --headless --path . --script res://tests/inventory_revision.gd
godot --headless --path . --script res://tests/item_rarity_matrix.gd
godot --headless --path . --script res://tests/character_progression.gd
godot --headless --path . --script res://tests/combat_timeline_editing.gd
godot --headless --path . --script res://tests/weapon_hit_shake.gd
godot --headless --path . --script res://tests/workbench_curve_editing.gd
godot --path . --script res://tests/inventory_appearance_render.gd
```

[The curve regression](../../tests/workbench_curve_editing.gd) exercises an insert and remove through the graph and checks the resulting tangent modes and sampled shape. [The hit shake regression](../../tests/weapon_hit_shake.gd) exercises direction inheritance, save/reload, the camera feedback path, and the preview's hard-stop return to the authored ready pose.

Use [legendary rolls](../../tests/legendary_rolls.gd) for eligibility and fixed stats, [deck cards](../../tests/deck_cards.gd) for card behavior, and [Training Ground](../../tests/training_ground.gd) for runtime enemy authoring. Use [campaign integration](../../tests/integration.gd) for starting merchant stock and character restore. The inventory appearance render check needs a native renderer for pixel readback. Inspect the editor preview and game for tint, transparency, and state changes when modifying the painter. Compile and headless data checks address different parts of the contract.
