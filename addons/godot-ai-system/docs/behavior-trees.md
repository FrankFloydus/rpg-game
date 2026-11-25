# Behavior trees from GDScript

Install the addon for Godot 4.7 using the [project README](../README.md). GDScript can create, save, and run `AIBehaviorTree` resources directly. Add one `AIBehaviorRunner` per actor and share the tree resource across actors. Each runner keeps its own Blackboard, active branches, action history, timers, and script instances. The host decides when to tick and supplies the gameplay state and side effects.

## Run a tree built entirely in code

Create a scene with a plain `Node` root. Attach a script, paste the following into it, and run the scene. Hold **Space** to make the target available. The first child inspects the target and prints a message on success. It waits half a second after a completed inspection before it can start again. The fallback Wait runs when there is no target or the action is on cooldown. Release **Space** during an inspection to interrupt it.

```gdscript
extends Node

var runner: AIBehaviorRunner
var _inspect_elapsed := 0.0


func _ready() -> void:
	var behavior_tree := build_tree()
	var issues := behavior_tree.validate()
	if not issues.is_empty():
		push_error("\n".join(issues))
		set_physics_process(false)
		return

	runner = AIBehaviorRunner.new()
	runner.name = "BehaviorRunner"
	runner.tree = behavior_tree
	runner.debug_enabled = true
	add_child(runner)


func _physics_process(delta: float) -> void:
	_tick_ai(delta, Input.is_physical_key_pressed(KEY_SPACE))


func _tick_ai(delta: float, has_target: bool) -> int:
	runner.set_value(&"has_target", has_target)
	return runner.tick(delta, _run_action)


func _run_action(action: StringName, phase: StringName, delta: float) -> int:
	if action != &"inspect":
		return AIBehaviorRunner.FAILURE

	match phase:
		&"enter":
			_inspect_elapsed = 0.0
		&"tick":
			_inspect_elapsed += delta
			if _inspect_elapsed < 0.25:
				return AIBehaviorRunner.RUNNING
			var label: String = runner.get_action_parameters().get("label", "Target")
			var completed: int = runner.get_value(&"inspect_count")
			runner.set_value(&"inspect_count", completed + 1)
			print("Inspected ", label)
			return AIBehaviorRunner.SUCCESS
		&"exit":
			_inspect_elapsed = 0.0
	return AIBehaviorRunner.FAILURE


static func build_tree() -> AIBehaviorTree:
	var behavior_tree := AIBehaviorTree.new()
	behavior_tree.resource_name = "Inspect Target"
	behavior_tree.root_id = 0
	behavior_tree.blackboard_schema = {
		"has_target": {"type": TYPE_BOOL, "external": true},
		"inspect_count": {"type": TYPE_INT},
	}
	behavior_tree.blackboard_defaults = {"inspect_count": 0}
	behavior_tree.nodes = [
		{"id": 0, "kind": "root", "children": [1], "position": Vector2(240, 0)},
		{"id": 1, "kind": "selector", "children": [2, 3], "position": Vector2(240, 160)},
		{
			"id": 2,
			"kind": "action",
			"key": "inspect",
			"label": "Inspect target",
			"position": Vector2(20, 320),
			"conditions": [{"key": "has_target", "mode": "continuous"}],
			"decorators": [{"kind": "cooldown", "duration": 0.5}],
			"parameters": {"label": "Training dummy"},
		},
		{"id": 3, "kind": "wait", "duration": 0.2, "position": Vector2(380, 320)},
	]
	return behavior_tree
```

To persist the definition, call `ResourceSaver.save(build_tree(), "res://inspect_tree.tres")` from an editor script or another context where the project directory is writable. Check the returned Godot error code. To use the saved tree, assign `preload("res://inspect_tree.tres")` to `runner.tree`. Edit the saved resource's properties in the Inspector or author its node dictionaries in code.

## Resource schema

| `AIBehaviorTree` property or method | Contract |
| --- | --- |
| `nodes: Array` | An array of node dictionaries. Assign the array back after editing it because the getter returns a copy. |
| `root_id: int` | The ID of the entry node. A `root` node is the explicit entry wrapper. Older resources can point at their entry directly. |
| `blackboard_schema: Dictionary` | Typed key declarations keyed by name. |
| `blackboard_defaults: Dictionary` | Initial values keyed by name. |
| `validate() -> PackedStringArray` | Returns graph, configuration, schema, and script contract errors. An empty array means validation passed. |
| `get_validation_warnings() -> PackedStringArray` | Returns compatibility warnings, such as a reference to an undeclared key in a tree with inferred types. |
| `get_effective_blackboard_schema() -> Dictionary` | Returns the resolved key declarations, including inferred types when there is no explicit schema. |

The property equivalents are `set_nodes(nodes)` and `get_nodes()`, `set_root_id(root_id)` and `get_root_id()`, `set_blackboard_schema(schema)` and `get_blackboard_schema()`, and `set_blackboard_defaults(defaults)` and `get_blackboard_defaults()`.

Every node requires a unique, non-negative 32-bit integer `id` and a supported `kind` string. Supply ordered child IDs as `children: Array` or `PackedInt32Array`. Each non-root node has one parent, and all nodes must be reachable from the root without cycles. Execution depth is limited to 128, including attached decorators. Optional `label: String` and `position: Vector2` are used by the editor.

Every node can carry `conditions`, `decorators`, and `services` arrays. A direct Utility child also accepts `weight` and `considerations`. The supported kinds and their own fields follow.

### Entry, composites, and leaves

| `kind` | Children | Fields and behavior |
| --- | --- | --- |
| `root` | Exactly one | Forwards its child's result. It must be the node identified by `root_id`. |
| `selector` | One or more | Evaluates from the first child on every tick. The first child that returns Success or Running wins. If every child fails, the selector fails. A higher-priority branch can interrupt a running lower-priority branch. |
| `sequence` | One or more | Continues in order after each Success. The first Failure ends the sequence. Resumes a Running child on the next tick and succeeds once all children succeed. |
| `parallel` | One or more | Ticks unfinished children in authored order during one runner tick. It remembers each child's terminal result for this activation. `success_threshold: int = 0` means all children must succeed. A positive success threshold and `failure_threshold: int = 1` must be within the child count. The first threshold reached ends the Parallel and aborts any running siblings. If all children finish without reaching either threshold, it fails. |
| `utility` | One or more | Scores its direct children. `strategy: String = "weighted"` or `"highest"`, and `retry_backoff: float = 0.0` seconds. See [Utility scoring](#utility-scoring). |
| `condition` | None | Checks a Blackboard `key`, `op`, and any needed `value`. Returns Success when the check passes, Failure otherwise. For legacy resources, a condition leaf can supply a nonempty `conditions` list in place of `key`. |
| `action` | None | Requires a nonempty `key` string naming a host callback action. Optional `parameters: Dictionary` supplies per-node configuration. |
| `script_task` | None | Requires a `script: Script` resource with the [Script Task contract](#script-tasks). Optional `parameters: Dictionary` supplies per-node configuration. |
| `native_task` | None | Requires a registered compiled task ID in `block: String` or `StringName`. Optional `parameters: Dictionary` supplies the block's configuration. |
| `wait` | None | `duration: float = 1.0` seconds. Returns Running while accumulating tick delta, then Success. A duration of zero succeeds immediately. |
| `set_blackboard` | None | Requires a declared or inferred `key` and a compatible `value`. Writes the value to the runner and succeeds. Authored Arrays and Dictionaries are copied per execution. |
| `erase_blackboard` | None | Requires a declared or inferred `key`. Erases the current value and succeeds even if the key already has no value. Reset restores any authored default. |

### Execution decorators

Use one of these kinds as a standalone node with exactly one child, or place the same settings in a node's `decorators` array. For an attachment, supply only `kind`, the relevant settings, and an optional `label`. The first attachment is the outermost. A stack of `inverter` followed by `succeeder` inverts the Succeeder's final result. Running remains Running through either result decorator.

| `kind` | Settings and behavior |
| --- | --- |
| `inverter` | Swaps terminal Success and Failure. |
| `succeeder` | Converts either terminal result to Success. Displayed as **Always Succeed** in the editor. |
| `repeat` | `count: int = 1`, at least one. Succeeds after that many successful runs and fails on the first Failure. After a success that requires another run, starts the next run on a subsequent runner tick. |
| `retry` | `count: int = 1`, at least one, including the first attempt. Succeeds when the child succeeds and fails when the attempts are exhausted. After a failure that permits another attempt, starts it on a subsequent runner tick. |
| `timeout` | `duration: float = 1.0` seconds. Counts the wrapper's tick delta. At or after the deadline it aborts a running child and fails before ticking that child again. |
| `cooldown` | `duration: float = 1.0` seconds. Starts when the child returns a terminal result. Returns Failure on reentry before the deadline. A running child can finish normally, and aborting the wrapper clears the current execution without starting a new cooldown. |

Durations and intervals must be finite and non-negative. Attached execution decorators preserve the authored node ID in action history, Utility decisions, and active-node diagnostics.

## Blackboard and guards

A nonempty `blackboard_schema` enables strict declarations. Each entry is a dictionary with `type` set to a Godot Variant type such as `TYPE_BOOL`, `TYPE_FLOAT`, or `TYPE_VECTOR3`. Set `external: true` for values supplied by the host, a task, or a service. A key with `external: false` (the default) requires an authored default. An external key may also provide a default.

The runtime accepts values matching the declared type, converts an integer written to a float key, and accepts `null` for `TYPE_OBJECT`. `TYPE_NIL` is the declaration for an unconstrained Variant. An invalid host write reports a Godot error and leaves the old value intact. Supply a nonempty key name. With an empty schema, the runner infers declarations from `blackboard_defaults`. That compatibility mode allows extra host-supplied keys and warns about undeclared guard or Utility references. Set Blackboard and Erase Blackboard require declared or inferred keys in either mode.

Read with `runner.get_value(&"key", fallback)` and write with `runner.set_value(&"key", value)`. The fallback applies to absent keys. A present key can contain `null`. Use `get_blackboard()` for a copied snapshot. Object values retain their Godot object identity.

A `conditions` array is an ordered list of Blackboard guards. All entries must pass. Each uses the following keys.

| Field | Meaning |
| --- | --- |
| `key` | Required Blackboard key name. |
| `op` | `"truthy"` (default), `"falsy"`, `"exists"`, `"missing"`, `"=="`, `"!="`, `"<"`, `"<="`, `">"`, or `">="`. The comparison aliases are `eq`, `ne`, `lt`, `lte`, `gt`, and `gte`. |
| `value` | Required for comparisons. Use a value compatible with the key's declared type. |
| `mode` | `"continuous"` (default) checks on entry and while the node is active. `"entry"` checks when the node enters and can let a committed action finish after its admission flag changes. |

For example, `{"key": "distance", "op": "<=", "value": 2.5}` can gate a short-range action. Use `exists` and `missing` for key presence. Truthiness uses the Godot Variant value, so an absent key is falsy. A failed continuous guard aborts the active branch and runs its cleanup. Guards on an authored node gate its entire attached execution decorator stack. A `condition` leaf's own inline predicate remains inside that stack, so an attached Inverter can flip it.

## Utility scoring

Put `weight: float = 1.0` and `considerations: Array = []` on the Utility's **direct child**. The starting weight must be finite and non-negative. The Utility first checks the child's guards, then multiplies the weight by each consideration factor. A score of zero makes the candidate unavailable. With no considerations the score is the weight.

| Consideration field | Meaning |
| --- | --- |
| `source` | `"blackboard"` (default), `"time_since_attempt"`, or `"time_since_success"`. |
| `key` | Required for a Blackboard source. Integer, float, and Boolean values can be scored. Booleans contribute input 0 or 1. Missing, non-numeric, or non-finite inputs produce a factor of zero. |
| `action_id` | For a history source, the ID of an Action, Script Task, or Native Task. Omit it to use a direct action candidate's own history. A composite candidate must specify an action ID. |
| `min`, `max` | Defaults `0.0` and `1.0`. A finite increasing input range used to clamp and normalize the source value. A history event that has never happened uses `max`. |
| `curve` | Optional Godot `Curve`. The normalized input maps to the curve's domain. The sampled value is clamped to 0–1. With no curve or an empty curve, the normalized input is the factor. |

For instance, the consideration `{"source": "time_since_success", "min": 0.0, "max": 3.0}` makes a candidate's factor rise from 0 to 1 during the three seconds after its last success. History uses the runner's accumulated tick delta. An attempt is recorded when the action enters, and success when the action returns Success.

`"weighted"` chooses among positive scores in proportion to their values. `"highest"` chooses the highest score and breaks ties in child order. If the selected child fails, the Utility can try other eligible candidates in the same tick. It keeps a Running child until completion, interruption, or requested reconsideration. A Utility that exhausts its choices or finds none returns Failure and starts its optional retry backoff. It returns Failure while backoff remains so the parent can take another branch.

An active action callback or task can call `runner.request_utility_reconsideration()` to ask the nearest enclosing Utility to rescore on its next evaluation. It returns whether an enclosing Utility accepted the request. A child that wins again keeps its active state. A different chosen branch can interrupt the current one.

## Actions, script tasks, and services

### Host actions

Pass a stable Callable to `runner.tick(delta, handler)`. The runner calls it as `handler(action: StringName, phase: StringName, delta: float)` with phases `&"enter"`, `&"tick"`, and `&"exit"`. The first evaluation enters and ticks the action during the same runner call. Use the phase's `delta` for work in `tick` and return one of these integers from that phase.

| Constant | Value | Meaning |
| --- | --- | --- |
| `AIBehaviorRunner.FAILURE` | 0 | The action ended unsuccessfully. |
| `AIBehaviorRunner.SUCCESS` | 1 | The action finished successfully. |
| `AIBehaviorRunner.RUNNING` | 2 | The action remains active. |

The runner ignores `enter` and `exit` return values. An invalid tick result ends the action with Failure. Exit runs once when the action ends or is aborted, including when a continuous guard fails, another branch takes over, the runner resets, or the runner leaves the scene tree. An Action reached with no valid Callable returns Failure. Changing the Callable while a host action is active stops the current execution through the original Callable before the new one runs.

Read `get_action_parameters()` inside the callback to distinguish nodes with the same action key. If concurrent actions under Parallel use the same handler, keep their mutable state per action instance or identify the node through its own parameter. Script Tasks already have a separate object per node.

### Script tasks

Save this as `res://inspect_task.gd` to move the inspection logic into the tree's own task. In the builder, change node 2's kind to `"script_task"`, replace its `key` with `"script": preload("res://inspect_task.gd")`, and keep its parameters, conditions, and cooldown. Replace `runner.tick(delta, _run_action)` with `runner.tick(delta)`.

```gdscript
extends RefCounted

var _elapsed := 0.0


func enter(_runner: AIBehaviorRunner) -> void:
	_elapsed = 0.0


func tick(runner: AIBehaviorRunner, delta: float) -> int:
	_elapsed += delta
	if _elapsed < 0.25:
		return AIBehaviorRunner.RUNNING
	var label: String = runner.get_action_parameters().get("label", "Target")
	var completed: int = runner.get_value(&"inspect_count")
	runner.set_value(&"inspect_count", completed + 1)
	print("Inspected ", label)
	return AIBehaviorRunner.SUCCESS


func exit(_runner: AIBehaviorRunner) -> void:
	_elapsed = 0.0
```

The script must extend `RefCounted` or a subtype and instantiate without constructor arguments. Its required `tick(runner, delta) -> int` uses the same three result constants as host actions. `enter(runner)` and `exit(runner)` are optional. Callbacks are synchronous. A script instance belongs to one runner and one node and keeps its fields across activations. Use `enter` for fields that should reset on every activation.

Use custom Script Tasks to connect project-specific game logic. The compiled tasks and services are documented in [Behavior blocks](behavior-blocks.md).

### Native tasks and services

Choose a compiled block by ID. Use `kind: "native_task"` on a leaf and `block` in place of the script resource. The task participates in guards, timing decorators, and action history. `tree.validate()` checks that the ID is registered as a task. The category guide defines the block's parameters and input and output types.

```gdscript
{"id": 2, "kind": "native_task", "block": "wait_for_clear_shot",
 "parameters": {"clear_key": "shot_clear", "result_key": "shot_decision", "timeout": 0.8}}
```

For a compiled service, use `block` in its `services` entry. The owner sets the interval and can mix native and script services in the same ordered array. Each attachment has one implementation. The service runs immediately on activation and on subsequent due ticks. It exits after the active body and children clean up. Put sensors on an ancestor when their outputs feed guards on descendants.

```gdscript
"services": [{"block": "estimate_target_motion", "interval": 0.1}]
```

Task and service instances belong to one runner and are recreated on reset or plan replacement. Hosts bind external callables and current game facts after assigning or resetting the tree. Native trace events include the block ID in `block`. [Compiled block catalog and examples](behavior-blocks.md#compiled-block-catalog)

### Services

A service runs alongside its owning node, before that node evaluates its body or children. Attach an ordered `services` array to the owner. Each dictionary contains `script: Script` or a registered `block` service ID, optional `interval: float = 0.2` seconds, optional `label: String`, and optional `parameters: Dictionary`. Inside a script service callback, read the parameters with `runner.get_service_parameters()`.

Save this example as `res://observe_input.gd`. It can supply the builder's `has_target` key from a service on node 0. Add the following field to that node and remove the direct host write to `has_target` in `_tick_ai`. The service and the Script Task can run in the same tree.

```gdscript
extends RefCounted


func tick(runner: AIBehaviorRunner, _delta: float) -> void:
	var key: StringName = runner.get_service_parameters().get("key", &"has_target")
	runner.set_value(key, Input.is_physical_key_pressed(KEY_SPACE))
```

```gdscript
"services": [
	{
		"label": "Observe input",
		"script": preload("res://observe_input.gd"),
		"interval": 0.0,
		"parameters": {"key": &"has_target"},
	},
],
```

Each attachment gets a separate no-argument `RefCounted` script instance per runner. Optional `enter(runner)` precedes its immediate first `tick(runner, delta)`. Later ticks use the accumulated delta since the last invocation. An interval of zero runs on every owner evaluation. A long frame runs each due service once. Service ticks have no return status. When the owner ends or is aborted, its body and active children clean up, then `exit(runner)` runs for entered services in reverse attachment order. With an attached Repeat or Retry, a service on the body enters and exits on each attempt.

A guard must pass before that owner's services run. Put a sensing service on an ancestor when the service should update facts used to admit child branches.

## Runner lifecycle and diagnostics

| `AIBehaviorRunner` property or method | Contract |
| --- | --- |
| `tree: AIBehaviorTree` | Assign the definition before publishing runtime values. `set_behavior_tree(tree)` and `get_behavior_tree()` are the method equivalents. |
| `tick(delta: float, action_handler: Callable = Callable()) -> int` | Advances one evaluation with finite, non-negative delta in seconds. Call it from the host's update loop. An invalid compiled tree returns Failure. |
| `get_value(key: StringName, default = null) -> Variant` | Reads the current Blackboard value or the default for a missing key. |
| `set_value(key: StringName, value: Variant) -> void` | Publishes a Blackboard value using the type rules above. |
| `get_blackboard() -> Dictionary` | Returns a copy of the Blackboard. |
| `get_action_parameters() -> Dictionary` | Reads the current action's parameters during a callback. Outside a callback, it reads the first active action's parameters in tree order if there is one. |
| `get_service_parameters() -> Dictionary` | Reads the current attachment's parameters inside a service callback. Returns an empty dictionary outside service callbacks. |
| `request_utility_reconsideration() -> bool` | Requests a new score pass for the nearest enclosing Utility from an active action callback. |
| `get_action_history(action_id: int) -> Dictionary` | For an Action, Script Task, or Native Task ID, returns `attempt_at`, `success_at`, `time_since_attempt`, and `time_since_success` in seconds. Unobserved fields are `null`. An invalid action ID returns an empty dictionary. |
| `reset() -> void` | Exits the active execution and restores authored defaults. Resets timers, history, and task and service instances. A legacy optional Callable is accepted. Cleanup still uses the Callable that entered the action. |
| `get_active_node_ids() -> PackedInt32Array` | Returns the authored IDs of active nodes, including multiple running branches under Parallel. Available without debug tracing. |
| `debug_enabled: bool` | Enables detailed tracing for this runner. `set_debug_enabled(enabled)` and `is_debug_enabled()` are the method equivalents. |
| `get_debug_snapshot() -> Dictionary` | Returns detailed diagnostics when enabled and an empty dictionary otherwise. |

Publish facts before each tick or from callbacks in the tree. Invoke ticks, resets, and tree assignment outside behavior callbacks. Assigning a different tree resets that runner. Editing the current resource's compiled definition closes the old execution on the next tick and clears its history, timers, and script instances. Compatible Blackboard values survive the edit, and missing keys can take their new defaults. A shared resource edit affects each runner when it next ticks.

The debug snapshot includes the following fields.

| Field | Meaning |
| --- | --- |
| `active_node_ids`, `last_status`, `tick`, `time` | Current execution, most recent tick result, debug tick count, and runner time in seconds. |
| `rejected_guard`, `interrupted_guard`, `failed_guard` | Latest guard results from the current tick. Guard records contain `node_id`, `key`, and `mode`. `failed_guard` prefers an interruption when both occurred. |
| `utility_scores` | Candidate scores computed during the current tick, keyed by authored child ID. |
| `decision` | Last recorded Utility selection, with `utility_id`, `selected_id` (`-1` when none), `scores`, `candidates`, `strategy`, and `tick`. Weighted selections can include a normalized `roll`. Candidate details include guard result, availability, weight, final score, and consideration inputs and outputs. |
| `retry_remaining` | Active Utility retry backoff by authored node ID, in seconds. |
| `events` | Up to 24 recent trace events, including action entry, exit, abort, guard interruptions, timeouts, and service entry or exit. Service events identify the owner node and zero-based attachment index. |
| `blackboard` | A copy of the runner's current Blackboard. |


In `decision.candidates[child_id]`, `guard_passed`, `available`, `weight`, and `final_score` describe the candidate. A guard rejection can include `rejected_guard`, and an evaluated child can include `attempt_status`. Each item in `considerations` includes `source` and its `key` or `action_id`, `observed`, `raw_input`, `effective_input`, `normalized_input`, `curve_output`, `factor`, and `running_product`. A decision stays available while a committed branch keeps running. If several Utilities score during one tick, the most recent decision occupies this field.
