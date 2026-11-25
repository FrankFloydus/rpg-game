# Movement blocks

These C++ blocks use the behavior runner's existing blackboard and callback contracts. Author a native task with `{"kind": "native_task", "block": &"block_id", "parameters": {...}}` or attach a native service with `{"block": &"block_id", "parameters": {...}, "interval": 0.0}`. Each activation reads the parameters shown below. The block instance belongs to one runner and one node or service attachment.

When a block requires a driver, declare its key as an external `TYPE_CALLABLE` and bind it after assigning or resetting the runner's tree. The driver receives `(command: StringName, context: Dictionary) -> Variant` on the game thread. An operation that takes several frames returns `AIBehaviorRunner.RUNNING` while active. Use the runner constants for terminal success or failure. Keep movement, collision, animation, and resource ownership in the game. Do not call `tick()`, `reset()`, or reassign the runner tree from a driver callback. [Tree and blackboard contracts](behavior-trees.md)

Open `res://ai_demo/block_labs/movement_lab.tscn` and press **F6**. Choose **1–5** to set up an exercise. Read the objective and press **E** to start, then use **WASD** and the mouse to move around the range and see what the pawn does. [Exercise controls](native-block-labs.md) The five behavior tree resources are under `res://ai_demo/block_labs/movement/`.

## Patrol Route

**Native task** `patrol_route`. Visit route stops in order. Each stop can include a wait after arrival.

| Parameter | Default | Contract |
| --- | --- | --- |
| `route_key` | `patrol_route` | Input `Array` of finite `Vector2` or `Vector3` points, or dictionaries with `position` and optional finite nonnegative `wait` seconds. Use one vector type throughout. The route must have at least one stop. |
| `driver_key` | `behavior_driver` | External Callable. |
| `mode` | `loop` | `once` succeeds after the final wait, `loop` wraps to the first stop, and `ping_pong` reverses at each end. A single-point repeating route keeps visiting that point. |

The task snapshots the route on entry. The driver receives `step` with `goal`, zero-based `index`, `delta`, and empty `reason`. Return `RUNNING` while moving, `SUCCESS` on arrival, or `FAILURE` when the leg cannot complete. A malformed response fails the task. Each attempted leg receives one `stop` with the same goal and index, zero delta, and reason `arrived`, `failed`, or `aborted`. The driver stops movement during the wait and prepares the next leg on its first step. Configure a timeout or a fallback in the tree if a game driver can return Running indefinitely.

```gdscript
# TYPE_ARRAY route fact and external TYPE_CALLABLE driver.
var patrol_node := {
    "id": 4, "kind": "native_task", "block": &"patrol_route",
    "parameters": {"mode": &"ping_pong"},
}
runner.set_value(&"patrol_route", [
    {"position": Vector3(0, 0, 5), "wait": 1.0}, Vector3(3, 0, 8),
])
runner.set_value(&"behavior_driver", patrol_driver)
```

## Follow Formation Offset

**Native task** `follow_formation_offset`. Follow the world position of a leader-local offset. Recompute the desired goal each tick so it follows the leader's position and facing.

| Parameter | Default | Contract |
| --- | --- | --- |
| `leader_transform_key` | `formation_leader_transform` | Input finite `Transform2D` or `Transform3D`. Provide a unit-scale transform when the formation should ignore leader scale. |
| `offset` | Required without a key | Literal finite `Vector2` or `Vector3`, matching the transform dimension. |
| `offset_key` | Omitted | Optional live blackboard offset in place of the literal. |
| `driver_key` | `behavior_driver` | External Callable. |
| `max_replacements` | `2` | Nonnegative integer replacement budget per activation. |

The driver receives `step` with `goal`, the current local `offset`, `delta`, and empty `reason`. Return `RUNNING` while moving or `SUCCESS` when settled. Either keeps the task active. On failure, the block can call `replace_offset` with the failed goal and offset, zero delta, and `reason: blocked`. Return a different finite local offset or `null` to fail. The block follows the replacement until the host changes the offset fact or starts a new activation. A `stop` command with `reason: failed` or `aborted` cleans up an attempted follow. The host decides how much change requires a path rebuild and how it assigns or releases formation slots.

```gdscript
# External TYPE_TRANSFORM3D and TYPE_CALLABLE facts.
var follow_node := {
    "id": 5, "kind": "native_task", "block": &"follow_formation_offset",
    "parameters": {"offset": Vector3(-1.5, 0, 2.0), "max_replacements": 1},
}
runner.set_value(&"formation_leader_transform", leader.global_transform)
runner.set_value(&"behavior_driver", formation_driver)
```

## Stay Within Leash

**Native service** `stay_within_leash`. Publish whether an actor should return home and whether it can pursue a target. Attach it above both branches so the selector can react to its outputs.

| Parameter | Default | Contract |
| --- | --- | --- |
| `position_key` | `actor_position` | Input finite actor position as `Vector2` or `Vector3`. |
| `home_key` | `leash_home` | Input home position in the same dimension. |
| `target_position_key` | Omitted | Optional input target position in the same dimension. Missing or out-of-range targets suppress pursuit when configured. |
| `radius` | `12.0` | Positive distance from home at which a return starts once exceeded. |
| `return_radius` | `1.0` | Distance at which return clears. Use a finite value from zero up to but excluding `radius`. |
| `must_return_key` | `must_return_home` | Boolean output. |
| `can_pursue_key` | `can_pursue` | Boolean output. |
| `goal_key` | `leash_goal` | Output home position, written while return is required. |

Distances are spherical in 3D. Supply planar positions if your leash should ignore height. Once outside the leash, the actor must reenter the smaller return radius before pursuit is allowed. If only the target leaves, pursuit stops and the actor can wait. Invalid samples or service exit clear both flags. Use distinct output keys and read the return goal only while the return flag is set.

```gdscript
# TYPE_VECTOR3 position, home, target, and goal. TYPE_BOOL return and pursue flags.
var leash_service := {
    "block": &"stay_within_leash", "interval": 0.1,
    "parameters": {"radius": 18.0, "return_radius": 2.0, "target_position_key": &"target_position"},
}
var return_condition := {"key": &"must_return_home", "op": "truthy", "mode": "continuous"}
# Put a host action guarded by return_condition before the can_pursue branch.
```

## Approach via Flank

**Native task** `approach_via_flank`. Choose a reachable lateral goal from a host-supplied list. Use a sequence to move there after the planner succeeds.

| Parameter | Default | Contract |
| --- | --- | --- |
| `target_position_key` | `target_position` | Input finite target position as `Vector2` or `Vector3`. |
| `target_forward_key` | `target_forward` | Input nonzero facing vector matching the position dimension. |
| `candidates_key` | `flank_candidates` | Input `Array` of dictionaries with finite `position`, boolean `reachable`, and finite nonnegative `path_cost`. |
| `goal_key` | `flank_goal` | Output chosen position. |
| `valid_key` | `has_flank` | Boolean output. Reset on each attempt. |
| `max_alignment` | `0.45` | Max absolute cosine between target forward and target-to-candidate direction, in `[0, 1)`. Zero admits exactly perpendicular directions. |
| `minimum_distance` | `0.5` | Nonnegative minimum planar distance from the target. |
| `alignment_weight` | `1.0` | Nonnegative penalty multiplier for directions closer to the frontal or rear axis. |
| `side` | `either` | `either`, `left` for negative cross product, or `right` for positive cross product. In 3D, directions project to the XZ plane. |

Eligible candidates rank by lowest `path_cost + abs(dot) * alignment_weight`; authored order breaks exact ties. Invalid and unreachable candidates are skipped. If no candidate qualifies, the task fails with `has_flank` false and leaves the previous position value available behind that flag. The game should refresh candidates when obstacles or targets move and handle movement failure after a successful plan. Use distinct input and output keys.

```gdscript
# TYPE_VECTOR3 target, facing, and goal. TYPE_ARRAY candidates. TYPE_BOOL has_flank.
var flank_node := {"id": 6, "kind": "native_task", "block": &"approach_via_flank"}
runner.set_value(&"target_position", Vector3(0, 0, 5))
runner.set_value(&"target_forward", Vector3.FORWARD)
runner.set_value(&"flank_candidates", [
    {"position": Vector3(-3, 0, 5), "reachable": true, "path_cost": 4.2},
    {"position": Vector3(0, 0, 3), "reachable": true, "path_cost": 1.0},
])
# The next Sequence child moves to flank_goal; the cheap frontal point is excluded.
```

## Traverse Navigation Link

**Native task** `traverse_navigation_link`. Request a traversal operation such as a jump, climb, vault, or door crossing. Approach the link's entry before starting this task.

| Parameter | Default | Contract |
| --- | --- | --- |
| `link_key` | `navigation_link` | Input Dictionary with nonempty `id` and `action`, finite `entry` and `exit` of the same vector type, and optional Dictionary `payload`. |
| `driver_key` | `behavior_driver` | External Callable. |
| `timeout` | `3.0` | Positive finite seconds allowed per activation. |

The descriptor is captured on entry. The driver receives `begin` once, then `poll` while running. Both receive the captured descriptor, `delta`, and an empty `reason`. Delta is limited to the remaining time budget. Return `SUCCESS` after the actor crosses, `FAILURE` on rejection, or `RUNNING` while traversal is in progress. An active task that uses the full budget and still reports Running fails. After any attempted begin, the driver receives one `stop` with zero delta and reason `completed`, `failed`, `timeout`, or `aborted`. Restore movement mode, animation, collision, and any traversal reservation there as appropriate. A guard can abort traversal if the link closes or the actor is interrupted.

```gdscript
# TYPE_DICTIONARY link and external TYPE_CALLABLE driver.
var traverse_node := {
    "id": 7, "kind": "native_task", "block": &"traverse_navigation_link",
    "parameters": {"timeout": 1.8},
}
runner.set_value(&"navigation_link", {
    "id": &"north_gap", "action": &"jump", "entry": Vector3(0, 0, 4),
    "exit": Vector3(0, 0, 7), "payload": {"animation": &"jump_long"},
})
runner.set_value(&"behavior_driver", traversal_driver)
```
