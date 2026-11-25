# Perception and search blocks

The identifiers below select compiled blocks in the GDExtension. Save the examples as node dictionaries within an `AIBehaviorTree`. Put a service on an ancestor of the branches that consume its facts. An active service samples only when the runner evaluates it. Bind external facts and Callables after assigning or resetting the runner. The perception lab catalog at `res://ai_demo/block_labs/perception/cases.tres` points to five complete saved examples. [Tree lifecycle and blackboard types](behavior-trees.md)

## Prioritize Stimuli

`prioritize_stimuli` is a service. The host supplies the current observations and their ages. The service scores each eligible observation using `strength_weight × strength + freshness_weight × (1 − age / max_age) − distance_weight × distance`. Ties go to the earliest input. Negative final scores are allowed. Use a distance weight that suits the units and scale of your observations.

| Parameter | Default | Contract |
| --- | --- | --- |
| `stimuli_key` | `stimuli` | Array of dictionaries. Each needs a finite Vector2 or Vector3 `position` and finite nonnegative `strength`, `age` in seconds, and `distance`. Additional fields such as `id` and `kind` travel with the result. |
| `selected_key` | `selected_stimulus` | Dictionary output. An empty dictionary means no eligible observation. |
| `score_key` | `stimulus_score` | Float output. Zero when no observation is selected. |
| `max_age` | `4.0` | Positive finite age limit. Rows older than this are ignored. |
| `strength_weight`, `freshness_weight`, `distance_weight` | `1.0`, `1.0`, `0.1` | Finite nonnegative weights. |

Invalid rows are ignored. The service clears the result and score when it exits. In a stealth FPS, feed sound records such as `{"id": &"door", "position": Vector3(4, 0, 2), "strength": 0.8, "age": 0.3, "distance": 4.5}`. A branch can use `selected_stimulus.position` as the destination for an investigation. Remove or mark a sound consumed in the host after an investigation.

```text
"services": [{"block": "prioritize_stimuli", "interval": 0.1,
"parameters": {"max_age": 3.0, "distance_weight": 0.06}}]
```

## Search Around a Point

`search_around_point` is a task. It snapshots the center and the driver at entry. It generates deterministic points on an expanding spiral within the radius. Vector3 points vary on the XZ plane before host projection. One candidate can be queried per runner evaluation.

| Parameter | Default | Contract |
| --- | --- | --- |
| `center_key` | `search_center` | Finite Vector2 or Vector3 center. |
| `driver_key` | `search_driver` | External Callable taking a command StringName and a context Dictionary. |
| `visited_key` | `search_visited` | Integer count of arrivals in this activation. Reset to zero on entry. |
| `radius` | `4.0` | Positive finite candidate radius. |
| `max_attempts` | `6` | Candidate budget from 1 to 64. Invalid, unreachable, and duplicate projections use an attempt. |
| `time_limit` | `8.0` | Positive finite runner-time limit in seconds, including movement. |

| Command | Context and host response |
| --- | --- |
| `project` | Receives `center`, `candidate`, and one-based `attempt`. Return a finite reachable point of the same vector type or null to skip it. The host may project to navigation and reject candidates whose paths exceed its own constraints. |
| `step` | Receives `goal`, `attempt`, and `delta`. Return `moving`, `arrived`, or `blocked` as StringName or String. An unknown response fails the task. |
| `stop` | Receives `goal`, `attempt`, and `reason`. Reasons are `arrived`, `blocked`, `timeout`, `failed`, or `aborted`. Release any steering or movement claims for that leg. The return value is ignored. |

The task succeeds when the candidate budget ends with at least one arrival. It fails if every candidate is skipped or blocked, the time limit expires, or the driver response is invalid. Every started leg receives one stop call if its driver is still valid. The latest visit count remains readable until the next activation or runner reset.

Use this task after an enemy loses sight and approaches its last known location. The movement driver can query a 3D navmesh, follow a tile grid, or use the host's ordinary movement controller.

```text
{"id": 5, "kind": "native_task", "block": "search_around_point",
"parameters": {"center_key": "last_seen_position", "radius": 6.0, "max_attempts": 8}}
```

## Rank and Retain Targets

`rank_and_retain_targets` is a service. The host decides candidate eligibility and supplies the scores. The incumbent remains selected while eligible until a challenger exceeds its score by **more** than the configured margin. When the incumbent disappears, the highest valid score wins immediately. Ties without an incumbent go to the first matching row.

| Parameter | Default | Contract |
| --- | --- | --- |
| `candidates_key` | `target_candidates` | Array of dictionaries containing `target` and finite numeric `score`. A target can be an integer ID, nonblank String or StringName, or a live Object. Omit ineligible targets. |
| `target_key` | `ranked_target` | Selected identity or null. Use TYPE_NIL for arbitrary identifiers or TYPE_OBJECT when using live objects only. |
| `score_key` | `ranked_target_score` | Float score of the chosen target. Zero when none is eligible. |
| `valid_key` | `has_ranked_target` | Boolean gate for the chosen identity. |
| `switch_margin` | `0.2` | Finite nonnegative score advantage required to replace an eligible incumbent. |

The outputs clear on service exit. For an RPG enemy, score the current party candidates from threat, damage, or distance. With an incumbent at `0.60` and a `0.20` margin, a challenger at `0.70` will wait and one at `0.95` will switch. Keep guard checks for whether a selected target can be hit.

```text
"services": [{"block": "rank_and_retain_targets", "interval": 0.1,
"parameters": {"switch_margin": 0.2}}]
```

## Share Contact

`share_contact` is a service that exchanges short-lived sighting records through a host Callable. Each participant uses the same monotonic clock. The transport decides which reporters a recipient can hear, such as through squad membership, radio range, or shout distance.

| Parameter | Default | Contract |
| --- | --- | --- |
| `observation_key` | `contact_observation` | Local dictionary with `target` ID, finite Vector2 or Vector3 `position`, and numeric `observed_at` on the shared clock. An empty dictionary means no local report. |
| `source_key` | `contact_source` | Host's unique integer ID or nonblank String/StringName. Target IDs use the same supported types. |
| `time_key` | `contact_time` | Current finite seconds on the shared clock. |
| `driver_key` | `contact_driver` | External Callable taking a command StringName and a context Dictionary. |
| `received_key` | `shared_contact` | Latest fresh incoming report, or an empty dictionary. |
| `ttl` | `3.0` | Positive finite lifetime in seconds. Records expire at the boundary. |

| Command | Context and host response |
| --- | --- |
| `publish` | Receives the record `{target, position, observed_at, source}`. Return boolean true to acknowledge it. Rejected reports can retry on later service evaluations while fresh. The service remembers the last accepted record during this activation. |
| `latest` | Receives `{source, now}`. Return the most recent relevant report in the same shape, or null. Keep the record available to readers for its lifetime. The service ignores reports from the local source and reports with future or expired timestamps. |

The received output is cleared when the transport has no fresh relevant report or when the service exits. Use it as an investigation lead. Set the timestamp when the host first sees a contact or takes a genuinely new observation, so repeatedly reading an old observation does not extend its lifetime.

```text
"services": [{"block": "share_contact", "interval": 0.2, "parameters": {"ttl": 2.2}}]
```

## Estimate Target Motion

`estimate_target_motion` is a service. It computes displacement over the elapsed sample interval and can smooth the result with an exponential time constant. The first sample primes the estimate. A second valid sample with positive delta produces a velocity. Zero-delta samples do not advance the baseline.

| Parameter | Default | Contract |
| --- | --- | --- |
| `position_key` | `target_position` | Finite Vector2 or Vector3 observation. Use a consistent coordinate space. |
| `identity_key` | Omitted | Optional key for the observed target's integer or nonblank text ID or live Object. Losing or replacing this identity clears the previous sample. |
| `observed_key` | Omitted | Optional boolean observation gate. A false or missing fact clears the sample. |
| `velocity_key` | `target_velocity` | Velocity output in the corresponding vector type, in position units per second. |
| `valid_key` | `has_target_velocity` | Boolean gate for reading the velocity. |
| `smoothing_seconds` | `0.15` | Finite nonnegative smoothing time constant. Zero uses the raw velocity. |
| `max_sample_gap` | `1.0` | Positive finite interval limit. A larger gap re-primes from the current sample. |

Losing observation, changing position dimension, or exiting the service clears validity. A previously sampled dimension is zeroed on invalidation. To test an FPS lead point, draw a marker at `target_position + target_velocity * 0.45` when the gate is true. Keep projectile travel, aim constraints, and collision checks in the host.

```text
"services": [{"block": "estimate_target_motion", "interval": 0.05,
"parameters": {"identity_key": "target_id", "observed_key": "target_visible",
"smoothing_seconds": 0.18}}]
```
