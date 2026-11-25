# Assets agent guide

Read [World and assets](../docs/agents/world-and-assets.md) and check the [model catalogue](../MODEL_CATALOGUE.md) for the editable source, runtime export, and scene that uses it. Weapon and enemy runtime contracts are in [Combat and player](../docs/agents/combat-and-player.md).

- Edit the source and re-export the runtime asset together. Keep paths, scene roots, skeleton and marker names, grip positions, and texture bindings stable unless the consumer changes in the same task. Preserve unrelated work in any open Blender scene.
- Preview the imported game asset. Check sampled texture variation, UV coverage, proportions, and mesh connections from front and side. Inspect animated models through windup, contact, and recovery. Keep opaque materials at roughness `1.0` and specular `0.0`.
- Ship project-owned assets and their reproducible editable sources. Track Godot's source-side import settings and UIDs when present. Leave generated `.godot/` caches and export temp files out of source control.
- Author sound cues through [Sound Catalogue](audio/sound_catalogue.tres). Verify the intended runtime event and its variant or fallback before changing adjacent playback logic. Use the runtime scene for particles or receivers rather than replacing a working scene with a single rendered mesh.
- For every addition, change, or removal, update the [model catalogue](../MODEL_CATALOGUE.md) for affected models and [World and assets](../docs/agents/world-and-assets.md) when ownership, import, or verification changes. Record the runtime validation that actually ran.
