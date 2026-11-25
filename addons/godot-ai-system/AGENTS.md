# Godot AI System integration

This addon is a script-facing Godot 4.7 GDExtension. Use the consuming game's own scenes and scripts for actor-specific behavior.

- Start from `implementation-playbook.md` for a new NPC request. The ZIP includes the detailed guides in `docs/` beside this file. In a source checkout, the guides are in the repository's top-level `docs/`.
- Use `behavior-trees.md` for node dictionaries, typed Blackboard inputs, action callbacks, utility choices, and services. Use the encounter and director guides when the actor needs crowd positions or encounter pacing.
- Use `behavior-blocks.md` to find a reusable block, then read its category guide for the exact blackboard keys, host callbacks, and wiring example. The compiled blocks are available through `native_task` and native service attachments.
- Treat a requested behavior as complete when its data, actor/controller wiring, movement or effect execution, interruption cleanup, and a representative runtime check all work together. Put those files in the game's folders so addon upgrades are straightforward.
- Use `get_debug_snapshot()` on a selected runner when behavior needs inspection. The diagnostics guide gives the commands and trace fields.
