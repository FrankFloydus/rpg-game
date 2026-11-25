# Diagnostics and verification

## Watch one behavior runner

Set `debug_enabled = true` on the `AIBehaviorRunner` you want to inspect and read `get_debug_snapshot()` after it ticks. You can do this in a game script, a temporary probe, or a test. The runner supplies the trace directly. Leave the flag off for the other actors, and turn it off when you are done. Disabling it discards the trace, and `get_debug_snapshot()` then returns an empty dictionary. `get_active_node_ids()` is available independently of the trace.

In the demo, each spawned enemy has a `Brain` child of type `AIBehaviorRunner`. This temporary probe can be called with the live arena's `Enemies` node after the first archer spawns. Read the snapshot in your probe after a physics update. For a manually ticked runner, read it immediately after calling `tick()`. The actor already ticks its own runner in the arena.

```gdscript
var watched_runner: AIBehaviorRunner


func watch_first_archer(enemies: Node) -> void:
	if is_instance_valid(watched_runner):
		watched_runner.debug_enabled = false
	watched_runner = null
	for enemy in enemies.get_children():
		if not enemy.get("ranged"):
			continue
		watched_runner = enemy.get_node("Brain") as AIBehaviorRunner
		watched_runner.debug_enabled = true
		break


func print_watch_sample() -> void:
	if not is_instance_valid(watched_runner):
		return
	var snapshot := watched_runner.get_debug_snapshot()
	print(snapshot)
	print(watched_runner.get_meta(&"ai_debug_reason", ""))
	print(watched_runner.get_meta(&"ai_debug_diagnostics", {}))
```

Keep the returned runner reference if you want to follow the same actor. Resetting a wave frees its enemies and invalidates the reference. Call the selection function again once the new wave spawns. In your own game you can pick a unit by name, selection, or a test fixture reference. The two metadata reads are optional demo data published by the actor. The native snapshot has the same structure in any project.

| Snapshot field | What to inspect |
| --- | --- |
| `active_node_ids` | IDs of all active nodes in traversal order. Match each ID to an authored record in `runner.tree.get_nodes()`. A Parallel can have several live branches, including several leaf actions. A completed action can disappear from this list on the same tick it finishes. |
| `last_status`, `tick`, `time` | Latest tick result and its position in the trace. `AIBehaviorRunner.FAILURE`, `SUCCESS`, and `RUNNING` have values 0, 1, and 2. Time is accumulated runner tick time in seconds. |
| `rejected_guard`, `interrupted_guard` | Guard that blocked entry or interrupted an active branch, when recorded on that tick. `failed_guard` is an alias that prefers the interruption if both exist. |
| `utility_scores`, `decision` | Scores evaluated this tick and the latest selection. The saved decision can be from an earlier tick if a branch remains committed. |
| `retry_remaining` | Positive retry timers in seconds, keyed by authored node ID. |
| `events` | The most recent 24 transitions, including action entry, normal exit, abort, timeout, guard interruption, and service entry or exit. Use the event tick, time, and node ID to correlate the transitions. |
| `blackboard` | A copy of the runner's current blackboard. Object values can still refer to live objects. Convert those values to identifiers before writing a portable JSON log. |

Use `runner.get_value(&"key", fallback)` to inspect one blackboard key and `runner.get_blackboard()` for all keys. Inspect one runner at a time when checking whether a branch sees the correct target or a service's write. Keep resource defaults and current runner values distinct when comparing two actors.

For action timing, compare `action_enter`, `action_exit` and `action_aborted` events with `runner.get_action_history(node_id)`. The history reports `attempt_at`, `success_at`, `time_since_attempt`, and `time_since_success`. An unobserved timestamp is null. Read `get_action_parameters()` inside the action callback to inspect its authored arguments, especially with parallel branches. Callback actions receive `enter`, `tick`, and `exit` phases. Check the status returned by `tick` and whether cleanup ran after an interruption.

For a utility choice, inspect `decision.utility_id`, `selected_id`, `strategy`, `tick`, and the optional random `roll`. The per-child `candidates` records include guard outcome, weight, final score, and each consideration's raw and effective input, normalized input, curve output, and factor. Check `observed` when scoring against action history. The same candidate can start off cooldown before an action has ever been attempted and produce a lower score after the first attempt.

Services report `service_enter` and `service_exit` with the attached node ID, service index, label, and script path. For cadence, log or count calls inside the service's `tick(runner, delta)`. The trace records lifecycle transitions and the service's blackboard writes can be observed in snapshots. Read `runner.get_service_parameters()` inside the service callback. On entry the service ticks immediately. Afterward its interval is measured in runner time and an interval of zero ticks it on every runner evaluation of the active node.

## Reproduce gameplay

Run the normal arena and choose **1** for 12 melee enemies, **2** for a 56-enemy mixed wave, or **3** for six archers. **I** keeps the player alive for movement and launch observations. **V** shows movement goals, **Tab** switches to overhead, and **R** resets the preset. Use `res://ai_demo/stress_arena.tscn` for the 100-enemy mixed wave, which starts overhead with an ally. Watch the runner's snapshot alongside the demo's `Motion`, `Melee position`, `Attack`, and `Firing lane` diagnostics as applicable to the actor.

| Scenario | Fixture and expected observation |
| --- | --- |
| Melee approach and waiting | With a live stationary target, watch requested, avoidance-safe, and actual velocity alongside the waypoint and final slot. A queued actor at its waiting point can stand still. To test recovery, obstruct a claimed route with a real collider or feed zero safe velocity to one actor in a test fixture while it still requests movement. Observe recovery to a reachable route after releasing the obstruction. |
| Melee attack turns and camera | Hold target position fixed and compare facing toward and away from a crowd. Record slot ownership, attack pressure, actual animation starts and impacts, and any warnings separately. Check that a yielding or flank-approach actor cannot start an attack while completing that movement. Test contention around both the player and the ally. |
| Archer blocked by another enemy | Put a moving friendly collider in a valid shot path. Observe the archer holding or repositioning, then clear the path. A transient blockage can delay a release, and the exact shot path must be clear at release. Place a world collider in the same path to test a solid-cover cancellation. Count projectile launches and actual impacts separately. |
| Reachable cover vs. a sealed target | Place a live target behind a wall with a connected navmesh route around it. Expect some archers to obtain firing lanes or pursue until they can. Repeat with a sealed or disconnected region and no legal ray. The fixture should show no launches through that wall and should resume combat when the target returns to reachable space. Keep all collision layers and navigation data active. |
| Dense cover | Start the 100-enemy preset, disable the ally for a single-target case, and place a living stationary player near cover, for example at `Vector3(7.0, 0.04, -1.75)` in the saved stress arena. Record launches and impacts per shooter over a fixed window. Inspect range, exact current muzzle rays, lane state, and actual travel on any silent shooter. |
| No target and recovery | Disable the ally and let the player die. Confirm units stop pursuing an active target. Repeat with the ally enabled and look for retargeting. Reset to verify combat resumes with a live player. |

For repeatable tests, put tuning values on in-memory fixtures. Wait for navigation synchronization and the wave spawn to finish before checking crowd behavior. Test authored resource references and validation separately from behavioral assertions. In a damage fixture, player invulnerability bypasses `hit_received`; leave invulnerability off and restore health before death if the test needs that signal. Keep impact counts distinct from launches because an actor can enter the bolt's path after release.

Useful behavior-tree fixtures include a continuous guard flipping while an action is running, a timeout that calls cleanup exactly once, and a Parallel with two active leaves. For utility scoring, use a deterministic highest-score fixture for exact selection and assert availability, relative scores, and valid outcomes for weighted selection. For services, use a fixture-owned typed blackboard counter or a callback log to test immediate activation, interval, exit, and separate instances for two runners. Assert gameplay outcomes and invariants across repeat runs, since physics and avoidance scheduling can affect individual trajectories.

## Build and smoke test

From the repository root on Windows x86-64, use a shell with Python, SCons and MSVC available. Set `$godot` to your Godot 4.7 console executable.

```powershell
git submodule update --init --recursive
scons platform=windows arch=x86_64 target=template_debug
scons platform=windows arch=x86_64 target=template_release
$project = (Resolve-Path -LiteralPath .\project).Path
& $godot --headless --editor --path $project --quit-after 180
& $godot --headless --path $project --fixed-fps 60 --quit-after 120 res://ai_demo/arena.tscn
& $godot --headless --path $project --fixed-fps 60 --quit-after 720 res://ai_demo/stress_arena.tscn
python tools/package.py
python -m zipfile -t ..\dist\godot-ai-system-addon-windows-x86_64.zip
python -m zipfile -t ..\dist\godot-ai-system-windows-x86_64.zip
```

Check import and game output for GDExtension loading, missing resources, and script errors, including errors printed by Godot when the exit code is zero. Repeat the smoke test on an extracted demo archive. In a fresh Godot project containing the extracted addon, verify that the GDExtension loads and a script can instantiate `AIBehaviorTree`, `AIBehaviorRunner`, `AIEncounter3D`, and `AIHordeDirector`. Validate the authored demo trees with `AIBehaviorTree.validate()` and inspect every reported error. Smoke runs verify loading and ticking. Use the fixtures above to check behavior.

## Profile the 100-enemy scene

Use a clean scratch copy of the demo. Keep debug traces off. Use a release export for measurements of a shipped executable. With the Godot editor executable, its debug feature tag selects the debug entry of the addon manifest. To measure the optimized addon with that executable, first close Godot for the scratch copy and put the release DLL in the debug slot there. Record which engine executable and native binary you tested.

```powershell
$bin = Join-Path $scratchProject "addons/godot-ai-system/bin/windows"
$release = Join-Path $bin "godot-ai-system.windows.template_release.x86_64.dll"
$debug = Join-Path $bin "godot-ai-system.windows.template_debug.x86_64.dll"
Copy-Item -LiteralPath $release -Destination $debug -Force
Get-FileHash -LiteralPath $release, $debug
& $godot --headless --editor --path $scratchProject --quit-after 180
```

Save the following as `stress_profile.gd` in that scratch project. It keeps the default camera and ally, keeps the player alive without input, warms up until the wave is present, and reports 600 fixed-step wall-time samples. The viewport timers also report renderer CPU and GPU work when supported by the active backend.

```gdscript
extends SceneTree

const STRESS_SCENE := preload("res://ai_demo/stress_arena.tscn")
const WARMUP_STEPS := 620
const SAMPLE_STEPS := 600


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var arena := STRESS_SCENE.instantiate()
	root.add_child(arena)
	arena.get_node("Player").set("invulnerable", true)
	var encounter := arena.get_node("Encounter") as AIEncounter3D
	var enemies := arena.get_node("Enemies")
	var rendered := DisplayServer.get_name() != "headless"
	var viewport := root.get_viewport_rid()
	if rendered:
		RenderingServer.viewport_set_measure_render_time(viewport, true)
	for step in WARMUP_STEPS:
		await physics_frame
	if enemies.get_child_count() != 100:
		push_error("Expected 100 enemies before sampling.")
		quit(1)
		return

	var wall_ms: Array[float] = []
	var render_cpu_ms: Array[float] = []
	var render_gpu_ms: Array[float] = []
	var max_candidates := 0
	var max_paths := 0
	var deferred := 0
	var previous_usec := Time.get_ticks_usec()
	for step in SAMPLE_STEPS:
		await physics_frame
		var now_usec := Time.get_ticks_usec()
		wall_ms.append((now_usec - previous_usec) / 1000.0)
		previous_usec = now_usec
		var search := encounter.get_ranged_search_stats()
		max_candidates = maxi(max_candidates, search.previous_candidates)
		max_paths = maxi(max_paths, search.previous_path_queries)
		deferred += int(search.previous_deferred)
		if rendered:
			render_cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport))
			render_gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))

	_report("wall", wall_ms)
	if rendered:
		_report("viewport CPU", render_cpu_ms)
		_report("viewport GPU", render_gpu_ms)
	print("Ranged search maxima candidates=%d paths=%d deferred_total=%d" %
		[max_candidates, max_paths, deferred])
	quit()


func _report(label: String, samples: Array[float]) -> void:
	var total := 0.0
	for sample in samples:
		total += sample
	samples.sort()
	var count := samples.size()
	print("%s ms: mean=%.3f p95=%.3f p99=%.3f" %
		[label, total / count, samples[ceili(count * 0.95) - 1],
		samples[ceili(count * 0.99) - 1]])
```

```powershell
& $godot --headless --path $scratchProject --fixed-fps 60 --script res://stress_profile.gd
& $godot --path $scratchProject --fixed-fps 60 --disable-vsync --resolution 1280x720 --script res://stress_profile.gd
```

Run each mode three times in fresh processes and compare the median of the run-level means, p95s, and p99s. Report hardware, renderer, resolution, binary, actor count, target setup, and sample window. The headless wall time includes engine and simulation work in that process. Rendered wall time includes render work and scheduling, with some GPU work overlapping CPU work. Fixed FPS controls simulated time here. Use the measured intervals as workload timings. A zero GPU timer can mean the backend does not expose timings, so record availability alongside the results.

`get_ranged_search_stats()` exposes current and previous physics-step counters. At the `physics_frame` signal, read the previous step as in the probe. Compare the candidate and navigation path maxima against the encounter's `ranged_candidates_per_step` and `ranged_paths_per_step`. Deferred requests indicate budget pressure. Combine these counters with observed time to find a usable lane and per-shooter launch and impact counts so a faster run also has comparable gameplay. Profile a deliberately blocked or disconnected crowd separately from the default stress preset.
