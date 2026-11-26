@tool
extends Resource
## Durations for a fallen enemy and the Training Ground's debug trace.

## How long debug melee collision boxes stay visible in the Training Ground.
@export_range(0.1, 10.0, 0.1, "or_greater", "suffix:s") var player_trace_seconds := 2.0
## Time after death during which a ragdoll remains and can be raised.
@export_range(120.0, 600.0, 1.0, "or_greater", "suffix:s") var corpse_lifetime_seconds := 120.0
