# Coordination blocks

Use a native task node with `kind: "native_task"` and its `block` ID, or use the service ID in a node's `services` array. The blocks run in the native extension. The game supplies its own path queries, occupancy, attack admission, movement, and interaction handlers.

## Find Reachable Position

The task ranks the candidates in an Array and publishes a single movement goal. It is a one-shot choice and works directly before a Move to Goal with Recovery task in a Sequence.

| Parameter | Default | Contract |
| --- | --- | --- |
| `candidates_key` | `position_candidates` | Blackboard Array of candidate dictionaries. |
| `goal_key` | `move_goal` | Output `Vector2` or `Vector3`. Declare the dimension in the schema. |
| `valid_key` | `has_move_goal` | Boolean output. Check it before using the goal. |
| `excluded_key` | Omitted | Optional Array of temporarily excluded positions. |
| `exclusion_radius` | `0.0` | Reject positions within this inclusive radius of an excluded point of the same dimension. |
| `path_weight` | `1.0` | Cost per unit of the candidate's path cost. |
| `distance_weight` | `0.0` | Cost per unit of deviation from `preferred_distance`. |
| `preferred_distance` | `0.0` | Desired value for the candidate's optional `distance` metric. |
| `visibility_weight` | `1.0` | Penalty scaled by the candidate's lack of visibility. |
| `crowding_weight` | `1.0` | Penalty scaled by the candidate's crowding. |

Use finite nonnegative settings. Each candidate supplies a finite `position`, `reachable: true`, and finite nonnegative `path_cost`. Optional `distance`, `visibility`, and `crowding` default to zero. Distance is finite and nonnegative. Visibility and crowding are in `0.0..1.0`. The task skips invalid rows. It minimizes `path_cost * path_weight + abs(distance - preferred_distance) * distance_weight + (1 - visibility) * visibility_weight + crowding * crowding_weight`. The first candidate wins an exact tie.

On success, the task publishes the position and sets the validity flag. With no eligible candidate, it clears the flag and fails. The game chooses the unit and meaning of path cost and distance. Scale the weights for your candidate metrics.

## Remember Unreachable Goals

Attach this service to a long-lived ancestor so several branches can read the same per-runner memory. The host publishes a report when a route fails. The service stores finite positions and publishes an Array in oldest-to-newest order.

| Parameter | Default | Contract |
| --- | --- | --- |
| `failure_key` | `unreachable_goal_report` | Dictionary containing a nonnegative integer `id` and a finite `position` as `Vector2` or `Vector3`. |
| `output_key` | `unreachable_goals` | Array of currently remembered positions. |
| `remember_seconds` | `4.0` | Positive, finite time after the service observes the report. |
| `capacity` | `8` | Positive integer. Evict the oldest entry when the capacity is exceeded. |

Advance the report ID for each new report. Reusing an ID does not extend its expiry. A new report for the same position refreshes it. The service observes the latest report on each tick, so attach it with an interval of zero if the host publishes one report every behavior evaluation. Exiting the owner clears the memory. Reentering the same attachment ignores report IDs it already consumed. A runner reset clears the report history along with the service instance. Connect the output to Find Reachable Position's `excluded_key` to prefer other destinations after a failure.

## Exclusive claims

Reserve Position, Acquire Attack Permission, and Use an Objective use the same host callback contract. The host arbitrates claims between actors and can adapt an existing cover reservation, encounter coordinator, interaction registry, or other game-specific system.

| Parameter | Reserve Position | Acquire Attack Permission | Use an Objective |
| --- | --- | --- | --- |
| `driver_key` | `position_reservation_driver` | `attack_permission_driver` | `objective_driver` |
| `request_key` | `position_request` | `attack_request` | `objective_request` |

Declare the driver fact as external `TYPE_CALLABLE`. The request fact may be any supported host identity, such as a StringName, point, or live Object. The task captures the request and callback on entry. Each task also accepts a `payload` dictionary (default empty), `wait_timeout` (default `2.0` seconds), and `poll_interval` (default `0.1` seconds). Timeout zero allows one immediate acquire attempt. Poll interval zero retries each tick while waiting. A tree timeout can bound the active operation.

The callback signature is `(command: StringName, context: Dictionary) -> Variant`. Treat the context as input. It contains `request`, the opaque `token` after acquisition, `payload`, runner `delta` in seconds, and `reason` on release.

| Command | Host response and ownership |
| --- | --- |
| `acquire` | Return `{"status": &"acquired", "token": claim_token}`, `{"status": &"waiting"}`, or `{"status": &"denied"}`. An acquired token must be non-null. A waiting response owns no claim and leaves no pending request to cancel. |
| `step` | Advance the protected operation. Return `&"running"`, `&"success"`, or `&"failure"`. Reserve Position and Acquire Attack Permission use this command. |
| `approach` | Move toward the claimed interaction point and return the same status strings. Use an Objective calls this until success. |
| `interact` | Perform the objective interaction with the same token and return the same status strings. This starts on the next tick after approach succeeds. |
| `release` | Clean up the protected operation and release the token. `reason` is `succeeded`, `failed`, or `aborted`. The task ignores the return value. |

Release runs once after acquisition when the operation finishes, fails, or exits through a guard, runner reset, or owner removal. Keep the driver alive until cleanup. Hosts that destroy their own driver should clean up that driver's claims as part of its lifetime. A malformed acquisition response cannot supply a claim token, so the host must publish `acquired` with its token whenever it successfully claims something.

### Reserve Position

Use the `step` phase to move into or occupy a reserved point. Keep returning `running` for as long as the claim must remain exclusive. Returning a terminal result ends the reservation before the next tree node starts.

### Acquire Attack Permission

Use `step` to advance the entire attack commitment, from wind-up to the point at which the host wants another attacker to enter. Return `running` through those phases. The host still owns hit timing, hit validation, and its attack limit.

### Use an Objective

The task keeps one claim through approach and interaction. Approach success advances to interaction. Either phase can fail and release the claim. Use the release reason to stop pending interaction animations or movement on interruption and to preserve a completed effect.

## Authoring examples

Use the snippets inside the host that sets up the tree. Declare facts using the types in each contract and publish external Callables after assigning or resetting the tree. In a saved resource, the node and service dictionaries have the same keys.

### Select cover and publish a goal

~~~gdscript
var find_cover := {
	"id": 3, "kind": "native_task", "block": &"find_reachable_position",
	"parameters": {"visibility_weight": 4.0, "excluded_key": &"unreachable_goals"},
}
runner.set_value(&"position_candidates", [
	{"position": Vector3(5, 0, 2), "reachable": true, "path_cost": 6.0, "visibility": 1.0},
	{"position": Vector3(3, 0, 0), "reachable": true, "path_cost": 3.0, "visibility": 0.0},
])
~~~

Place `find_cover` before a movement task that reads `move_goal`. With an empty exclusion list, the first point wins here because the second adds four units of visibility cost.

### Record a route failure

~~~gdscript
var remember_failed_routes := {
	"block": &"remember_unreachable_goals", "interval": 0.0,
	"parameters": {"remember_seconds": 5.0, "capacity": 6},
}
# Add remember_failed_routes to the services array of a long-lived node.
report_id += 1
runner.set_value(&"unreachable_goal_report", {"id": report_id, "position": failed_goal})
~~~

Report the failure from the host movement adapter when it abandons a route. Use `unreachable_goals` as the next position query's exclusion list.

### Claim a defensive position

~~~gdscript
var occupy_cover := {
	"id": 4, "kind": "native_task", "block": &"reserve_position",
	"parameters": {"wait_timeout": 0.8, "payload": {"stance": &"crouch"}},
}
runner.set_value(&"position_request", &"cover_12")
runner.set_value(&"position_reservation_driver", drive_cover_claim)
~~~

`drive_cover_claim` resolves the point ID, owns the claim, and returns `running` during approach and occupation. A branch guard can stop the task when a higher-priority threat appears.

### Hold an attack permit through recovery

~~~gdscript
var attack_with_permit := {
	"id": 5, "kind": "native_task", "block": &"acquire_attack_permission",
	"parameters": {"wait_timeout": 0.6, "payload": {"attack": &"heavy_swing"}},
}
runner.set_value(&"attack_request", target)
runner.set_value(&"attack_permission_driver", drive_melee_commitment)
~~~

`drive_melee_commitment` calls the game's permit coordinator during `acquire`, advances the attack from its normal animation callbacks during `step`, and releases the permit in `release`. Finish the task once that actor should make room for the next attacker.

### Claim and operate a terminal

~~~gdscript
var use_terminal := {
	"id": 6, "kind": "native_task", "block": &"use_an_objective",
	"conditions": [{"key": &"objective_allowed", "op": "truthy"}],
}
runner.set_value(&"objective_request", &"terminal_a")
runner.set_value(&"objective_driver", drive_terminal)
~~~

`drive_terminal` reserves the terminal in `acquire`, routes to its interaction socket in `approach`, and completes the game interaction in `interact`. If `objective_allowed` becomes false mid-action, the driver receives `release` with reason `aborted`. The saved coordination lab demonstrates both success and cancellation through this same runner lifecycle.
