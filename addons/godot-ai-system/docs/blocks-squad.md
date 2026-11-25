# Squad and equipment blocks

Declare the listed input and output facts in the tree's blackboard schema. Host Callables use `TYPE_CALLABLE` with `external: true`. Set them after assigning the tree and after every runner reset. The examples show node dictionaries and host facts. See the [tree authoring guide](behavior-trees.md) for complete root, schema, and runner wiring.

The drivers in this group receive `(command: StringName, context: Dictionary) -> Variant`. A step reports `&"running"`, `&"success"`, or `&"failure"`. Commands execute synchronously on the runner's thread. Host systems can update an asynchronous operation separately and report its current state from the step. Run cleanup with the same driver and token that started the operation. Keep the driver alive through runner reset or tree removal when its host owns resources that need releasing.

## Reload or Swap Weapon

Native Task `reload_or_swap_weapon` picks an action for an empty weapon. A loaded weapon succeeds immediately. With both actions possible, the task reloads unless the preference fact is true. If only one is possible, it chooses that action.

| Parameter | Default | Blackboard or tuning contract |
| --- | --- | --- |
| `has_ammo_key` | `weapon_has_ammo` | Boolean. Required. |
| `can_reload_key` | `can_reload` | Boolean. Required for an empty weapon. |
| `can_swap_key` | `can_swap` | Boolean. Required for an empty weapon. |
| `prefer_swap_key` | `prefer_weapon_swap` | Optional Boolean. A missing fact is treated as false. Feed a game-specific exposure or urgency decision here. |
| `driver_key` | `weapon_maintenance_driver` | Host Callable. Required when the task chooses a maintenance action. |
| `timeout` | `4.0` | Positive finite seconds in runner time. |

| Command | Context and result |
| --- | --- |
| `start` | `action` is `reload` or `swap`. Return Boolean true after accepting it. |
| `step` | `action` and `delta`. Advance the operation or observe its state. Report success when the weapon is ready. |
| `stop` | `action` and `reason`. Runs once per accepted operation on completion, failure, timeout, or interruption. |

`stop.reason` is `succeeded`, `failed`, `timed_out`, or `aborted`. An unavailable action or a rejected start fails so the parent can choose a fallback. The choice is made on entry. To interrupt when the pawn changes weapons, attach a continuous guard driven by the host's current weapon identity.

```gdscript
var reload_task := {
    "id": 2, "kind": "native_task", "block": &"reload_or_swap_weapon",
    "parameters": {"timeout": 2.5},
}
runner.set_value(&"weapon_has_ammo", false)
runner.set_value(&"can_reload", true)
runner.set_value(&"can_swap", true)
runner.set_value(&"prefer_weapon_swap", exposed_to_enemy)
runner.set_value(&"weapon_maintenance_driver", drive_weapon_maintenance)
```

## Select an Available Ability

Native Service `select_available_ability` filters host ability candidates into a list and can publish separate eligibility flags for authored Utility children. It keeps the original order and takes the first eligible entry for each ID.

| Parameter | Default | Blackboard or tuning contract |
| --- | --- | --- |
| `candidates_key` | `ability_candidates` | Array of dictionaries with a nonempty `id` and Boolean `ready` and `eligible` fields. Both must be true. Additional fields pass through. |
| `available_key` | `available_abilities` | Array output. Set the parameter to an empty name to skip the list output. |
| `eligibility_keys` | `{}` | Optional dictionary mapping ability IDs to Boolean output keys. Each destination must be distinct from other outputs and the input. |

Invalid candidates are skipped and a missing input produces an empty list. Exiting the service clears its list and flags. Attach the service to the root or an ancestor of the Utility to publish eligibility before its children are scored. Use each flag in the corresponding child's condition and provide independent considerations for the score. Recheck costs and eligibility when the game commits the action.

```gdscript
root_node["services"] = [{
    "block": &"select_available_ability", "interval": 0.1,
    "parameters": {"eligibility_keys": {&"blink": &"blink_available"}},
}]
blink_utility_child["conditions"] = [{"key": &"blink_available", "op": "truthy"}]
runner.set_value(&"ability_candidates", [
    {"id": &"blink", "ready": blink_cooldown <= 0.0, "eligible": landing_zone_is_free},
])
```

## Protect an Ally

Native Task `protect_ally` computes an interception point every tick. The point starts at the ally and extends toward the threat by up to the configured offset. The host controls how to reach and hold that point.

| Parameter | Default | Blackboard or tuning contract |
| --- | --- | --- |
| `ally_position_key` | `ally_position` | Live finite Vector2 or Vector3. |
| `threat_position_key` | `threat_position` | Live finite position of the same type as the ally. |
| `needed_key` | `protection_needed` | Boolean. True drives interception. False succeeds and stops it. |
| `driver_key` | `protection_driver` | Host Callable. |
| `offset` | `1.0` | Finite, nonnegative world distance from ally toward threat. |

The `step` command receives `goal` and `delta`. Both `running` and `success` keep the task active so it can hold or update the point. Invalid positions, a missing active driver, or driver failure fail the task. If stepping started, `stop` receives the last `goal` and a `reason` of `succeeded`, `failed`, or `aborted`. Return failure from the driver when no safe route to the interception point is available.

```gdscript
var bodyguard_task := {
    "id": 4, "kind": "native_task", "block": &"protect_ally",
    "parameters": {"offset": 2.0},
}
runner.set_value(&"protection_driver", drive_bodyguard)
runner.set_value(&"ally_position", escort.global_position)
runner.set_value(&"threat_position", threat.global_position)
runner.set_value(&"protection_needed", true)
```

## Assist or Revive

Native Task `assist_or_revive` acquires one target claim, approaches the target, then performs the requested host action. It uses the same target and token throughout. Losing eligibility or changing targets fails the task and releases its claim.

| Parameter | Default | Blackboard or tuning contract |
| --- | --- | --- |
| `target_key` | `assist_target` | Integer, nonempty string/name, or valid Godot object identifying the ally. Preserve the same type and value while active. |
| `eligible_key` | `ally_needs_assist` | Boolean. True is required before claiming and while advancing. |
| `driver_key` | `assist_driver` | Host Callable. |
| `action` | `assist` | Nonempty host action name, such as `revive`. |
| `timeout` | `10.0` | Positive finite total seconds for approach and perform phases. |

| Command | Context and result |
| --- | --- |
| `claim` | `target` and `action`. Return an opaque non-null token to acquire the claim or null to deny it. |
| `approach` | `target`, `action`, `token`, `delta`. Success advances to perform on the next tick. |
| `perform` | Same fields as approach. Success completes the task. |
| `release` | `target`, `action`, `token`, `reason`. Use the token to release the claim and stop unfinished host work even if the target no longer exists. |

Reasons match Reload or Swap Weapon. A successful host revive may clear eligibility during its final step and return success in that call. A future revive uses a fresh activation and token.

```gdscript
var revive_task := {
    "id": 5, "kind": "native_task", "block": &"assist_or_revive",
    "parameters": {"action": &"revive", "timeout": 6.0},
}
runner.set_value(&"assist_driver", drive_revive)
runner.set_value(&"assist_target", downed_ally)
runner.set_value(&"ally_needs_assist", true)
```

## Retreat and Regroup

Native Task `retreat_and_regroup` evaluates a trigger and writes the best reachable fallback goal. Place it before your host's move and regroup actions in a sequence. The task ranks by highest safety, then shortest path cost, then input order.

| Parameter | Default | Blackboard or tuning contract |
| --- | --- | --- |
| `trigger_key` | `morale` | Finite numeric host fact such as normalized health, morale, or threat pressure. |
| `threshold` | `0.35` | Finite numeric threshold in the same units as the fact. |
| `direction` | `at_or_below` | Inclusive comparison. Use `at_or_above` for an increasing threat fact. |
| `candidates_key` | `fallback_candidates` | Array of dictionaries with a finite `position`, finite `safety`, and finite nonnegative `path_cost`. The cost can be negative to mark a blocked route. |
| `goal_key` | `move_goal` | Output position. Match the position type of the candidates to the declared output type. |

Use a single vector dimension per tree. On success the goal is available immediately to the next child. If the threshold is unmet or every route is invalid, the task fails and leaves the previous goal untouched. Consume its output on success. Re-evaluate reachability during movement through the host's route driver.

```gdscript
var retreat_task := {
    "id": 6, "kind": "native_task", "block": &"retreat_and_regroup",
    "parameters": {"trigger_key": &"pressure", "direction": &"at_or_above", "threshold": 0.7},
}
runner.set_value(&"pressure", 0.85)
runner.set_value(&"fallback_candidates", [
    {"position": Vector3(-3, 0, 1), "path_cost": -1.0, "safety": 1.0},
    {"position": Vector3(4, 0, 6), "path_cost": 8.5, "safety": 0.75},
])
# Follow node 6 with the host movement action and a regroup wait or action.
```

## Try the saved demos

Walk through the **Squad** gate in the hub, or open `res://ai_demo/block_labs/squad_lab.tscn` and press **F6**. Pick **1–5** and follow the objective. **E** starts the exercise or triggers its labeled action. Aim at a world marker or the floor and click when the HUD offers an aimed interaction. **R** resets the exercise. [Lab controls](native-block-labs.md)

| Case | Manual check |
| --- | --- |
| Reload or Swap Weapon | Aim at **Swap** and click, then press **E** to give the order. Reset and choose **Reload** to compare. |
| Select an Available Ability | Start the exercise, then press **E** to toggle Fireball's cooldown. Aim at Blink and click to toggle its eligibility independently. |
| Protect an Ally | Start the exercise, aim at another point on the floor, and click to move the threat. Watch the bodyguard pick a new interception point. **E** clears the threat. |
| Assist or Revive | Let the rescuer approach and revive the ally. Reset and press **E** during the approach to withdraw the ally and observe claim release. |
| Retreat and Regroup | Press **E** to lower morale and retreat to West Cover. Reset, aim at West Cover and click to block its route, then repeat to see Backup Cover chosen. |
