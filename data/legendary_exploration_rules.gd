@tool
extends Resource
## Tuning for legendary effects triggered while exploring an expedition.

## Furthest distance from a destructible to a secret wall that Mason's Listener can reveal.
@export_range(1.0, 20.0, 0.25, "suffix:m") var mason_range := 7.0
## Duration of the glow on the discovered wall's crack.
@export_range(0.4, 4.0, 0.05, "suffix:s") var mason_clue_seconds := 1.40
