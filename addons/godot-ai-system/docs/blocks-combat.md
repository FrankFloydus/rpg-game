# Combat behavior blocks

These blocks handle combat decisions, timing, and cancellation through blackboard facts and game callbacks. The game supplies collision queries, movement, animation, attacks, and effects. See [behavior trees](behavior-trees.md) for blackboard types, continuous guards, and timeout decorators.

## Wait for Clear Shot

Native Task `wait_for_clear_shot`. Sample a live firing-lane fact until it clears or the wait expires.

| Parameter | Default | Contract |
| --- | --- | --- |
| `clear_key` | `shot_clear` | Boolean input. Update it from the host's current line-of-fire query before each runner tick. |
| `result_key` | `shot_decision` | StringName output. Declare it on the blackboard and keep the two keys distinct. |
| `timeout` | `0.6` | Finite nonnegative seconds of runner time. Zero checks once. |

A blocked lane publishes `waiting` and keeps the task running. A clear sample publishes `fire` and succeeds. A blocked lane at the deadline publishes `reposition` and fails, allowing a selector to try its next child. A missing or non-Boolean sample publishes `invalid` and fails. Interruption while waiting publishes `cancelled` before normal runner cleanup. A clear sample takes priority if it arrives on the evaluation that would cross the deadline. The game should check the actual firing lane again at projectile release when wind-up separates the decision from release.

```gdscript
# Declare shot_clear as TYPE_BOOL and shot_decision as TYPE_STRING_NAME.
# Place this inside a selector so its Failure can select a repositioning branch.
{"id": 3, "kind": "native_task", "block": "wait_for_clear_shot",
 "parameters": {"timeout": 0.45}}
```

## Phase driver callbacks

**Take Cover and Peek**, **Telegraph, Commit, Recover**, and **Reposition Between Attacks** use a host Callable with this signature.

```gdscript
func drive_phase(command: StringName, context: Dictionary) -> Variant:
    if command == &"stop":
        locomotion.stop()
        return null
    return locomotion.step_toward(context.goal, context.delta)
```

Declare the driver key as an external `TYPE_CALLABLE` and bind it with `runner.set_value()` after assigning the tree and after each reset. In a real host adapter, return `&"running"`, `&"success"`, or `&"failure"` from `step`. A phase returning success gives the next phase the next tick. The block treats unsupported responses as failures.

| Command | Context |
| --- | --- |
| `step` | `phase: StringName`, `first: bool` for the first step of that phase, `delta: float` in runner seconds, `goal` as a point or null, and `data: Dictionary` described per block. |
| `stop` | `phase`, `reason: StringName`, and `data`. Once any step is issued, the driver receives one stop when the operation ends, including on guard interruption or reset. The block ignores the stop return value. |

Use `first` to start an animation, issue a movement request, or create an effect once. Treat `context` and its authored `data` as read-only. Use `stop` to release reservations, stop driving movement, or clear host state that survives interruption. A native `timeout` decorator can bound the entire task when the host might keep returning `running`.

## Take Cover and Peek

Native Task `take_cover_and_peek`. Follow `take_cover` → `peek` → `return_to_cover`. During `peek` the host can move to the exposure point, check sight, hold for a firing window, or send an action request. The task succeeds after the requested number of complete cycles.

| Parameter | Default | Contract |
| --- | --- | --- |
| `driver_key` | `cover_driver` | External Callable implementing the phase driver contract. |
| `cover_key` | `cover_position` | Finite `Vector2` or `Vector3` cover point, captured on entry. |
| `peek_key` | `peek_position` | Distinct blackboard key for a finite point of the same type, captured on entry. |
| `cycles` | `1` | Positive integer number of cover cycles. |

The driver receives the corresponding point as `goal` and an empty `data` dictionary. Stop reasons are `completed`, `failed`, and `aborted`. The task fails when a required point or driver is invalid, or a phase fails. For moving targets or compromised cover, use a continuous guard to cancel and let the tree choose fresh points.

```gdscript
# Supply cover_position, peek_position, and cover_driver before ticking.
{"id": 4, "kind": "native_task", "block": "take_cover_and_peek",
 "parameters": {"cycles": 2},
 "decorators": [{"kind": "timeout", "duration": 8.0}]}
```

## Telegraph, Commit, Recover

Native Task `telegraph_commit_recover`. Follow `telegraph` → `commit` → `recover`. The host owns phase duration, animation, and damage. Telegraph warns, commit executes the strike or ability, and recover waits for the host to be ready for another action.

| Parameter | Default | Contract |
| --- | --- | --- |
| `driver_key` | `attack_driver` | External Callable implementing the phase driver contract. |
| `action` | `attack` | Nonempty action identifier passed in `data.action` as a StringName. |
| `payload` | `{}` | Optional authored Dictionary passed in `data.payload`. |

The driver receives null as `goal`. Stop reasons are `completed`, `failed`, and `aborted`. A failed phase ends the task and skips the later phases. Use an entry guard for admission that remains valid through a committed attack, or a continuous guard for an action the host can cancel. When gameplay damage happens at an authored animation event, report `success` from the commit phase when that phase actually completes.

```gdscript
# Bind attack_driver. The host defines what the payload and lunge action mean.
{"id": 5, "kind": "native_task", "block": "telegraph_commit_recover",
 "parameters": {"action": "lunge", "payload": {"variant": "heavy"}}}
```

## Interrupt on State Change

Native Service `interrupt_on_state_change`. The service captures the initial discrete state at entry and publishes a latched Boolean when the value changes. This lets a continuous guard detect a transition from whichever state the actor started in. A guard that checks a fixed fact directly remains appropriate when only one state is allowed.

| Parameter | Default | Contract |
| --- | --- | --- |
| `watch_key` | `interrupt_revision` | Discrete input as Boolean, integer, String, or StringName. A monotonically increasing integer revision is useful when multiple host events can arrive between runner ticks. |
| `result_key` | `interrupted` | Boolean output, declared on the blackboard. Use a distinct key. |

A valid initial sample publishes false. Any value or type change, including a missing input, sets true until service exit. An invalid or missing initial sample sets true immediately. Service exit resets the output to false. Place the service on an ancestor of the guarded action and use interval zero for evaluation on every tree tick. The continuous child guard must use this output to interrupt the action. The runner then performs the task's ordinary exit cleanup. When using [Request an Action and Wait](behavior-blocks.md#request-an-action-and-wait), return a cancellation Callable from the host to undo a pending action.

```gdscript
# Node 5 can use any task with an exit path. Its service lives on node 0.
[
    {"id": 0, "kind": "root", "children": [5], "services": [
        {"block": "interrupt_on_state_change", "interval": 0.0}
    ]},
    {"id": 5, "kind": "action", "key": "channel",
     "conditions": [{"key": "interrupted", "op": "falsy", "mode": "continuous"}]}
]
```

Increment the host's revision to interrupt a channel after a hit, squad order change, or similar event. As with other services, a root that returns a terminal result will reenter on a later tick and capture the then-current state. Put a separate eligibility guard above the protected branch if a cancelled operation should stay unavailable.

## Reposition Between Attacks

Native Task `reposition_between_attacks`. Drive toward a chosen point while a live readiness fact is false. Return Success as soon as an attack is ready. If the pawn reaches the point first, stop driving and continue waiting for readiness.

| Parameter | Default | Contract |
| --- | --- | --- |
| `driver_key` | `reposition_driver` | External Callable implementing the phase driver contract. |
| `ready_key` | `attack_ready` | Live Boolean input from the host. |
| `goal_key` | `reposition_goal` | Finite `Vector2` or `Vector3`, captured when movement starts. |

The driver receives phase `reposition`, the supplied `goal`, and an empty `data` dictionary. Stop reasons are `ready`, `arrived`, `failed`, and `aborted`. Arrival stops the driver immediately. A later readiness success does not stop it a second time. If readiness is already true, the task succeeds without asking for movement. An invalid readiness value or failed route returns Failure.

```gdscript
# A prior task chooses reposition_goal. The host updates attack_ready each tick.
{"id": 6, "kind": "native_task", "block": "reposition_between_attacks",
 "decorators": [{"kind": "timeout", "duration": 3.0}]}
```

## Demo

Walk through the **Combat** gate in the hub, or open `res://ai_demo/block_labs/combat_lab.tscn` and press **F6**. Pick **1–5** and press **E** to begin. The objective tells you when to open the shutter, block a route, or interrupt a channel. **R** resets the exercise. The saved trees under `res://ai_demo/block_labs/combat/` contain the editable parameters and fixture data. [Lab controls](native-block-labs.md)
