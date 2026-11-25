# Encounters and navigation

`AIEncounter3D` coordinates enemies that share targets. It selects targets, assigns melee positions, searches for ranged destinations, and meters attacks. Put one encounter node in the gameplay scene and give the participating actors a reference to it. Keep it in the scene tree with physics processing enabled so pressure, recovery timers, and stale registrations advance.

The encounter returns decisions and world-space positions. Your actor follows paths, steers around bodies, chooses animations, tests impacts, and applies damage. `AIBehaviorRunner` can use those facts to choose an action, or a regular GDScript state machine can consume the same results. The demo wires these responsibilities in `res://ai_demo/arena.gd` and `res://ai_demo/enemy.gd`.

## Register and select targets

| Method | Use |
| --- | --- |
| `register_target(target: Node3D)` | Register a live target. Registering the same node again preserves its existing state. |
| `set_target_enabled(target: Node3D, enabled: bool)` | Change availability while keeping the registration. Disabling clears the target's melee claims, ranged plans, and attack meters. Re-enable it after respawn or reset. |
| `unregister_target(target: Node3D)` | Remove the target and its encounter state when it leaves play permanently. |
| `is_target_valid(target: Node3D) -> bool` | Check whether the node is registered, enabled, and available for use. Call this before acting on a cached target. |
| `release_agent(agent: Node3D)` | Drop the actor's melee and ranged state and remove it from every chokepoint. Call this on retarget, despawn, or cancellation when the actor has no further use for those claims. |

`select_target(agent: Node3D, current_target: Node3D, ring: int, include_melee_crowding: bool = true) -> Node3D` returns a registered target or `null`. It favors short distances and gives the current target a stickiness bonus. The default adds a penalty for occupied, queued, and disabled positions in the requested melee ring. Pass `false` for a distance-and-stickiness selector. The selector still expects a valid ring constant, even with crowding disabled.

`acquisition_radius` and `acquisition_mask` apply to newly acquired targets. A valid current target remains eligible through temporary cover or when it leaves the acquisition radius. The acquisition ray uses a 1.1 m vertical offset on both actors. Set the radius or mask to `0` to omit that filter. The demo leaves both at zero so spawned waves are already aware of registered party members.

`select_ranged_target(agent: Node3D, current_target: Node3D, min_range: float, max_range: float, collision_mask: int, muzzle_height: float, aim_height: float) -> Node3D` ranks targets that have a clear shot **from the actor's current position**. It also respects new-target acquisition filters. Use it when a ranged actor wants a viable alternate target. A target behind cover may still be a useful pursuit target chosen by `select_target()` or by your own code.

```gdscript
func choose_target(encounter: AIEncounter3D, actor: Node3D,
		current: Node3D, ring: int, melee: bool) -> Node3D:
	var selected := encounter.select_target(actor, current, ring, melee)
	if selected != current:
		encounter.release_agent(actor)
	return selected
```

Reset the actor's cached destination and progress timer after a target change. The encounter also cleans up freed or queued-for-deletion actors and targets during its physics updates.

## Use the actor's navigation map

Supply the same map RID and navigation layer mask to the encounter that your movement controller uses. For `NavigationAgent3D`, pass `navigator.get_navigation_map()` and `navigator.navigation_layers`. A navigation layer mask filters navmesh regions. A physics collision mask filters ray hits. `NavigationAgent3D` avoidance layers and masks configure steering between agents separately. [Godot NavigationAgent3D reference](https://docs.godotengine.org/en/stable/classes/class_navigationagent3d.html)

The default arguments `RID()` and `1` use the encounter's world map and layer 1 when the map is ready. An explicit RID or a layer mask other than `1` requests a navigation context. Before its map has synchronized usable regions, a planning call can return `pending`. The encounter projects destinations onto matching enabled regions and verifies that the path reaches the intended endpoint. `navigation_snap_distance` limits how far the planner can snap a candidate or path origin to the mesh. A disconnected island or a region on the wrong layer can therefore leave a point unusable even when it looks close in world space. `use_navigation_mesh = false` selects geometric positioning with the applicable obstacle probes. Use that mode only when your movement policy can handle the resulting positions.

Wait for navigation synchronization before requesting routes. Set `navigator.target_position` when the destination changes meaningfully. Then use `get_next_path_position()` during physics processing while following the path, and feed the next point into your movement code. Treat an unreachable or partial route as a recovery case. A path result can become stale as the level or target moves, and avoidance and physics collision can prevent a body from following a complete path. [Godot guide to path following and avoidance](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html)

```gdscript
func plan_melee(encounter: AIEncounter3D, actor: Node3D, target: Node3D,
		navigator: NavigationAgent3D, ring: int) -> Dictionary:
	return encounter.update_position(
		actor, target, ring, navigator.get_navigation_map(), navigator.navigation_layers
	)
```

For frequent movement updates, poll the encounter on a short, staggered timer and steer along the last usable plan each physics step. The demo polls more often when a ranged search needs work. Reset route-following state when the plan changes instead of assigning a new navigation target every frame.

## Melee positions and recovery

`update_position(agent: Node3D, target: Node3D, ring: int, navigation_map: RID = RID(), navigation_layers: int = 1) -> Dictionary` plans around a registered, enabled target. The ring constants are `AIEncounter3D.RING_NORMAL` (`0`, 9 positions), `RING_MEDIUM` (`1`, 8), and `RING_LARGE` (`2`, 4). Their authored radii are 1.85, 2.2, and 2.25 m. Actual available positions depend on obstacles, navmesh projection, paths, and neighboring claims. Choose the ring that matches the actor's clearance and attack reach.

| Field | Meaning |
| --- | --- |
| `position: Vector3` | Current movement destination. Read `status` before following it. |
| `has_slot: bool` | The actor owns a final melee position at the time of this query. |
| `slot_position: Vector3` | Final claimed position when `has_slot` is true, even during a flank approach. With no claim this equals `position`. |
| `occupied: int`, `queued: int` | Owned slots and registered waiters across all rings for this target. An actor at a fallback position may have no queue entry. |
| `status: StringName` | The current phase of the positioning plan. |

| Status | Actor response |
| --- | --- |
| `slot` | Follow the final slot. Check actual reach and the attack's collision conditions before committing. |
| `side_approach` | Follow an intermediate waypoint while retaining the final claim. Poll again at arrival to advance to the slot. |
| `queue` | Move to a waiting point and hold it while checking periodically for promotion. |
| `fallback` | Move to an outside position while searching for a claim or a queue. |
| `yielding` | Give up space for another ring. Follow the retreat point if one was found. This status can return the actor's current position. |
| `pending` | Poll again. A route check may be deferred, and a claimed slot can survive while its approach is pending. |
| `no_route` | The planner found no usable movement route on this update. Hold or run a recovery action and try again. |
| `invalid_target` | Clear the goal and reacquire. Also check the inputs if the target appears valid. |

Approach angle affects candidate order. A reachable rear slot can still be selected, and a side waypoint can guide an actor around the target before it closes in. The coordinator can transfer space to a waiter from another ring after the current owners have held their claims long enough. It protects locked claims and checks spacing before transfer. Displaced actors receive outward movement plans. Let your movement and avoidance code handle bodies that are still crossing during the handover.

When a route stalls, call `report_melee_stuck(agent: Node3D, seconds: float = 1.5) -> bool`. A successful report releases the current unlocked claim or wait entry and temporarily excludes the last movement destination and, when applicable, the slot for that actor. The duration is clamped to `0.1`–`5.0` seconds. A locked assignment or a plan without movement returns `false`. Keep intentionally waiting actors out of stall recovery. The optional `AIMovementProgress` helper accepts `update(position, commanded_speed, delta)` after movement and resets on a route change.

Check `owns_melee_slot(agent: Node3D, target: Node3D) -> bool` before committing an attack that requires a claim. This checks the current owner without a route search. The actor's earlier `has_slot` value can be stale after a handover. `set_slot_locked(agent: Node3D, locked: bool)` keeps the claim through a committed swing. Unlock on normal completion, interruption, or cancellation. A disabled or removed target clears the claim through its lifecycle API.

## Ranged firing lanes

```text
update_ranged_position(agent: Node3D, target: Node3D, min_range: float,
    max_range: float, collision_mask: int, muzzle_height: float, aim_height: float,
    navigation_map: RID = RID(), navigation_layers: int = 1,
    allow_reposition_clear_shooter: bool = true, transient_occluder_mask: int = 0)
    -> Dictionary
```

Pass the full projectile collision mask and the muzzle and aim heights used by your actor. Range is measured in 3D between the actors' origins, inclusive of the supplied limits. The planner's ray uses the actor origin plus `muzzle_height` on Y and the target origin plus `aim_height` on Y. It excludes the actor and target from the obstruction ray when the supplied nodes are themselves collision objects. Your gameplay shot should verify the actual hitbox and impact at release.

| Field | Meaning |
| --- | --- |
| `can_fire: bool` | The exact current-position range and ray passed with the full mask. |
| `found: bool` | The result supplies a position usable for the returned status. A usable position can be a movement goal or the current position. |
| `position: Vector3` | Current position or movement destination. |
| `reposition: bool` | A voluntary spacing move was found. A clear current shot and a spacing move can both be available. |
| `status: StringName` | The firing-lane or search phase. |

| Status | Actor response |
| --- | --- |
| `current` | The current shot is clear. Commit only after your gameplay checks. |
| `goal` | Follow the reachable destination and check the live muzzle at arrival. |
| `goal_occluded` | A verified destination is temporarily blocked by a moving body. Continue toward it or briefly hold on arrival while polling. |
| `approach` | Take a short lateral step and check again for a shot. This waypoint carries no firing reservation. |
| `pending` | Poll again as search work becomes available. Follow a retained destination only if `found` is true. |
| `exhausted` | This search pass found no usable destination. Retry or choose another target or movement action. |
| `route_invalid` | The previous goal became unusable, for example when its path, range, or line of sight changed. Replan or fall back. |
| `invalid_target` | Clear the cached lane and target. Check that ranges and heights are finite and the target is registered and enabled. |

The search starts with local peeks and sweeps bearings around the target before trying additional radii. `ranged_preferred_spacing` gives nearby ranged claims on the same target and navigation map room to spread on overlapping navigation layers. It is a preference for prospective destinations. The search can relax it when no preferred destination is viable. `ranged_reposition_clear_shooters` enables voluntary spacing moves for an already clear shooter. Pass `false` for `allow_reposition_clear_shooter` when the actor should keep a ready shot, such as during a committed release sequence.

Set `transient_occluder_mask` to the bits in the full mask that represent moving bodies. For example, with world, targets, and enemies on layers 1, 2, and 3, use `collision_mask = 7` and `transient_occluder_mask = 4` to classify only enemies as transient. Static geometry can invalidate a goal immediately. A body-only obstruction can hold an already verified destination for `ranged_occlusion_grace`, with a shorter hold for distant goals. When no firing lane is found, the planner may return a lateral waypoint with a short reachable path. Opting in also checks that planned routes stay outside the minimum standoff, with a small tolerance, or move outward when the actor starts inside it. `can_fire` and newly claimed firing destinations still use the full collision mask.

```gdscript
const BOLT_MASK := 7
const ENEMY_BODY_MASK := 1 << 2

func plan_archer(encounter: AIEncounter3D, actor: Node3D, target: Node3D,
		navigator: NavigationAgent3D, during_cooldown: bool) -> Dictionary:
	return encounter.update_ranged_position(
		actor, target, 6.0, 16.0, BOLT_MASK, 1.35, 1.56,
		navigator.get_navigation_map(), navigator.navigation_layers,
		during_cooldown, ENEMY_BODY_MASK
	)
```

If a movement route stalls or arrival reveals a blocked muzzle outside the occlusion hold, call `reject_ranged_position(agent: Node3D, position: Vector3, seconds: float = 1.25, radius: float = 0.75)`. This releases the ranged claim, resets the search, and temporarily excludes that position for the actor. `release_ranged_position(agent: Node3D)` clears its entire ranged plan when it deliberately changes tactics. `release_agent()` also removes any melee and chokepoint state. For one-off geometric previews, `find_ranged_position(agent, target, min_range, max_range, collision_mask)` returns only `found` and `position`. The preview uses a 1.35 m ray offset at both ends and does not establish a reservation or prove a path to the destination.

The demo's actor also tries a short backoff inside bow range and checks the center and sides of the upper-body hitbox at shot time. It verifies the selected impact point again after wind-up, and `res://ai_demo/bolt.gd` sweeps the projectile through the same collision layers. These aiming, release, and hit policies belong in the actor and projectile code.

## Attack admission and chokepoints

Position ownership and attack admission serve different purposes. Check actual target validity, reach, and collision first. Use `can_attack(target: Node3D, category: StringName) -> bool` to expose admission to the behavior tree, then call `try_begin_attack(target: Node3D, category: StringName, cost: float) -> bool` exactly once when the attack commits. The commit call checks again and accepts a positive finite cost. Start wind-up only when it succeeds.

```gdscript
func try_commit_swing(encounter: AIEncounter3D, actor: Node3D, target: Node3D,
		inside_reach: bool, swing_clear: bool) -> bool:
	if not inside_reach or not swing_clear or not encounter.owns_melee_slot(actor, target):
		return false
	if not encounter.try_begin_attack(target, &"normal", 2.0):
		return false
	encounter.set_slot_locked(actor, true)
	return true

func finish_swing(encounter: AIEncounter3D, actor: Node3D) -> void:
	encounter.set_slot_locked(actor, false)
```

Each target and category has its own pressure meter. The attack that raises pressure **above** the threshold is admitted, then that category closes to further starts. A successful start refreshes the decay grace period. After grace, pressure falls by `decay × threshold` per second while closed and at one quarter of that rate while open. A closed meter reopens when it reaches `reset`. The built-in categories are `normal`, `running`, `charge`, `cleave`, `sweep`, `frenzy`, and `push`. Their default rule is `threshold = 2.5`, `grace = 1.0`, `decay = 1.0`, `reset = 0.25`, with `charge` using `decay = 0.4`.

Set `attack_rules` or call `set_attack_rules()` with a dictionary keyed by category. Each value is a dictionary containing any of `threshold`, `grace`, `decay`, and `reset`. The setter reinstates the built-in defaults and applies the supplied overrides or custom categories. Read `get_attack_rules()` for the current rules and `get_attack_pressure(target, category)` for the meter. `is_flanking(agent, target, forward)` compares the target's supplied forward direction with the direction toward the actor. The demo uses this for a warning after commitment. Slot selection and pressure work from target position and category, independently of camera direction.

`try_enter_chokepoint(agent: Node3D, key: StringName, capacity: int) -> bool` adds an actor to a queue for a caller-defined entrance. It admits the head of the queue when room is available and returns `true` for an already admitted actor. Use a stable key and consistent positive capacity at each door or link. The actor script defines where to wait and how to traverse. Call `leave_chokepoint(agent, key)` on exit or cancellation to release admission or remove a queued actor.

## Tuning and diagnostics

| Property | Default | Use |
| --- | --- | --- |
| `obstacle_mask` | `0` | Physics layers used by positioning obstacle probes. The demo uses `1` for world geometry. |
| `use_navigation_mesh` | `true` | Enable navmesh projection and route validation when the navigation context is available. |
| `navigation_snap_distance` | `1.25` m | Limit projection and path-origin snapping. |
| `acquisition_radius`, `acquisition_mask` | `0`, `0` | Optional distance and obstruction filters for newly selected targets. |
| `target_stickiness` | `5.0` | Score bonus for the current target. |
| `ranged_candidates_per_step`, `ranged_paths_per_step` | `48`, `8` | Shared ranged search work limits per encounter per physics step. Calls also cap candidate and path work per poll. |
| `ranged_preferred_spacing` | `1.5` m | Preferred separation between prospective ranged positions. `0` disables spacing. |
| `ranged_reposition_clear_shooters` | `false` | Permit voluntary spacing destinations for shooters with a clear current shot. The demo enables it. |
| `ranged_occlusion_grace` | `0.65` s | Maximum nearby goal hold for body-only obstruction when the transient mask is used. |

`get_ranged_search_stats()` returns `frame`, `candidates`, `path_queries`, `deferred`, and the prior frame's `previous_candidates`, `previous_path_queries`, and `previous_deferred`. `deferred` counts updates that postponed work. These counters measure bounded search activity. The live muzzle checks and projectile rays still run as gameplay requires.

For an actor that waits unexpectedly, inspect its target validity, plan `status`, and navigation map and layers first. For melee, check `has_slot`, live ownership, reach, and the attack category's pressure. For ranged, check the current muzzle and the destination separately. A wall can block all available firing angles while the target stays valid. The `src/ai_encounter_3d.cpp` define the full result and tuning contracts.
