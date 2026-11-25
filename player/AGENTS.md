# Player agent guide

Read the [combat, player, and enemy AI guide](../docs/agents/combat-and-player.md) for how input, movement, first-person presentation, and combat share the player scene.

- Update the combat guide and any affected linked guides in the same change whenever you add, modify, move, or delete a file in this package. Keep gameplay controls, editable paths, authoring steps, and verification current.
- Keep immediate input capture, physics-driven action timing, and rendered camera feedback in their respective owners. Use the player's gameplay aim transform for traces and collision. Preserve physics interpolation at movement and teleport boundaries.
- Edit held pose, animation, and trace socket placement in the weapon scene. Preserve marker names, clip timing, hand identity, movement response, and trace coverage when retuning weapon feel.
- Test light input, charge, guard, pause or modal transitions, and actual terrain or enemy contact if the corresponding path changes. Check authored motion in a rendered first-person Training Ground run.
