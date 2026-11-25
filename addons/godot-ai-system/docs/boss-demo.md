# The Hollow Warden boss arena

Open `res://ai_demo/boss/boss_arena.tscn` in Godot 4.7 and press **F6** to run this scene. The normal and stress arenas remain available from their own scenes.

Use **WASD** and the mouse to move and aim, **LMB** to fire, **RMB** to block, and **Space** to jump. Hold **LMB** to keep firing at the configured interval. **Left Shift** dashes in the held movement direction or forward if no direction is held. You can dash in midair. You have two charges and regain one spent charge every two seconds. The dash makes you invulnerable while it moves you. The next charge fills on the HUD while later charges wait their turn.

Press **I** to toggle practice invulnerability, **R** to restart, and **Esc** to release the mouse. Click the game to recapture it.

## Fight flow

- **Combat** uses a behavior tree for a slam, a traveling fan of bolts, and a targeted meteor with a ground warning. When a slam is chosen outside melee reach and a combat leap is viable, the boss leaps toward a fixed landing point and winds up the slam after landing. The boss uses the same attacks after the ritual and during the final phase.
- **Ritual** starts once when the boss reaches 50% of maximum health. At 500 maximum HP, the threshold is 250 HP. It becomes immune and leaps to the central sigil. After it lands, the arena spawns ten offerings per portal, one at a time, rotating across the three authored gates. Offerings walk to the boss and ignore the player as a target and a movement obstacle. Kill them with player bolts. Each one that arrives disappears and restores 2 HP up to the boss's maximum. Immunity lasts until every scheduled offering has spawned and either been killed or delivered.
- **Final phase** begins at 15% of maximum health. At 500 maximum HP, the threshold is 75 HP. The arena immediately spawns two melee and two ranged enemies that target the player. Another group arrives every 15 seconds until the boss dies, including when enemies from an earlier wave are still alive.

The volley tracks the player's movement during its wind-up and locks shortly before firing. The meteor places its circle under the player when the boss finishes casting. The circle stays in place until impact, so a late change of direction or dash can get you clear.

A hit crossing an untriggered threshold ends at that threshold. This gives each phase a chance to start even with high projectile damage. The ritual stays spent after the boss heals, so the player can make progress through both thresholds.

## Try the reusable ritual blocks

Run the boss arena and press **I** for practice invulnerability. Shoot the Warden to 50% health. The compiled `AIThresholdLatch` fires during damage resolution, which lets the Warden clamp the hit and become immune immediately. On landing, the arena's `RitualBrain` starts the saved ritual tree. Its native `request_action_and_wait` task stays active until the final offering has spawned. The native `wait_for_fact` task then stays active until every offering has died or reached the boss. If you kill or intercept offerings while others are still queued, the ritual continues. Press **R** during either stage to cancel the ritual and rearm the threshold.

For script diagnostics, inspect the `RitualBrain` runner's active node IDs or enable its debug trace. In `res://ai_demo/boss/boss_ritual_tree.tres`, node **2** requests the spawn batch and node **3** waits for `ritual_resolved`. See [Behavior blocks](behavior-blocks.md) for the same wiring in another project.

## Attack selection

The behavior tree rolls once among eligible attacks, using their scores as relative chances. Cooldowns and each attack's range and visibility rules determine eligibility. Distance shifts the odds, with an added cost for a slam that needs a leap. The last attempted attack gets a repeat penalty, and each attack's cooldown has a tunable amount of variation. An attack commits to its wind-up and recovery once selected, so the player can read the warning and react.

The weighted utility selector follows the approach Kevin Dill and Dave Mark presented at GDC and Bill Merrill described for behavior trees. The repeat penalty applies the idea of filtering randomness with recent outcomes to this encounter. [Improving AI Decision Modeling Through Utility Theory](https://www.gdcvault.com/play/1012410/Improving-AI-Decision-Modeling-Through) · [Building Utility Decisions into Your Existing Behavior Tree](https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter10_Building_Utility_Decisions_into_Your_Existing_Behavior_Tree.pdf) · [Advanced Randomness Techniques for Game AI](https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter03_Advanced_Randomness_Techniques_for_Game_AI.pdf)

## Tune the encounter

Edit `res://ai_demo/boss/default_encounter.tres` or assign another **Tuning** resource to the arena root. Fields have Inspector tooltips and are available directly to GDScript.

| Group | Settings |
| --- | --- |
| Boss | Name, maximum health, ritual and final thresholds as percentages, movement speed, and ritual leap height and duration |
| Attack Selection | Relative attack weights, penalty for repeating the last attack, and cooldown variation |
| Melee Slam | Damage, range, wind-up, recovery, cooldown, and the combat leap's range, timing, height, and weight multiplier |
| Ranged Volley | Damage per bolt, range, timing, bolt count, spread, travel speed, aim-lock timing, and motion lead |
| Ranged Meteor | Damage, range, timing, impact radius, and warning duration |
| Portal Ritual | Offerings per portal, initial delay, spacing in time, health, walking speed, delivery distance, and healing |
| Final Reinforcements | Interval, melee and ranged counts, health, movement speed, attack damage, arrow speed, and lateral spawn spacing |
| Player Projectile | Damage, travel speed, and firing interval |
| Player Movement | Jump speed, dash speed and duration, maximum charges, time to recover each charge, and dash field-of-view boost |

Keep **Final Health Percent** below **Ritual Health Percent** when tuning thresholds. The **Player Projectile Damage** field applies to the boss, offerings, and reinforcements.

The saved `Portals` node contains three portal markers. The arena counts its marker children at startup. When moving markers or placing a new one, keep its spawn area clear and connected to the ritual center and player by the saved navigation region. `RitualCenter`, `BossSpawn`, and `PlayerSpawn` are separately authored markers.

## Script ownership

- `res://ai_demo/boss/boss_arena.gd` handles the ritual tree's summon request and owns portal scheduling, offering accounting, the player bolt callback, the existing melee/ranged reinforcement scenes, and encounter reset.
- `res://ai_demo/boss/boss.gd` owns the boss's health, phase gates, action execution, and attack signals. `res://ai_demo/boss/boss_tree.tres` defines normal and final combat selection.
- `res://ai_demo/boss/ritual_minion.gd` follows the boss through navigation, receives damage, and reports exactly one outcome to the arena. Its movement does not use the reinforcement behavior trees.
- `res://ai_demo/player.gd` handles first-person controls. The boss arena opts into jump and dash using its tuning resource.
- `res://ai_demo/boss/boss_hud.tscn` shows boss and player health, boss immunity, the outstanding offering count, final wave timing, and dash charges.

See the [behavior tree reference](behavior-trees.md) for runtime authoring and the [encounter guide](encounter-and-navigation.md) for the shared melee and ranged actors.
