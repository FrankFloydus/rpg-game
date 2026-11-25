# Gameplay AI agent guide

Read the [combat, player, and enemy AI guide](../docs/agents/combat-and-player.md) and the [native AI addon guide](../addons/godot-ai-system/AGENTS.md) for ownership. This directory contains Hearth Below's game behavior tree and expedition pacing.

- Update the combat guide and any affected linked guides in the same change whenever you add, modify, move, or delete a file in this package. Keep driver ownership, blackboard contracts, editor paths, and verification current.
- Keep behavior tree facts and callbacks in sync with the shared enemy runtime. Preserve selector order, entry conditions, cleanup, and pack admission when editing an existing task.
- Keep per-enemy moves in the archetype and shared world-space target and navigation handling in the coordinated AI path. Expedition pacing changes attack costs. Dungeon and encounter owners place and restore the roster.
- Verify the native runner and a real expedition or Training Ground fight. Exercise perception, route recovery, attack budget, and interruption where affected.
