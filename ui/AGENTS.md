# Hearth Below UI agent guide

Read the [project agent guide](../AGENTS.md), then the [UI and inventory reference](../docs/agents/ui-and-inventory.md). The reference maps the production scene, game session, model, appearance resources, input, and affected tests.

- Edit the existing `.tscn` and reusable templates for fixed layouts and authored controls. Preserve active scene paths, scene-unique bindings, scroll behavior, and keyboard focus. Keep gameplay state and persistence with the existing model and session.
- Use [the shared theme](hearth_gear_theme.tres) and [MenuFrame](menu_frame.gd) for menu chrome. Use [the inventory appearance painter](inventory_appearance.gd) for placed-item and placement states in both the game and the Workbench.
- Route inventory changes through [Inventory](../systems/inventory.gd). Keep hover, click carry, and native drag in their UI adapters. Match placement previews to the real commit, preserve concealed information, and preserve source ownership through cancellation, failed fits, and save/restore.
- For layout and interactive changes, use the real game and check pointer input, keyboard focus, modal return, and the affected view at normal and compact sizes. Run the focused suites in the reference. Use a native renderer for pixel and appearance verification.
- Update the relevant agent reference and nearest guide in the same task whenever you add, change, or remove UI features, scenes, input, data ownership, appearance rules, or verification workflows.
