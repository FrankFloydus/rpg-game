# Combat agent guide

Read the [combat, player, and enemy AI guide](../docs/agents/combat-and-player.md) before editing this package. Use the owner and verification tables to select the affected scenes, resources, runtime, and tests.

- Update the combat guide and any affected linked guides in the same change whenever you add, modify, move, or delete a file in this package. Keep owner paths, authoring steps, behavior, and validation current.
- Keep ability definitions reusable. Edit enemy-specific decisions in the archetype AI and author timings, geometry, and effects in the owning resources. Preserve stable archetype, ability, and effect IDs used in saved runs.
- Keep committed attack vectors, hit locations, and ground warnings in world space. Use world yaw for facing under dungeon floors. Keep animation tracks in rig space.
- Use the shared resolution, status lifecycle, trace, and impact APIs so effects and logs follow real outcomes. Test changes to mitigation, knockback, or rounding against the normal combat entry points.
- Preserve editable scenes and clip markers. Verify visible motion, particle effects, and telegraphs with a rendered Forward+ run alongside focused gameplay checks.
