# First-person behavior block labs

Open the Godot 4.7 demo project and press **F5** to enter the training range. Click to capture the mouse, move with **WASD**, and walk through one of the five labeled portals. Walk through the amber **Return to hub** gate in any lab to choose another. Open an individual lab scene and press **F6** to enter it directly.

Choose **1–5** for the exercise. The objective tells you what will happen and what to do first. Press **E** to begin, then follow the live instructions. Depending on the exercise, **E** changes a scenario input or an aimed click places an observation or target in the world. Press **R** to release active work and reset the current exercise. **Esc** frees the mouse so you can use the exercise buttons. A failure can be the expected result, such as a blocked route or interrupted action.

| Scene under `res://ai_demo/block_labs/` | What to try |
| --- | --- |
| `movement_lab.tscn` | Lead an escort, lure a guard across the marked leash boundary, or interrupt a jump over the physical gap. [Movement contracts](blocks-movement.md) |
| `perception_lab.tscn` | Aim at the ground to introduce stimuli, move a target, and observe search, contact expiry, and motion estimates. [Perception contracts](blocks-perception.md) |
| `coordination_lab.tscn` | Block the preferred lane, contest a claim, or interrupt an objective approach and see the reservation release. [Coordination contracts](blocks-coordination.md) |
| `combat_lab.tscn` | Open a shutter to clear a shot, watch a cover peek, or interrupt a channel or cooldown move. [Combat contracts](blocks-combat.md) |
| `squad_lab.tscn` | Change weapon and ability readiness, place a threat for an ally to intercept, or block the preferred retreat route. [Squad contracts](blocks-squad.md) |

Each category has a `cases.tres` catalog pointing to five saved `AIBehaviorTree` resources in the same folder. Open a tree to inspect its nodes, declared facts, and tuning. The demo controls and sample hosts are compiled into the Windows extension. The addon archive contains the reusable runtime and these guides. The demo archive adds the editable scenes, catalogs, and trees.

## Adapt a case to a game

1. Pick the block ID and read its category guide. Copy the relevant task or service configuration into the game's own tree resource.
2. Declare inputs and outputs with the documented Variant types. Give inputs an authored default or mark them external. Supply live values and Callable adapters after assigning the tree and after each reset.
3. Route requests to the game's real systems. For example, a traversal callback can enter a movement state and report arrival from the motor. A position callback can delegate the exclusive claim to a shared squad service. Treat cancellation as a request to stop or release only the work started by that activation.
4. Validate and run the saved tree through the actual pawn. Check one normal completion and one failure or interruption. Turn on `debug_enabled` for one runner and inspect `get_debug_snapshot()` to see the `block` ID on native task and service events.

[Full block catalog](behavior-blocks.md#compiled-block-catalog) · [Native Task and Service syntax](behavior-trees.md#native-tasks-and-services) · [Actor integration playbook](implementation-playbook.md)
