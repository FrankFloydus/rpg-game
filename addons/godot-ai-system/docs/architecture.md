# Runtime architecture

The GDExtension registers the AI runtime, native helpers, and first-person lab classes at Godot's scene initialization level. `godot-ai-system.gdextension` selects the binary for the current platform and build feature tags. Trees are editable resources, and the host supplies game-specific operations.

| Layer | Source in the checkout | Responsibility |
| --- | --- | --- |
| Registration | `src/register_types.cpp`, `project/addons/godot-ai-system/godot-ai-system.gdextension` | Expose the native classes and select the loaded library. |
| Tree definition | `src/ai_behavior_tree.h`, `src/ai_behavior_tree.cpp` | Validate dictionaries, node IDs, ordered connections, blackboard types, references, and scripts. Compile authored data into an execution plan. |
| Tree execution | `src/ai_behavior_runner.h`, `src/ai_behavior_runner.cpp` | Hold one actor's blackboard, active branches, action/service instances, utility decisions, timers, and optional trace. |
| Encounter coordination | `src/ai_encounter_3d.h`, `src/ai_encounter_3d.cpp` | Track targets, reserve approach and firing positions, budget navigation work, and admit attacks. |
| Spawn pacing | `src/ai_horde_director.h`, `src/ai_horde_director.cpp` | Track pressure and pacing and return wave requests against host-supplied populations and candidate gates. |
| Displacement sampling | `AIMovementProgress` in `src/blocks/movement_progress.cpp` | Measure real movement after the host moves an actor. |
| Behavior blocks | `src/blocks/` | Compile 31 native tasks and services into the extension. They read Blackboard facts and send requests through host callbacks. |
| Block Labs | `src/block_labs/`, `project/ai_demo/block_labs/` | Load saved demonstration trees and catalogs into five first-person labs with compiled sample hosts and a portal hub. |
| Integration example | `project/ai_demo/` | Connect tree, locomotion, cover, combat, targeting, and spawning through ordinary Godot scenes and scripts. |
| Builds and distribution | `SConstruct`, `build_profile.json`, `tools/package.py` | Compile and install the native library and bundle the addon and demo with the guides. |

## A behavior tick

1. The actor observes the world, validates its target and route, and publishes typed facts with `AIBehaviorRunner.set_value()`.
2. The host calls `runner.tick(delta, action_handler)` from its chosen update loop. An actor that moves or traces physics normally uses `_physics_process()`. A tree using native leaves and Script Tasks can omit the host handler.
3. The runner evaluates guards and branch control. Script and native services can update facts for the active branch. Native tasks, Script Tasks, and host action callbacks provide execution results. Authored order controls composite traversal and tie breaking where applicable.
4. The host applies requested movement or attacks through its normal gameplay systems. It samples actual displacement after movement and handles damage at the authored impact or projectile contact.
5. Terminal or interrupted actions and services clean up through their exit paths. The host releases its encounter claims on target change, removal, or relevant route failure.

Many actors can share a saved `AIBehaviorTree`. The resource supplies authored data and the compiled plan. A runner supplies the mutable execution state. Mutating the shared resource can change every runner using it. Publish per-actor values to that runner's blackboard instead.

## Optional world services

A behavior tree can run on its own. Add `AIEncounter3D` when several actors need shared target selection, spacing, or attack admission. Feed its candidate positions to the host locomotion controller. A ranged position is a planning result. The host owns the release check and projectile collision.

Add `AIHordeDirector` when an arena or level needs pacing. Supply valid targets, events, current and queued populations, and gate observations. The host resolves archetype IDs, queues accepted requests, creates actors, and registers or releases them. The tree, encounter, and director can be tested independently before a full integration.

- [Implement a behavior from a request](implementation-playbook.md)
- [Tree data and execution](behavior-trees.md)
- [Reusable behavior blocks](behavior-blocks.md)
- [Navigation and encounter contracts](encounter-and-navigation.md)
- [Director contracts](horde-director.md)
- [Demo wiring](arena-demo.md)
- [Verification and runtime diagnostics](diagnostics-and-verification.md)
