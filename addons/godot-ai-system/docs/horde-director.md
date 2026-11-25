# Horde director

`AIHordeDirector` is an optional native `Node` that a game can instantiate and configure entirely from GDScript. It advances an encounter through pressure phases, checks population budgets and wave cooldowns, and chooses a spawn gate from facts provided by the game. The host owns the clock call, navigation and visibility queries, actor creation, and queued spawns. The director works independently of `AIBehaviorRunner` and `AIEncounter3D`.

## Integrate it in a game

1. Install the addon as described in the [README](../README.md). Add an `AIHordeDirector` node to the encounter scene or create one with `AIHordeDirector.new()`. Set its properties in GDScript or serialize them in the scene.
2. Register every active hero or other pressure target with `register_pressure_target(target)`. Feed gameplay events such as a hit, a block, or a nearby defeat into `record_target_pressure(target, amount)`. Use `record_pressure(amount)` for encounter-wide events. Choose the amounts in the game.
3. Call `update_encounter(elapsed_seconds, population, candidates)` from one host loop. If you sample at a fixed interval, pass the elapsed time since the previous call. This drives pressure decay, phase transitions, and channel cooldowns. You can pass an empty candidate array while the map is loading or while the encounter has no eligible target, so the clocks still advance.
4. Read `spawn_id`, `channel`, and `composition` from a nonempty request. Resolve the gate and archetype IDs using the game's own data. Enqueue the accepted members immediately so the next population snapshot includes them. Instantiate them on the host's schedule.
5. Unregister a target when it leaves play, including when a dead or disabled target remains in the scene. Reset the director and manage the game-owned actors and spawn queue when restarting the encounter.

## Pressure and phases

The director stores global pressure and a separate pressure meter for each registered object. A finite positive impulse adds to that meter up to 100 and refreshes its grace period. Once grace expires, the remaining elapsed time reduces the meter at `pressure_decay` points per second, down to zero. `get_pressure()` returns the global meter plus the arithmetic mean of the target meters, capped at 100. Registered targets with zero pressure count in the mean. For example, a global meter of 5 and two target meters of 40 and 0 yield aggregate pressure of 25.

Recording a valid target impulse also registers that target. Explicitly registering all eligible targets gives consistent averaging before they receive their first impulse. The director removes freed objects on its next valid update. An alive object that should stop contributing needs an explicit `unregister_pressure_target()` call. `get_target_pressure()` returns zero for null or unregistered targets.

| `get_state()` | Transition | Wave admission |
| --- | --- | --- |
| `&"build_up"` | Aggregate pressure reaches `peak_pressure`. | Eligible profiles can request a wave, including on the tick that enters sustain. |
| `&"sustain"` | `sustain_duration` expires. | Eligible profiles can request a wave until the tick that enters fade. |
| `&"fade"` | Aggregate pressure falls to or below the smaller of `fade_pressure` and `peak_pressure`. | No requests. Channel timers pause. |
| `&"relax"` | `relax_duration` expires. | Profiles with `allow_during_relax` can request a wave on ticks spent in relax. Their channel timers also run in this phase. |

The update decays pressure before checking transitions. A single call evaluates one phase transition at most. The calls that enter relax and return to build-up produce no request. On return to build-up, channels that only run in combat phases restart their startup delay. Channels with at least one relax-enabled profile keep their existing cooldown. Pressure can accumulate during fade or relax, and a quiet encounter can remain in build-up indefinitely.

## Director properties

Set these directly on the node, for example `director.startup_delay = 2.0`. Each property also has a bound `set_<property>()` and `get_<property>()` method.

| Property | Default | Meaning |
| --- | --- | --- |
| `wave_profiles` | `[]` | Array of dictionaries defining wave composition and admission. An empty array enables the built-in horde profile. |
| `wave_size` | 12 | Size of the built-in wave and the limit returned by legacy `update_pacing()`. Minimum 1. Authored waves derive their size from their composition. |
| `max_active_enemies` | 48 | Global active-plus-queued population cap. Minimum 1. |
| `startup_delay` | 3.0 s | Delay applied when an update mode first starts its wave clock and when combat-only channels return to build-up. Minimum zero. |
| `wave_interval` | 8.0 s | Default cooldown after a successful wave request. Minimum 0.1 s. |
| `peak_pressure` | 35.0 | Minimum aggregate pressure for sustain. Range 0.1–100. |
| `fade_pressure` | 12.0 | Pressure at or below which fade can end. Range 0–100, with the effective threshold capped at `peak_pressure`. |
| `pressure_decay` | 6.0/s | Linear decay for each meter after its grace period. Minimum 0.1/s. |
| `pressure_grace` | 1.5 s | Time for which a new impulse holds its meter before decay. Minimum zero. |
| `sustain_duration` | 3.0 s | Time spent in sustain after hitting peak pressure. Minimum zero. |
| `relax_duration` | 8.0 s | Time spent in relax after fade. Minimum zero. |

Use a smaller `fade_pressure` than `peak_pressure` if you want a clear interval between the rising and falling thresholds. The director measures seconds from supplied deltas. It does not catch up with multiple waves after a large delta.

## Author wave profiles

A profile is an editable dictionary in the node's **Wave Schedule → Wave Profiles** array. You can also assign the array in script. Channels are game-defined population and cooldown categories, such as `"horde"`, `"special"`, or `"roamer"`.

| Field | Type and default | Use |
| --- | --- | --- |
| `channel` | Required `String` or `StringName` | Nonempty population key. `"total_active"` and `"threat"` are reserved. |
| `composition` | Required `Array` | Ordered list of nonnegative integer or nonempty string archetype IDs. Repeat an ID to request multiple copies. |
| `max_alive` | Optional `int`, defaults to the global cap | Maximum active-plus-queued members of this channel. Explicit zero prevents admission. Omit the field to inherit the global cap. Negative integers clamp to zero. |
| `max_threat` | Optional number, defaults to unlimited | Largest current total threat at which this profile can admit a wave. Equal values pass. |
| `interval` | Optional seconds, defaults to `wave_interval` | Positive override for the channel cooldown after this profile wins. Values between zero and 0.1 clamp to 0.1. Nonpositive values use the default. |
| `min_spawn_distance` | Optional number, defaults to 0 | Inclusive lower bound in the host's distance units. |
| `max_spawn_distance` | Optional number, defaults to unlimited | Inclusive upper bound in the same units. |
| `approach` | Optional `String`, defaults to `"any"` | `"ahead"` requires a positive `path_offset`. `"behind"` requires a negative one. A zero offset only qualifies for `"any"`. |
| `allow_visible` | Optional `bool`, defaults to `false` | Allow candidates visible to the host's observers. Hidden gates retain priority. |
| `allow_during_relax` | Optional `bool`, defaults to `true` for `"roamer"` and `false` otherwise | Allow this profile during relax as well as the combat phases. |

The director copies the assigned array and compiles usable entries. It skips malformed profiles and drops invalid members from otherwise usable compositions. A nonempty array with zero usable profiles yields zero waves. An empty array enables a built-in `"horde"` profile with repeated integer ID `0`, hidden and reachable gates, and no relax admission. The `wave_profiles` getter returns a deep copy of the authored data. Assign the edited array back to apply changes. Assigning it restarts the encounter channel clocks and profile rotation on the next call. Use `reset()` if you also want to clear pressure and previous-gate preference.

Profiles in the same channel share one cooldown. When several profiles are eligible, the director searches in authored order, beginning after the last successful profile and wrapping once. A successful request starts that profile's channel cooldown. If a profile is blocked by capacity, threat, or an unsuitable gate, the director can try the next one in the same call.

## Population and threat

`population` is a snapshot from the host. Use a nonnegative integer count under each active channel and include living actors plus accepted spawn jobs waiting to instantiate. For profiles that use the default global cap, the channel still needs an accurate count for bookkeeping.

| Key | Value |
| --- | --- |
| Channel name | Active and queued members of that channel. A missing count is read as zero. |
| `"total_active"` | Optional distinct total across all groups, including any actors outside wave channels. Supply it when categories overlap or the dictionary has other integer metadata. Without it, the director sums integer counts under string keys other than `"threat"`. |
| `"threat"` | Current aggregate cost from the host, usually from the same living and queued members. Defaults to zero. Each profile compares this value with its own `max_threat`. |

Population capacity is the smaller of global remaining capacity and the profile's remaining channel capacity. The request contains the first members of the composition that fit. For example, `["melee", "melee", "archer"]` with two available places requests two melee units. The rest of the composition is discarded for that request. Put essential members early in the array or choose caps that leave enough room for the intended mix.

Threat is a gate on the **current** snapshot. The director has no per-archetype threat costs, so it cannot calculate the projected cost of a requested composition. Apply a projected threat limit in the host if your game requires one. Once a request is returned, its cooldown and rotation advance even if the host subsequently drops a spawn job.

## Spawn candidates

`spawn_candidates` is an array of dictionaries. Give each gate a stable, unique integer ID and keep the corresponding marker or transform in host data.

| Field | Value |
| --- | --- |
| `id` | Integer key that the host can resolve at spawn time. |
| `hidden` | Boolean computed by the host. A conservative policy marks a gate hidden when all relevant players lack a clear view of the entry. Omission behaves as false. |
| `reachable` | Boolean computed by the host using the route or navigation layers the spawned units can use. Check that a path actually reaches the destination or a valid nearby endpoint. Omission behaves as false. |
| `distance` | Required finite distance from the host's chosen reference point to the gate. |
| `path_offset` | Signed progress from the reference, defaulting to zero. On a linear map this can be gate route progress minus the lead player's progress. |

After filtering on reachability, visibility permission, distance bounds, and approach, the director ranks candidates by hidden first, then a gate other than the last one used, then nearest distance, then lowest ID. Avoiding the last gate is a preference across all channels, so a lone viable gate can repeat. If every gate fails the filters, the director returns an empty request and keeps the ready channel eligible for the next call.

Compute these facts in the host using your level's semantics. In 3D, the demo waits until the navigation map is ready, checks that the marker is near the mesh and its path reaches the projected gate, and raycasts from valid targets against world collision. It uses the lead target's facing dot product for arena-relative progress and permits a visible fallback in all three demo profiles. A linear level can use route coordinates instead, so turning the camera has no effect on what counts as ahead. Decide how to handle a gate that becomes blocked or visible between scheduling and instantiation. The demo accepts a request into a queue and releases it in batches.

## API and lifecycle

| Method | Return and effect |
| --- | --- |
| `register_pressure_target(target: Object)` | Adds a zero-initialized meter on first registration. Re-registering preserves the existing meter. |
| `unregister_pressure_target(target: Object)` | Removes its meter from the aggregate. |
| `record_target_pressure(target: Object, amount: float)` | Adds a finite positive impulse for that target. |
| `record_pressure(amount: float)` | Adds a finite positive impulse to the global meter. |
| `get_target_pressure(target: Object)` | Returns that target's `float` pressure. |
| `get_pressure()` | Returns aggregate `float` pressure. |
| `get_state()` | Returns the current phase as a `StringName`. |
| `update_encounter(delta: float, population: Dictionary, spawn_candidates: Array)` | Returns an empty `Dictionary` or one request containing a `String` channel, an integer `spawn_id`, and an `Array` of archetype IDs. |
| `update_pacing(delta: float, active_enemy_count: int)` | Legacy count-only mode. Returns zero or a wave size bounded by `wave_size` and the global cap. It runs in build-up and sustain and uses its own startup delay and interval. |
| `reset()` | Clears all meter values and grace timers, returns to build-up, and resets the wave clocks, profile rotation, and previous-gate preference. Registered targets and authored configuration persist. |

Both update methods share the pressure and phase state and advance that state from their supplied delta. Choose one method per director instance and update it from one loop. Zero, negative, and nonfinite deltas produce no update. Legacy `update_pacing()` leaves gate selection and composition entirely to the host. When using it with a spawn queue, include queued actors in the count.

An empty request is a normal outcome. For diagnostics, log the current phase and pressure, the host's alive-plus-queued counts, and each candidate's flags and distance. Recheck that the host is supplying positive elapsed time and that profile keys match the population snapshot. The public API returns no rejection reason or channel cooldown snapshot.

## Run a script-only configuration

Save this as `res://director_smoke.gd` in a project with the addon installed and imported. Run `godot --headless --path . --script res://director_smoke.gd` using the executable for your Godot 4.7 installation. The script supplies one fixed gate and counts queued jobs immediately. A real host would compute gate facts from the level and transfer queued jobs into live population as it spawns them.

```gdscript
extends SceneTree


func _initialize() -> void:
	var director := AIHordeDirector.new()
	director.startup_delay = 0.0
	director.max_active_enemies = 3
	director.wave_profiles = [{
		"channel": "reinforcements",
		"composition": [&"guard", &"guard", &"scout"],
		"max_alive": 2,
		"interval": 2.0,
		"min_spawn_distance": 8.0,
		"approach": "ahead",
	}]
	var target := Node.new()
	director.register_pressure_target(target)
	director.record_target_pressure(target, 4.0)

	var gates := [{
		"id": 7,
		"hidden": true,
		"reachable": true,
		"distance": 14.0,
		"path_offset": 10.0,
	}]
	var population := {"reinforcements": 0, "total_active": 0, "threat": 0.0}
	var spawn_queue: Array[Dictionary] = []
	var request := director.update_encounter(0.25, population, gates)
	if request.get("spawn_id") != 7 or request.get("composition") != [&"guard", &"guard"]:
		push_error("Expected gate 7 and two guards under the channel cap.")
		target.free()
		director.free()
		quit(1)
		return

	for archetype in request.composition:
		spawn_queue.append({
			"gate": request.spawn_id,
			"archetype": archetype,
			"channel": request.channel,
		})
	population.reinforcements = spawn_queue.size()
	population.total_active = spawn_queue.size()
	population.threat = float(spawn_queue.size())
	var followup := director.update_encounter(2.0, population, gates)
	if not followup.is_empty():
		push_error("Queued guards should fill the channel after the cooldown expires.")
		target.free()
		director.free()
		quit(1)
		return

	print("Director requested two guards at gate 7. The queued guards fill the channel.")
	target.free()
	director.free()
	quit()
```

For a scene-based reference, the arena configures its profiles on `HordeDirector` in `res://ai_demo/arena.tscn`. Run the arena from the demo project and press **P** to enable director pacing. The initial preset waves are queued by the arena. Additional waves after enabling pacing come through `update_encounter()`.
