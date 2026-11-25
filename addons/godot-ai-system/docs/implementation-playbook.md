# Implementing NPC behavior with Godot AI System

Use this playbook when the request is a short description such as “make a guard patrol and investigate noise” or “make archers find a side angle when another enemy blocks their shot.” The deliverable is a saved actor scene that performs the behavior through its normal game entry points, with an editable tree, connected game systems, and evidence that it works.

## 1. Turn the request into an observable contract

Write down what starts each behavior, what a player can observe while it runs, and what ends or interrupts it. Include the first failure case likely to happen during play. A guard can receive a noise it cannot reach. An archer can lose its shot after beginning the wind-up. A successful implementation handles both the normal path and the recovery path.

Identify the actual target project and read its project instructions before editing. Locate an existing actor scene, its movement and animation systems, the game events that supply perception, and an existing scene where the behavior can be tested. Use the project's terminology, collision layers, input, and navigation settings. Decide any reversible tuning needed for a first pass and report it at handoff. Ask about an ambiguity only when competing interpretations would materially change gameplay.

Break the design into three responsibilities.

| Responsibility | Owns |
| --- | --- |
| Behavior tree and Blackboard | Priorities, eligibility, action ordering, authored durations, utility scores, and the facts those choices consume. |
| Actor and game adapters | Sensing, target validity, route following, avoidance, animation, damage, interaction, and cleanup. The host publishes facts and performs the actions the tree selects. |
| Optional shared coordinator | Melee claims, firing destinations, attack admission, choke capacity, or wave admission when multiple actors actually share that concern. |

For each action, specify its key, compiled block ID, or script, then record input facts, movement or gameplay outputs, and terminal results. Include what to release when the action is interrupted. For each Blackboard key, specify its Variant type, who writes it, when it expires, and its initial value if one is needed. Keep an object's lifetime in mind when the board carries a Node reference.

## 2. Find the code and choose the integration

Confirm the target project has the runtime addon and a compatible native binary. The manifest currently requires Godot 4.7. Match the platform, architecture, precision, and debug or release feature tags in the manifest. Verify that Godot registers `AIBehaviorTree` and `AIBehaviorRunner` after importing the project. For a missing class, check extension loading and the first engine error before changing GDScript. The [repository README](../README.md) describes the supported build and package workflow.

Use the source map below when working from the full repository. An addon-only installation contains the runtime files. The demo project and C++ implementation are in the clone.

| Look at | Use it to verify |
| --- | --- |
| `src/ai_behavior_tree.cpp` | Accepted serialized fields, type checks, tree structure, and validation. |
| `src/ai_behavior_runner.cpp` | Script bindings, tick and exit behavior, utility decisions, timers, action history, and debug fields. |
| `src/blocks/` and [compiled block catalog](behavior-blocks.md#compiled-block-catalog) | Reusable decision and lifecycle logic. Find a documented block and confirm its host contract before implementing a custom one. |
| `src/ai_encounter_3d.cpp` | Target registration, positioning results, route budgets, attack admission, and reservation release. |
| `src/ai_horde_director.cpp` | Wave profile settings, spawn candidate fields, and the returned admission request. |
| `project/ai_demo/enemy.gd` and the melee and ranged tree resources beside it | The demo's host action adapter, route recovery, and timed attack release. |
| `project/ai_demo/arena.gd` | How the demo registers targets, configures enemies, and interprets spawn requests. |
| `AIMovementProgress` in `src/blocks/movement_progress.cpp` | An optional displacement-based stall detector. |

Extend the existing actor motor and gameplay APIs when they fit. A simple noncombat actor usually needs a tree, runner, and host adapter. Add `AIEncounter3D` for shared tactical positions or attack admission. Add `AIHordeDirector` when the request includes pacing or spawn composition. The demo's faction assumptions, collision masks, attack names, controls, and assets belong to that demo. Use project-owned adapters and resources in the new actor scene.

## 3. Author an editable tree resource

Save a text `.tres` of type `AIBehaviorTree` in the target project. It contains `nodes`, `root_id`, `blackboard_schema`, and `blackboard_defaults`. You can write the text resource directly or generate it once with `AIBehaviorTree.new()` and `ResourceSaver.save()`. If a generator helps, keep the resulting resource as the asset assigned by the actor scene. Check the save result, reload the file, and validate that instance. The engine's save API is documented here. [Godot ResourceSaver](https://docs.godotengine.org/en/stable/classes/class_resourcesaver.html)

- Give each node a stable, nonnegative 32-bit integer `id`. Use a `root` node with one child for new trees and set `root_id` to that node. Preserve existing IDs and entry behavior when editing older trees. Child order comes from the `children` array. Every non-root node needs one incoming link, and all nodes must be reachable from the root.
- Declare facts in `blackboard_schema` as `{key: {"type": TYPE_*, "external": bool}}`. Set `external` when the game publishes the key. It may have a fallback default. A nonexternal declaration needs a default. A nonempty schema rejects undeclared runtime writes. Legacy resources without a schema infer types from their defaults. Use the actual declared type, including the distinction between `String` and `StringName`.
- For attached Blackboard guards, author `conditions` entries with `key`, `op`, an operand `value` for comparisons, and optional `mode`. The default `continuous` can interrupt a running branch. Use `entry` when a valid start should remain committed despite changes to the starting fact. Continue to recheck safety-critical gameplay facts such as a shot's line of fire when its side effect occurs.
- Use a Selector for explicit priorities, a Sequence for ordered steps, and a Parallel only for tasks intended to advance together. The Selector reevaluates higher-priority branches. The Sequence resumes its running child. Parallel ticks children in authored order and exits outstanding branches when a threshold is met. Its `success_threshold` defaults to zero, meaning all children, and `failure_threshold` defaults to one.
- An `action` node has a `key`. A `native_task` names a registered `block`. A `script_task` uses a `script` resource. Each supports `parameters`. A `wait` uses `duration` in seconds. `set_blackboard` requires a declared `key` and typed `value`, and `erase_blackboard` requires a declared `key`.
- Attach result and timing wrappers using the node's `decorators` array in outermost-first order. Each entry has a `kind` of `inverter`, `succeeder`, `repeat`, `retry`, `timeout`, or `cooldown`. Repeat and Retry accept `count`, default one. Timeout and Cooldown accept `duration`, default one second. Cooldown starts after the child succeeds or fails. The corresponding standalone nodes take exactly one child.
- Attach periodic sensing or maintenance to the owner with `services` entries containing a `script` or a compiled `block`, an optional `label` and `parameters`, and `interval` in seconds. Its default is 0.2. A service gets an immediate tick on activation and then updates at its interval while the owner remains active. Zero means every runner tick. A guard that needs a fact to let the owner enter must read a fact already published by the host or an eligible ancestor.

Run `tree.validate()` and inspect `tree.get_validation_warnings()`. A valid tree can still contain an action key the host never handles. Check the action-key inventory against the actual callback or task scripts. Keep editable tuning in resources or documented exported fields. Preserve previously saved behavior when adding new keys or branches. [Behavior tree reference](behavior-trees.md)

### Utility decisions

Use a Utility node when multiple eligible choices should compete on current facts. Its `strategy` is `weighted` by default or `highest` for maximum-score selection with authored-order ties. Each child starts at its `weight`. Each consideration normalizes its input over `min` and `max`, samples an optional `Curve`, and contributes a factor clamped to 0–1. Blackboard considerations accept numbers and Booleans, with false mapped to zero and true to one. A missing or unsupported input contributes a zero factor. The final score is the weight multiplied by the factor product. A guard can disqualify the child before scoring. Check that the authored ranges produce meaningful scores for the facts the host actually supplies.

A consideration's `source` can be `blackboard` with a `key`, `time_since_attempt`, or `time_since_success`. History is per runner and action node ID. For a history input on the action itself, omit `action_id`. To read another action's history or put the consideration on a composite, supply the action's ID. An unobserved event uses the input maximum. A successful completion and an attempted entry are different events.

A running child normally keeps its commitment. When the action is interruptible, it can call `request_utility_reconsideration()` from its callback to ask its nearest enclosing Utility to reconsider next tick. A retained winner continues its existing action state. Set `retry_backoff` in seconds if no eligible choice or a full set of failed attempts should defer the next search. The Utility returns failure during the delay so a parent Selector can run a fallback. An omitted or zero delay preserves immediate reevaluation.

## 4. Wire the actor and the game loop

In the saved actor `.tscn`, assign the saved tree to an `AIBehaviorRunner` under the actor. Connect the existing movement controller, optional navigation agent, animation, target sensors, and events. Expose the references a designer needs to assign and provide defaults that work in the included test scene. Make the world scene supply any required targets, patrol markers, routes, or coordinators.

For a physics-driven actor, publish facts before ticking, apply locomotion afterward, and measure the result after movement. At minimum, separate requested movement from the actual displacement. This is the order to map onto the project's existing callbacks.

```gdscript
func _physics_process(delta: float) -> void:
    refresh_facts(delta)
    brain.tick(delta, perform_action)
    apply_requested_movement(delta)
    measure_progress(delta)
```

The four calls describe the host's integration points. Implement them with the actor's existing controllers. Give `tick` the elapsed, finite, nonnegative simulation delta. Refresh expensive sensing or route selection on an appropriate cadence while keeping movement, interrupts, and action timing responsive. An actor must have one owner of its runner tick. Avoid replacing the tree or calling `reset()` or `tick()` from inside a runner callback.

| Implementation | Callback contract |
| --- | --- |
| Host Action | Pass a Callable to `brain.tick(delta, perform_action)`. It receives `(key: StringName, phase: StringName, delta: float)`. Handle `enter` for acquisition, `tick` for progress, and `exit` for cleanup. The tick returns `AIBehaviorRunner.RUNNING`, `SUCCESS`, or `FAILURE`. |
| Script Task | Assign a synchronous `RefCounted` GDScript implementing `tick(runner: AIBehaviorRunner, delta: float) -> int`. `enter(runner)` and `exit(runner)` are optional. A task instance belongs to its runner and node and can retain state across activations. Reset per-activation data in `enter`. |
| Service | Assign a synchronous `RefCounted` GDScript implementing `tick(runner: AIBehaviorRunner, delta: float) -> void`. Optional `enter(runner)` and `exit(runner)` manage activation state. Read attachment parameters through `runner.get_service_parameters()` during a service callback. |

Read node parameters through `get_action_parameters()` during the action or Script Task callback. Use those parameters to share a task implementation with different speeds, durations, or identifiers. Keep mutable action state on the owning actor or task instance. Parallel children can be active together, so shared host state needs an explicit owner when actions overlap. For trees without host Action nodes, `brain.tick(delta)` is sufficient.

Use `RUNNING` while work is in progress, `SUCCESS` when the actual completion condition is met, and `FAILURE` when the branch cannot continue. An action waiting for a signal can update host state from the signal and return the result on the next synchronous tick. Clean up movement, timers, animation state, claims, and callbacks in `exit` on both terminal and interrupted paths. Revalidate objects at the point of use. Reset or remove the runner when recycling the actor and release any shared coordinator claims during teardown.

### Route following and stall recovery

Use a saved, traversable navigation region and wait for its navigation map to synchronize before requesting a route. With a `NavigationAgent3D`, set `target_position` when the goal changes meaningfully, advance the route with `get_next_path_position()` in physics, and let the actor motor move the body. Check reachability and actual distance to the intended destination. Reaching the end of a partial path is insufficient for a task that requires arrival. When avoidance is enabled, consume the computed safe velocity according to the motor's callback timing. When disabled, apply the desired velocity. [Godot NavigationAgents](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html)

Measure planar displacement after movement while the actor is being asked to move. The optional `AIMovementProgress` helper tracks position, requested speed, and delta. Its `update(position, commanded_speed, delta)` returns true once the configured stall time is reached. Call `reset()` when a goal changes. A stalled actor should have a concrete next step such as rebuilding a route, rejecting the blocked destination, selecting a different target, or ending the action so a fallback can run.

## 5. Apply the contract to a behavior

### Noncombat guard that investigates a noise

For a guard that patrols until it hears a noise, prioritize investigation above patrol. The following resource gives a complete tree for one pending noise at a time. It expects two host actions, `move_to_noise` and `patrol`. The schema's numeric IDs are Godot's `TYPE_BOOL` and `TYPE_VECTOR3`, respectively.

```ini
[gd_resource type="AIBehaviorTree" format=3]

[resource]
resource_name = "Noise Guard"
nodes = [{
"id": 0, "kind": "root", "children": [1]
}, {
"id": 1, "kind": "selector", "children": [2, 6]
}, {
"id": 2, "kind": "sequence", "children": [3, 4, 5],
"conditions": [{"key": "has_noise", "op": "truthy", "mode": "continuous"}]
}, {
"id": 3, "kind": "action", "key": "move_to_noise"
}, {
"id": 4, "kind": "wait", "duration": 1.0
}, {
"id": 5, "kind": "set_blackboard", "key": "has_noise", "value": false
}, {
"id": 6, "kind": "action", "key": "patrol"
}]
root_id = 0
blackboard_defaults = {"has_noise": false}
blackboard_schema = {
"has_noise": {"type": 1, "external": true},
"noise_position": {"type": 9, "external": true}
}
```

1. Save the guard scene with collision, movement, a runner holding this resource, and references to at least two reachable patrol markers. Add the guard to a saved scene with traversable navigation and a real noise source, such as an interaction event or a test-scene signal connected to the guard's noise handler.
2. Accept a noise by writing its world-space `noise_position` before setting `has_noise` true. For this simple contract, accept another noise after the pending investigation clears. The actor can expose a separate cancel event that clears `has_noise` to interrupt movement or inspection.
3. In `patrol`, advance through the assigned patrol markers. Set the route when the marker changes and return `RUNNING` while patrolling. Its exit relinquishes the movement request so investigation can take over.
4. In `move_to_noise`, request a route to the recorded location. Return `RUNNING` while following it and `SUCCESS` when the guard physically reaches it. Stop movement on success so the Wait is stationary. For an unreachable or abandoned noise, clear `has_noise`, release movement, and return `FAILURE`. The Selector can then choose patrol. A route stall follows the project's recovery policy before giving up.
5. Verify patrol → noise travel → stationary inspection → patrol. Add an unreachable noise and verify the guard recovers. If the request calls for replacing or queuing noises during inspection, author that policy explicitly and test it. This tree consumes one pending event before accepting another.

### Tactical melee attacker

Give the actor a real target policy and a dedicated encounter coordinator only when it needs to share space or attack admission with others. Register available targets. When an actor changes target or leaves, call `release_agent(actor)`. Disable a dead target with `set_target_enabled(target, false)` or unregister a removed target. Use `select_target(actor, current_target, ring)` if its crowding and stickiness rules suit the game. Use the host's own selection when roles or perception need different rules.

1. During physics, poll `update_position(actor, target, ring, nav_map, nav_layers)` on the actor's planning cadence. Use the same navigation map and layers as its motor. Follow the returned `position`, which can be a waypoint, final slot, or waiting location. A claim is indicated by `has_slot`, and `slot_position` identifies its final reserved position. Poll as the actor approaches a waypoint. On a stalled route, call `report_melee_stuck(actor)` and replan when the claim is released.
2. Prioritize interrupted or staggered behavior first, then a valid strike, then movement or waiting. Before committing, recheck that the actor owns the expected slot when the design requires one, the target is valid, and reach, line of sight, and cooldown allow the attack. Use `try_begin_attack(target, category, cost)` at commitment if encounter admission applies. Lock the melee slot for the committed strike when needed and unlock it on exit.
3. Drive the host's attack animation and damage API. At the actual impact frame, recheck the committed target, reach, and obstruction, then apply damage once. Cancel callbacks or guard them by attack state if the action ends early. Check that a dead or departing target cannot be hit by a stale animation event.
4. Test one actor first. Add another actor competing for the same target and verify that waiting, claims, action interruption, and claim release produce observable behavior. Test with a real obstacle and a target swap.

### Tactical archer that seeks a firing lane

Use separate facts for target validity, a usable movement goal, current muzzle clearance, and attack readiness. An actor can have a reachable lane goal while its current shot is blocked. A goal reservation alone cannot authorize projectile release.

1. In physics, call `update_ranged_position(actor, target, min_range, max_range, collision_mask, muzzle_height, aim_height, nav_map, nav_layers)`. Read `status` and `found` together. A pending budget update can retain a usable goal. `approach` is a reachable repositioning waypoint without a firing reservation. `goal_occluded` describes a previously verified destination temporarily blocked by a moving body. `exhausted` and `route_invalid` call for the actor's fallback. The result's `can_fire` describes the current muzzle, and `reposition` can suggest optional spacing even for a clear shooter.
2. Hold a clear lane while shooting is sensible. Move toward a valid goal when blocked. If the route stalls or the goal arrives with no usable shot, call `reject_ranged_position(actor, position)` to release the reservation and temporarily exclude that spot. Let the actor try another lane or a clear alternate target. Release its claim when the target changes.
3. Use the same blocker rules and exact muzzle and aim point in the committed shot and the projectile. Recheck at wind-up start and release. Handle cancellation cleanly when an ally or obstacle crosses the ray. For projectile-based weapons, verify the projectile also stops on the expected blockers after launch.
4. Test with two archers lined up, a wall that admits a reachable side angle, a fully occluded target, and a body entering the lane during wind-up. Check that the initially blocked archer actually moves and releases a valid shot. In a crowd test, count shots per actor to catch one stalled archer that aggregate damage would hide.

See the shared coordinator reference for all route statuses, optional query arguments, and reservation ownership. [Encounter and navigation](encounter-and-navigation.md)

### Encounter pacing when requested

Author `AIHordeDirector.wave_profiles` with a `channel` and `composition` of archetype IDs. The host provides current population by channel, including queued units, plus `threat`. Supply `total_active` when channels overlap. For spawn candidates, provide an integer `id`, `reachable`, `hidden`, `distance`, and signed `path_offset` when the profile distinguishes ahead from behind. A call to `update_encounter(delta, population, candidates)` can return an empty dictionary. A nonempty result gives `channel`, `spawn_id`, and `composition`. Resolve those IDs to saved scenes and marker positions and spawn through the host's normal flow. Use `register_pressure_target(target)` and feed real gameplay events into `record_target_pressure(target, amount)`. [Horde director reference](horde-director.md)

## 6. Verify the behavior and hand it off

1. **Import and load.** Use the target project's Godot binary. Verify that the addon loads, the tree validates, the assigned resource persists after a reload, and every script, scene, node reference, and navigation layer resolves. Test the scene actually used by the user.
2. **Exercise the decision contract.** A small deterministic fixture can tick the real runner with known facts and a recording handler. Assert the expected action transitions and interruption cleanup. Use fixed simulation steps where timing matters. Inspect warnings as well as validation errors. A bounded editor launch alone establishes import and parse health.
3. **Exercise the complete actor.** Instantiate the saved scene, trigger the normal signal or encounter event, and assert actual movement, arrival, animation impact, damage, or interaction as appropriate. Test blocked paths, disappearance of a target, interrupted actions, and recovery. For crowd behavior, exercise the requested population and measure outcome counts alongside timing.
4. **Use diagnostics while verifying.** Set `brain.debug_enabled = true` on the fixture or selected actor, then read `get_debug_snapshot()` for active node IDs, statuses, guard rejections or interruptions, the last Utility decision, and recent events. A retained score is evidence from its decision tick. Also record host facts the tree cannot infer, such as route state, desired and safe velocity, actual displacement, a blocked muzzle, or why a gameplay callback ended. Enable tracing only where it helps the test.
5. **Report a reproducible result.** Give the scene to open, the event or input to trigger, the expected behavior, and what passed. Name any assumptions you made and any relevant check you could not run. Keep the authored files in the target project so the user can edit them.

Example commands, using the actual executable and paths for the target project.

```text
godot --headless --editor --path <target-project> --quit-after 180
godot --headless --path <target-project> --scene res://path/to/npc_test.tscn --quit-after 180
godot --headless --path <target-project> --script res://path/to/npc_smoke.gd
```

The second command is a bounded smoke launch. The third assumes a project test script that asserts behavior and exits with a meaningful status. Inspect the engine log for extension, parse, runtime, and assertion errors. [Diagnostics and verification](diagnostics-and-verification.md) · [Godot command-line reference](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html)
