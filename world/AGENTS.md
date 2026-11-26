# World agent guide

Read [World and assets](../docs/agents/world-and-assets.md) before changing the Hub, Training Ground, placement, or world VFX. Read [Campaign and saves](../docs/agents/campaign-and-saves.md) before changing character state or saved interactions.

- Edit the owning scene for the Hub, Training Ground, reusable module, or interactive prop. Follow the output through collision, navigation, and live interaction.
- Preserve the named markers and entry or exit transforms these scenes use unless the task changes them. Keep approaches to merchants, the stash, portals, and training stations traversable.
- Fit props to their supporting geometry and leave space to approach. Register solid training obstacles with the existing navigation owner.
- Keep visible masonry matte and textured. Check level transitions, lighting, moving particles, and floor/ceiling joins in Forward+ at player eye height. Treat a headless layout pass as structural evidence.
- For every addition, change, or removal, update the affected ownership and verification guidance in the same task. Update the [model catalogue](../MODEL_CATALOGUE.md) for model assets and the neighboring agent guide when a contract crosses directories.
