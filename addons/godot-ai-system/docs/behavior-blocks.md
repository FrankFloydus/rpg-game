# Reusable behavior blocks

The addon includes 31 compiled C++ blocks. The game supplies blackboard facts and implements the actions requested by the tree. Each runner has its own block state. [Tree and runner contracts](behavior-trees.md)

## Compiled block catalog

| Guide | Blocks |
| --- | --- |
| [Movement](blocks-movement.md) | Patrol Route, Follow Formation Offset, Stay Within Leash, Approach via Flank, Traverse Navigation Link |
| [Perception](blocks-perception.md) | Prioritize Stimuli, Search Around a Point, Rank and Retain Targets, Share Contact, Estimate Target Motion |
| [Coordination](blocks-coordination.md) | Find Reachable Position, Reserve Position, Remember Unreachable Goals, Acquire Attack Permission, Use an Objective |
| [Combat](blocks-combat.md) | Wait for Clear Shot, Take Cover and Peek, Telegraph Commit Recover, Interrupt on State Change, Reposition Between Attacks |
| [Squad and abilities](blocks-squad.md) | Reload or Swap Weapon, Select an Available Ability, Protect an Ally, Assist or Revive, Retreat and Regroup |
| Built-in task and service contracts below | Wait for a Fact, Trigger Once at a Threshold, Request an Action and Wait, Move to Goal with Recovery, Remember Last Seen Position, Maintain a Range Band |

Use a `native_task` node with a registered `block` ID. To attach a compiled service, set `block` on the entry in the owner's `services` array. Both accept `parameters`. The guides document which inputs the game must supply and how to compose the block. [Native Task syntax](behavior-trees.md#native-tasks-and-services) · [Interactive examples](native-block-labs.md)

## Migrate the original six blocks

Replace each old `script_task` with `kind: "native_task"` and `block` set to the original filename without `.gd`. In service attachments, replace `script` with `block`. Keep the node IDs, parameters, guards, and blackboard keys. Remove the six obsolete script resource references. For a host that called the threshold script directly, instantiate `AIThresholdLatch.new()` and keep one instance per latch.

## Wait for a fact

Native task `wait_for_fact` succeeds when a blackboard key is present and its value equals the expected value.

| Parameter | Type | Use |
| --- | --- | --- |
| `key` | `String` or `StringName` | Required nonempty blackboard key. |
| `equals` | Variant | Expected value. Defaults to `true`. |

The task returns `RUNNING` until a present value matches. Key presence matters even when the expected value is `null`. An absent key keeps waiting, and a present `null` satisfies `equals: null` where the blackboard declaration permits that value. Matching supports equal values of the same type, integer-to-float comparisons, and `String`-to-`StringName` comparisons. An invalid key configuration returns `FAILURE`.

Add the built-in `timeout` decorator to bound the wait. For example, `"decorators": [{"kind": "timeout", "duration": 5.0}]` gives the task five seconds of runner time to succeed. See [execution decorators](behavior-trees.md#execution-decorators) for timeout behavior and ordering.

## Trigger once at a threshold

Native task `trigger_once_at_threshold` succeeds once when a numeric fact meets the configured threshold. The first valid sample can trigger immediately when it is already at or beyond the threshold.

| Parameter | Type | Use |
| --- | --- | --- |
| `value_key` | `String` or `StringName` | Required nonempty key of the numeric fact to sample. |
| `threshold` | Finite number | Literal threshold when using a fixed limit. |
| `threshold_key` | `String` or `StringName` | Optional nonempty blackboard key for the numeric threshold. A configured key supplies the limit in place of the literal. |
| `direction` | `String` or `StringName` | `at_or_below` by default. Use `at_or_above` for a rising value. Both include equality. |

A valid, unconsumed task returns `RUNNING` while the sampled value or a keyed threshold is absent, or while the value has yet to meet the threshold. Invalid configuration returns `FAILURE`. Once both samples are available, a nonnumeric or nonfinite value also fails. A qualifying sample returns `SUCCESS` and consumes the latch. A later activation of that same task instance returns `FAILURE`. `runner.reset()` rearms it by clearing the runner's task instances.

For an event that needs a synchronous decision, create an `AIThresholdLatch` and call `try_trigger(value: float, threshold: float, direction: StringName = &"at_or_below") -> bool`. A qualifying sample returns `true` and consumes that instance's latch. Call `reset()` on the host-owned instance when starting a new cycle. Each native tree node maintains its own latch.

## Request an action and wait

Native task `request_action_and_wait` asks the game to perform an action when the task enters. It waits for the game's completion callback.

| Parameter | Type | Use |
| --- | --- | --- |
| `handler_key` | `String` or `StringName` | Blackboard key of the host `Callable`. Defaults to `request_handler`. |
| `action` | `String` or `StringName` | Required nonempty action identifier understood by the host. |
| `payload` | `Dictionary` | Per-request arguments. Defaults to an empty dictionary. |

Declare the handler key as an external `TYPE_CALLABLE` in the tree's `blackboard_schema`, then supply a valid Callable with `runner.set_value()`. Implement the handler as `(action: StringName, payload: Dictionary, finish: Callable) -> Variant` and return one of these values.

| Return | Meaning |
| --- | --- |
| `true` | Accept the request. The host will report completion through `finish`. |
| `false` | Reject the request. The task fails. |
| A valid `Callable` | Accept the request and provide a cancellation callback that takes no arguments. |

After accepting, call `finish.call(true)` for success or `finish.call(false)` for failure. Completion can happen during the handler call or in a later frame. A pending request returns `RUNNING`. A missing or invalid handler returns `FAILURE`. A rejected request fails even if the host called `finish` during the handler. An accepted synchronous completion can return its result on the same runner evaluation.

If a pending task exits because a guard fails, the runner resets, or another branch interrupts it, the block calls the provided cancellation callback once. Use that callback to undo or stop the game operation as appropriate. Completions from an old or already completed request are ignored. Keep the completion callback on the game thread. The host can report completion from a signal or an update loop while the task itself stays synchronous.

## Move to goal with recovery

Native task `move_to_goal_with_recovery` leaves navigation to the host. The host chooses the initial goal, drives movement, and supplies remaining route distance. The task detects stalled progress, asks the host for a replacement goal, and bounds the number of recovery attempts.

| Parameter | Default | Use |
| --- | --- | --- |
| `goal_key` | `move_goal` | Blackboard key containing a finite `Vector2` or `Vector3`. The task captures the initial goal on entry. |
| `driver_key` | `move_driver` | External `TYPE_CALLABLE` blackboard key. |
| `stall_timeout` | `0.8` | Seconds of requested movement without meaningful progress before recovery. |
| `minimum_progress` | `0.1` | Decrease in remaining distance that counts as progress. |
| `max_retries` | `2` | Maximum replacement requests per activation. Zero skips recovery. |

The driver receives `(command: StringName, goal: Variant, reason: StringName) -> Variant`. A minimal adapter can forward these calls to an existing movement controller.

| Command | Host contract |
| --- | --- |
| `step` | Continue toward the goal. Return a finite nonnegative distance to report movement, or a dictionary with `status` set to `moving`, `waiting`, `arrived`, or `blocked`. A `moving` dictionary also supplies finite nonnegative `remaining`. Use remaining path distance when possible so a detour counts as progress. Use `waiting` for deliberate pauses such as a doorway queue. |
| `recover` | Handle `blocked` or `stalled`. Return a finite replacement goal of the same vector type, or `null` to fail. Returning the same point is valid when the host rebuilds its route. |
| `stop` | Stop driving the movement on exit. `reason` is `arrived`, `failed`, or `aborted`. The host decides whether to keep a reservation on arrival and how to release one on failure. |

An arrival succeeds. While the host reports movement or a deliberate pause, the task stays active. An explicit blockage requests recovery immediately. A pause clears the progress sample and stall timer. If recovery fails or uses up its attempts, the task fails so the parent can choose another action. Each new activation gets its own retry budget. Use a fallback or cooldown when the tree would otherwise reenter on the same failed route immediately. The driver can steer through Godot navigation, a custom motor, or a grid. Attack readiness and shot clearance stay with the game.

## Remember last seen position

`remember_last_seen_position` is a native service. Attach it above the branches that use the memory. The host supplies a visibility fact and target position. While the target is visible, the service refreshes the remembered position. While visibility is lost, it retains the last sample for the configured duration.

| Parameter | Default | Use |
| --- | --- | --- |
| `visible_key` | `target_visible` | Host boolean observation. |
| `position_key` | `target_position` | Host position as a finite `Vector2` or `Vector3`. |
| `target_key` | Omitted | Optional target identity. A change or loss of this identity clears memory for the old target. |
| `remembered_position_key` | `last_seen_position` | Output position of the same vector type. |
| `memory_valid_key` | `has_last_seen_position` | Boolean output. Check this before reading the remembered position. |
| `memory_seconds` | `3.0` | How long to keep the sample after losing sight. |

On expiry or service exit, the validity flag becomes false. Attach the service to a branch that stays active across movement and idle decisions when memory should survive those decisions. Use the stored position to investigate or seek a new angle. Read live visibility or check collision again when releasing an attack.

## Maintain a range band

`maintain_range_band` is a native service. It reads a distance and publishes a `StringName` intent that the host or tree can turn into movement.

| Parameter | Default | Use |
| --- | --- | --- |
| `distance_key` | `target_distance` | Host distance as a finite nonnegative number. |
| `intent_key` | `range_intent` | Output key for `approach`, `hold`, or `back_off`. |
| `min_distance` | Required without a key | Start backing off below this distance. |
| `max_distance` | Required without a key | Start approaching above this distance. |
| `hysteresis` | `0.5` | Distance inside the band that the actor must reach before resuming `hold`. |
| `min_distance_key`, `max_distance_key`, `hysteresis_key` | Omitted | Optional blackboard keys that supply the corresponding settings. Each configured key takes precedence over its literal. |

Use nonnegative limits with the maximum at least as large as the minimum. With a 4–8 m band and 0.5 m hysteresis, an actor approaching from outside stops at 7.5 m. An actor backing off stops at 4.5 m. Crossing directly into the opposite side changes intent immediately. Missing or invalid distance or keyed settings publish `hold`. The actor or tree chooses the movement goal and handles blocked routes.

## Test the movement blocks with the pawn

Open `res://ai_demo/behavior_blocks_arena.tscn` and press **F6**. It uses the existing enemy pawn, a saved test tree, and a scene script that supplies the host facts and movement driver.

| Key | Expected behavior |
| --- | --- |
| **1** | The pawn approaches a distant target and switches to hold inside its preferred range. |
| **2** | The pawn backs away from a nearby target and switches to hold once it has room. |
| **3**, then **C** | The shutter blocks sight. The last seen position stays available until memory expires. **C** opens the shutter again. |
| **4** | A physical barrier stops the pawn. The movement task detects the stall and tries a route around it. |
| **5**, then **B** | The pawn deliberately waits at the closed barrier. It uses no retry while waiting and resumes when **B** opens the barrier. |

Use **R** to restart the current scenario and **Tab** to switch cameras. The status panel reads the same facts and driver state used by the tree.

## Example with a powered hatch

Add `AIBehaviorRunner` and `Hatch` children to a `Node3D`, then attach the script below to the parent. `Hatch` is the movable `Node3D` for the door. Call `begin_cycle()` to arm the tree, and feed the obstruction sensor and power reading through `set_inputs(clear_to_open, charge)`. The tree waits for clearance, waits for charge to reach `0.8`, then asks the actuator to open the hatch. If clearance disappears while it opens, the Request's continuous guard aborts it and the returned cancellation callback closes the hatch.

```gdscript
extends Node3D

@onready var _runner: AIBehaviorRunner = $AIBehaviorRunner
@onready var _hatch: Node3D = $Hatch

var _closed_height := 0.0
var _cycle_active := false


func _ready() -> void:
	_closed_height = _hatch.position.y
	var tree := AIBehaviorTree.new()
	tree.root_id = 0
	tree.blackboard_defaults = {"clear_to_open": false, "charge": 0.0}
	tree.blackboard_schema = {
		"clear_to_open": {"type": TYPE_BOOL},
		"charge": {"type": TYPE_FLOAT},
		"request_handler": {"type": TYPE_CALLABLE, "external": true},
	}
	tree.nodes = [
		{"id": 0, "kind": "root", "children": [1]},
		{"id": 1, "kind": "sequence", "children": [2, 3, 4]},
		{
			"id": 2, "kind": "native_task", "block": "wait_for_fact",
			"parameters": {"key": "clear_to_open"},
			"decorators": [{"kind": "timeout", "duration": 5.0}],
		},
		{
			"id": 3, "kind": "native_task", "block": "trigger_once_at_threshold",
			"parameters": {"value_key": "charge", "threshold": 0.8, "direction": "at_or_above"},
		},
		{
			"id": 4, "kind": "native_task", "block": "request_action_and_wait",
			"parameters": {"action": "open_hatch", "payload": {"travel": 1.8}},
			"conditions": [{"key": "clear_to_open", "op": "truthy"}],
		},
	]
	_runner.set_behavior_tree(tree)


func begin_cycle() -> void:
	_runner.reset()
	_hatch.position.y = _closed_height
	_runner.set_value(&"request_handler", _request_action)
	_cycle_active = true


func set_inputs(clear_to_open: bool, charge: float) -> void:
	_runner.set_value(&"clear_to_open", clear_to_open)
	_runner.set_value(&"charge", charge)


func cancel_cycle() -> void:
	_cycle_active = false
	_runner.reset()


func _physics_process(delta: float) -> void:
	if _cycle_active:
		_cycle_active = _runner.tick(delta) == AIBehaviorRunner.RUNNING


func _request_action(action: StringName, payload: Dictionary, finish: Callable) -> Variant:
	if action != &"open_hatch":
		return false
	var travel := float(payload.get("travel", 1.8))
	var motion := create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	motion.tween_property(_hatch, "position:y", _closed_height + travel, 0.6)
	motion.finished.connect(func() -> void: finish.call(true))
	return func() -> void:
		motion.kill()
		if is_instance_valid(_hatch):
			_hatch.position.y = _closed_height
```

`begin_cycle()` resets the runner before rebinding the external handler because a reset restores authored defaults. `cancel_cycle()` stops future ticks and resets the runner, so an in-flight operation follows the same cancellation path as a guard interruption. A completed request keeps its result in the game world until the next cycle deliberately closes the hatch. Call runner lifecycle methods from the host update or lifecycle code, outside task callbacks.

## How the Warden uses the blocks

The Hollow Warden calls the threshold latch synchronously during damage so the phase clamp and ritual immunity take effect on the crossing hit. After landing, the arena ticks `res://ai_demo/boss/boss_ritual_tree.tres` on its ritual runner. The request sends `summon_group` with `{"group": "ritual_offerings"}` and completes when the final offering spawns. The next task waits for `ritual_resolved`, which the arena sets once all offerings have been killed or delivered. The arena owns spawning, cleanup, and ritual effects. [Boss demo](boss-demo.md)
