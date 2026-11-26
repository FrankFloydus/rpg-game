# World locations and asset authoring

Hearth Below uses Godot 4.7 Forward+. The [world](../../world/AGENTS.md) guide covers authored locations, traversal, and reusable props. The [assets](../../assets/AGENTS.md) guide covers the editable source, imported outputs, and materials used by those scenes. Update the relevant guide whenever you add, change, or remove a system or asset contract. Keep the [model catalogue](../../MODEL_CATALOGUE.md) current when model assets change.

## Find the owner

| Work | Source of truth |
| --- | --- |
| Cinderhold hub, merchants, stash, and travel | [Hub scene](../../world/hub.tscn), [Hub interaction script](../../world/hub.gd), and [hub model modules](../../world/modules/) |
| Practice arena, authored obstacles, swim basin, and refill wells | [Training Ground scene](../../world/training_ground.tscn), [navigation and weapon drop points](../../world/training_ground.gd), [basin geometry](../../world/modules/training_swim_basin.tscn), and [well scene](../../world/props/training_recovery_well.tscn). Session setup, refill interactions, and weapon/enemy spawning flow through [Main](../../main.gd). |
| Ground drops and interactive prop presentation | [Training drop placement](../../world/training_ground.gd) and [WorldProp](../../world/world_prop.gd) |

## Author the Hub or Training Ground

- Edit the room, markers, doors, and interactive approaches in their owning scene. Use the World layer for solid surfaces and follow the actual floor, collision, navigation, and portal arrival from player eye height.
- Keep a clear approach to both Training Ground wells. Each well refills its own resource when targeted with **E**. Verify roof, ramp, water bounds, and camera water crossing where applicable.
- Place interactive props with a clear approach. Use the shared [arena drop placement](../../world/training_ground.gd) for floor support and drop spacing and add actual navigation blockers for solid scenery. Give solid decoration collision in the owning scene.
- [The session](../../main.gd) enables weapon stops on valid solid contacts by default in Training. The Carry Through practice preset keeps the swing moving while solid cover still blocks damage and plays impact feedback. [Breakable props](../../world/modules/breakable_prop.gd) expose the impact material, cleave mass and hit-through behavior. Set `allow_melee_damage` false for an intact obstacle. Compare the modes in [the Training Ground](ui-and-inventory.md#controls-and-item-lifecycle) and run the [breakable props fixture](../../tests/breakable_props.gd).

## Author and import art

### Art authoring workflow

1. Find the existing scene, runtime model, and editable source in the [model catalogue](../../MODEL_CATALOGUE.md). Most Blender sources live in [assets/source](../../assets/source/), with imports in [assets/models](../../assets/models/) or [player/weapons/models](../../player/weapons/models/). Edit the maintained source. Use an isolated Blender scene or session when the active file contains unrelated work. If Blender MCP is available and requested, use it for the relevant mesh, UV, or rig work and record the actual edit.
2. Preserve the existing asset's unit scale, pivot, forward axis, expected hierarchy, and attachment names. Check adjacent working assets before exporting a new family. Enemy rigs use `-Z` forward and should keep the skeleton and native scene animation bindings working through Idle, Walk, Windup, and Strike. For held items preserve `Pose`, trace markers, wrist alignment, and the `Pose/ForgedModel` mount expected by [WeaponView](../../player/weapon_view.gd). Configure first-person timing and trace events on the native Godot clips. A per-base geometry replacement should anchor to the existing hand or shield grip.
3. Use original texture inputs that may ship with the project. Supply meaningful UV0 coverage on both axes for mapped materials. Align face and neck color/density, ensure elbows and shoulders hold together when skinned, and check albedo textures under actual lighting. For posed props such as skull racks, scale an anatomical model uniformly and adjust the fixture layout around it. Keep opaque surfaces matte with roughness `1.0` and metallic specular `0.0`. The exceptions in appearance come from purpose-built effects such as water, emission, and portal shaders.
4. Export the GLB, reimport in Godot, and check actual scene instantiation. Keep editable source, export, textures, and their source-side `.import` and `.uid` metadata as appropriate. Follow a broken imported texture reference through to the actual file and its consumer. Let Godot regenerate the ignored `.godot/` cache. Verify imported materials, UV sampling, clips, skeleton tracks, collision, and runtime transforms before marking the model complete.
5. For item and creature art, check the actual in-game icon or portrait against the final model. Inventory icons should occupy the expected item footprint without clipping, and reusable models should read in the first-person pose or assembled world scene. Record source and runtime asset paths and verification in the [model catalogue](../../MODEL_CATALOGUE.md).

### Materials and lighting

The Training Ground instantiates the native receiver in [blood projection](../../world/modules/blood_floor_projection.tscn) with the shared [floor shader](../../world/modules/blood_floor.gdshader). Each practice visit creates its own receiver. Compare floor, wall, ceiling, ramp, and prop contact at a consistent scale. Inspect practical lights, visibility around corners, and actors in the shadows in the actual scene.

## VFX and audio boundaries

- **World VFX.** The scenes for [torch flame](../../world/modules/torch_flame.tscn), [votive candles](../../world/modules/floor_votive_cluster.tscn), [portal vortex](../../world/modules/portal_vortex.tscn), and [basin water](../../world/modules/basin_water.tscn) are reusable runtime owners. Tune the existing GPU emitters, shader or light in the scene that uses it. Inspect emitter bounds, layers, sorting, and behavior at the start and end of its lifetime. Verify portals and water both near the camera and from an oblique approach.
- **Combat VFX.** [CombatImpact](../../combat/effects/combat_impact.gd) routes world impact, blood, and severance through the existing effect and dismemberment owners. [EffectDefinition](../../combat/effects/effect_definition.gd) carries status presentation and lifecycle references. [Enemy projectiles](../../combat/effects/enemy_projectile.tscn) have a [runtime pool](../../combat/effects/enemy_projectile_pool.gd), so check for stale emitters and trails when an instance is reused. [Camera feedback](../../player/effects/camera/camera_feedback.tscn) owns first-person screen effects. Keep gameplay hit, status, and warning timing in their combat owners. Test status cleanup and corpse or floor contact when changing an effect's lifetime or attachment.
- **Sounds.** Edit **Audio → Sound catalogue** in [Hearth Workbench](../../addons/hearth_workbench/plugin.cfg) or inspect [sound_catalogue.tres](../../assets/audio/sound_catalogue.tres) in Godot. Assign imported streams to a [HearthSoundCue](../../systems/sound_cue.gd). The project's audio assets include WAV and Ogg Vorbis. One-shots pick among available clips and use authored gain and pitch variation. Ambience loops the first available clip. Walk and Sprint use Step as fallback when their specific cue has no playable clips. [GameAudio](../../systems/game_audio.gd) handles one-shots, ambient transitions, and shared spatial cue playback. The owning effect may drive a dedicated `AudioStreamPlayer3D`. Verify the intended event plays the expected cue at the right time and distance in a fresh game run after editing the resource.

## Verify in Godot

Run the relevant checks with Godot 4.7 from the directory containing [project.godot](../../project.godot).

```powershell
godot --headless --path . --editor --import
godot --headless --path . --script res://tests/training_ground.gd
godot --headless --path . --script res://tests/breakable_props.gd
```

Use [Training Ground](../../tests/training_ground.gd) and [breakable props](../../tests/breakable_props.gd) for interaction and impact. For visual changes, enter the actual hub or Training Ground in Forward+. Compare the relevant material, lighting, and contact under the same view and settings.
