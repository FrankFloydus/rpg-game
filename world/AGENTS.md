# World agent guide

Read [World and assets](../docs/agents/world-and-assets.md) before changing dungeon generation, authored world scenes, placement, or world VFX. Read [Expeditions and saves](../docs/agents/expeditions-and-saves.md) before changing stable IDs, seed inputs, or floor serialization.

- Edit the owning scene for the Hub, Training Ground, reusable module, or interactive prop. Edit the generator for repeated, seed-dependent placement. Follow the output through collision, navigation, minimap visibility, and live interaction.
- Preserve old generator branches and saved layout fingerprints. Avoid changing earlier RNG draw order, catalog order, entrance/exit transforms, or stable object IDs through incidental refactors.
- Keep thresholds, stairs, corner turns, trap lanes, and interactable approaches traversable. Fit props against the actual room or passage boundary, with a valid floor support and space to approach. Register solid blockers with the existing navigation owner.
- Keep visible masonry matte and textured. Check level transitions, lighting, moving particles, and floor/ceiling joins in Forward+ at player eye height. Treat a headless layout pass as structural evidence.
- For every addition, change, or removal, update the affected ownership and verification guidance in the same task. Update the [model catalogue](../MODEL_CATALOGUE.md) for model assets and the neighboring agent guide when a contract crosses directories.
