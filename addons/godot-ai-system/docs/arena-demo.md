# Arena demo

The arena is a Godot 4.7 example project. Its actors, combat rules, waves, HUD, and scene wiring live in GDScript and saved assets under `res://ai_demo/`. The scripts call the addon’s native behavior runner, encounter coordinator, and optional pacing director. Godot supplies navigation, avoidance, animation playback, and physics. The addon-only archive is the installable framework for another game. [Repository setup](../README.md) · `res://ai_demo/arena.gd`

## Run the scenes

From a checkout, open `project/project.godot` after building the addon. From a distribution, extract `godot-ai-system-windows-x86_64.zip` and open the included `project.godot`. Open `res://ai_demo/arena.tscn` and press **F6** for the normal arena. **F5** opens the lab hub. Open `res://ai_demo/stress_arena.tscn` and press **F6** for the 100-enemy preset. The normal arena starts in first person. The stress arena starts overhead with the ally enabled. `project/project.godot` · `res://ai_demo/arena.tscn` · `res://ai_demo/stress_arena.tscn`

Open `res://ai_demo/behavior_blocks_arena.tscn` and press **F6** for the pawn tests. The saved scene uses the existing enemy pawn and shows the current range intent, sight and memory, and movement recovery. See [Test the movement blocks with the pawn](behavior-blocks.md#test-the-movement-blocks-with-the-pawn).

| Control | Effect |
| --- | --- |
| WASD and mouse | Move and look in first person |
| Left click | Capture the mouse or fire a cyan training bolt |
| Right mouse button | Hold block while stamina remains |
| 1 / 2 / 3 | Restart with the small melee, mixed, or ranged preset |
| 4 | Toggle the ally as a second target |
| P | Toggle optional paced spawns |
| I | Toggle invulnerability. The health bar turns cyan. |
| Tab | Switch between the first-person and overhead cameras |
| V | Show or hide destination markers |
| R | Reset the current preset while retaining the pacing toggle |
| Escape | Release mouse capture |

The player’s shot costs one enemy hit point and stops at the first enemy or world surface it strikes. Invulnerability persists across scenario resets. With the ally disabled, player death leaves the enemies with no active target. With the ally enabled, surviving enemies can switch to it. The HUD shows which condition applies. `res://ai_demo/player.gd` · `res://ai_demo/player_bolt.tscn` · `res://ai_demo/arena.gd`

## Scene roles and wave density

| Scene or resource | Responsibility |
| --- | --- |
| `res://ai_demo/arena.tscn` | Owns the saved navigation region and world colliders, three gate markers, the player and ally, the encounter and director nodes, the overhead camera, and the HUD. |
| `res://ai_demo/enemy.tscn` | Shared character body for all enemy roles. Includes the navigation agent, native behavior runner, swing clips, health bar, ground indicator, and destination marker. |
| `res://ai_demo/player.tscn` and `res://ai_demo/ally.tscn` | Register as encounter targets through the arena. The player is a first-person character body. The ally is a fixed training target that counts received hits. |
| `res://ai_demo/bolt.tscn` and `res://ai_demo/player_bolt.tscn` | Use the same swept-ray projectile script with different collision masks and presentation. |
| `res://ai_demo/stress_arena.tscn` | Inherits the arena and overrides the initial preset and optional visual scenes. The actor scripts, capsule colliders, navigation, and combat rules are shared. |

The demo uses physics mask values **1** for world geometry, **2** for player and ally bodies, **4** for enemy hit detection, and **8** as an extra archer body bit. Player bolts use mask **5**, and enemy bolts use mask **7**. Enemy capsules have a 0.39 m radius. Their navigation agents use a separate 0.41 m avoidance radius. `res://ai_demo/enemy.tscn` · `res://ai_demo/enemy.gd` · `res://ai_demo/bolt.gd`

| Manual preset | Ordinary melee, ring 0 | Larger melee, ring 1 | Largest melee, ring 2 | Archers | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| **1** Small melee | 11 | 1 | 0 | 0 | 12 |
| **2** Mixed in normal arena | 40 | 7 | 3 | 6 | 56 |
| **3** Ranged lanes | 0 | 0 | 0 | 6 | 6 |
| **2** Mixed in stress arena | 71 | 12 | 6 | 11 | 100 |

The arena starts releasing enemies after 0.25 seconds and adds up to four per 0.25-second spawn step. The ranged-only preset alternates the west and east gates. The mixed preset rotates archer requests separately across west, east, and rear. Each spawn uses a small, seeded horizontal offset around its selected gate. Ring 1 and ring 2 increase visual scale and health to three and four hit points respectively. Ordinary melee and archers start with two. `res://ai_demo/arena.gd` · `res://ai_demo/enemy.gd`

The stress proxies use **2,880 player**, **2,936 archer**, **2,916 melee**, and **2,904 ally** triangles per instance. Each role shares one mesh, material, and distinct 2048 × 2048 S3TC albedo with mipmaps. All three melee variants share the melee asset. The proxies are static meshes attached to the existing visuals. Ground indicators, health bars, and spawned bolts still show actor activity in the stress view. `res://ai_demo/stress/` · `res://ai_demo/stress_arena.tscn`

With **P** enabled, the arena submits living enemies, queued requests, threat, and gate candidates to `AIHordeDirector` every 0.25 seconds. It calculates visibility by world ray and reachability by navigation path. The saved director has a 72-enemy admission cap for paced requests. The manual 100-enemy wave uses the arena’s own spawn queue. The director can request a six-melee horde, a pair of archers, or a single large melee roamer, each with an authored interval and population limits. `res://ai_demo/arena.gd` · `res://ai_demo/arena.tscn`

## Behavior trees and lifecycle

Both saved trees start with a Root and a reactive priority Selector. Stagger takes priority, an active target enables a Utility branch, and the idle action handles the absence of a target. The Utility branch scores eligible actions using the saved weights and distance curves. Attack readiness is an entry guard so an admitted attack can finish its wind-up and recovery. `res://ai_demo/melee_tree.tres` · `res://ai_demo/ranged_tree.tres`

| Saved tree | Combat and movement | Blackboard facts the actor supplies |
| --- | --- | --- |
| **Melee Horde** | Standing and running swings, slot approach, queue movement, and last seen investigation | `target_valid`, `staggered`, `distance`, `has_slot`, `melee_has_goal`, `queued`, `melee_ready`, `lunge_ready` |
| **Standoff Archer** | Aim and release, close defense, firing lane movement, side approach, and last seen investigation | `target_valid`, `staggered`, `distance`, `shot_ready`, `ranged_goal`, `pursuit_goal`, `melee_fallback`, `hold_position` |

1. The arena registers the player as a target and enables the ally according to the scene setting. It configures each enemy’s role, ring, encounter reference, projectile parent, and shared volley helper before adding the enemy to the tree. The actor assigns the saved tree to its `AIBehaviorRunner` in `_ready()`.
2. The actor polls its target and movement assignment on a staggered schedule. It gives the encounter the same navigation map and layers used by its agent. Every physics tick the actor evaluates attack and movement guards, publishes changed Boolean facts and the current distance, and calls `brain.tick(delta, _perform_action)`. The handler receives `enter`, `tick`, and `exit` phases and returns a behavior status.
3. The movement leaves run **Move to Goal with Recovery**. The actor returns the remaining route distance as a number while moving and applies the navigation agent’s avoidance velocity to the body. A crowded unclaimed melee queue can pause briefly while retaining its place. A failed route or stalled claimed move asks the actor to recover through the encounter’s slot or lane rules.
4. When an attack starts, the actor keeps its committed target. A melee attacker locks its claim during the attack and unlocks on exit. When an enemy changes target, dies, or leaves the tree, its reservations are released. Scenario reset releases enemies and projectiles, resets the volley and director, and restores player health, stamina, collision, and target registration state.

Both trees run **Remember Last Seen Position** and **Maintain Range Band** at the root. The actor supplies sampled sight and its role's range tuning. If sight is lost and the actor lacks a usable tactical route, it can investigate the recorded point while the memory is valid. The archer uses the range intent to back away from a close target. The melee actor can still move to a side or rear slot while close to the player. [Behavior blocks](behavior-blocks.md)

For melee, the encounter distinguishes the desired strike position from the immediate movement waypoint. A claimed position can require a side approach. An unclaimed attacker can wait farther out. Larger units can gain space through timed handovers between rings. The actor checks distance, world visibility, cooldown, and the target’s category-specific attack pressure. The saved standing and running clips call `_on_melee_impact()` at their authored hit frame, which checks distance and sight again. Player facing is used for the post-commit rear-attack warning. Position and navigation drive the approach. `res://ai_demo/enemy.gd` · `res://ai_demo/enemy.tscn` · `src/ai_encounter_3d.cpp`

For archers, the default bow range is **6–16 m**. The encounter searches for reachable firing positions and can retain a previously clear goal through brief body occlusion. The actor can back out of close range, follow a lateral approach, or try another clear target. At shot start and release it tests the center and sides of the upper body and requires the selected ray to hit the intended target first. At the release frame, a transient enemy crossing can hold the completed draw for up to **0.22 seconds**, with rechecks every **0.05 seconds** until the deadline. Three to five eligible archers within the volley’s 9 m grouping radius can schedule releases at 0.16-second offsets. The projectile sweeps each physics step against world geometry and bodies that may enter its flight path. `res://ai_demo/enemy.gd` · `res://ai_demo/archer_volley.gd` · `res://ai_demo/bolt.gd`

## Manual checks

1. Open the normal arena, press **I**, **3**, and **Tab**, then watch from above. The six archers should seek usable firing angles. Toggle **V** to compare their feet with their movement goals. Move beside a cover block in first person and return overhead to observe side routes. Keep an open route around the block when checking for repositioning.
2. Press **2** with invulnerability enabled. Wait for the mixed wave to reach the player, walk away from the pack, and stop. Watch waiting melee units, moving claim holders, and attack windups separately. To inspect an individual enemy, use the [script watch example](diagnostics-and-verification.md) to capture its running action, target, goal, and requested, safe, and actual velocities.
3. Turn invulnerability off and let the player go down with the ally disabled. Check the inactive-target HUD message. Press **4** and observe retargeting to the ally. Press **R** to restore the player and wave.
4. Open the stress scene with **F6**. Leave **P** off for the fixed 100-enemy run and use **I** to keep the hero alive. Run once with the default ally and once with **4** to isolate the player target. Compare rendered frame timings using the same camera, resolution, and renderer. `res://ai_demo/arena.gd` · `res://ai_demo/enemy.gd`

## Reproduce a 100-enemy run from PowerShell

Set the project path to the folder that contains `project.godot`. For a checkout this is `project/`. For the demo archive this is the extraction directory. Use the console executable from Godot 4.7.

```powershell
$godot = 'C:\path\to\Godot_v4.7-stable_win64_console.exe'
$arenaProject = (Resolve-Path .\project).Path  # Replace .\project with . in an extracted demo.
& $godot --headless --editor --path $arenaProject --quit-after 180
& $godot --path $arenaProject res://ai_demo/stress_arena.tscn
```

For a fixed-condition comparison, save the following as `godot-ai-arena-fixture.gd` in your temporary directory. It uses the saved stress scene with the ally disabled and the hero invulnerable. The moving case drives the hero’s position directly so the target follows the same route across builds. The impact callback records the bolt’s actual collision and forwards the original damage handling. This callback is part of the demo fixture.

```gdscript
extends SceneTree

var arena: Node3D
var fixture := "stationary"
var ticks := 0
var launches := 0
var hero_contacts := 0
var enemy_interceptions := 0
var world_interceptions := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		fixture = args[0]
	if fixture not in ["stationary", "moving", "wall", "cover"]:
		push_error("Expected stationary, moving, wall, or cover.")
		quit(2)
		return
	process_frame.connect(_start, CONNECT_ONE_SHOT)


func _start() -> void:
	seed(173)
	var scene := load("res://ai_demo/stress_arena.tscn") as PackedScene
	arena = scene.instantiate()
	arena.initial_ally = false
	root.add_child(arena)
	arena.player.invulnerable = true
	arena.player.set_physics_process(false)
	if fixture == "wall":
		arena.player.position = Vector3(0, 0.04, 16.6)
	elif fixture == "cover":
		arena.player.position = Vector3(7, 0.04, -1.75)
	if fixture == "wall" or fixture == "cover":
		arena.player.rotation.y = PI * 0.5
	arena.projectiles.child_entered_tree.connect(_record_launch)
	physics_frame.connect(_sample)


func _record_launch(bolt: Node) -> void:
	launches += 1
	_wrap_impact.call_deferred(bolt)


func _wrap_impact(bolt: Node) -> void:
	if is_instance_valid(bolt):
		var prior: Callable = bolt._hit_handler
		bolt._hit_handler = _record_impact.bind(bolt, prior)


func _record_impact(body: Object, bolt: Node, prior: Callable) -> void:
	if body == arena.player:
		hero_contacts += 1
	elif body is CollisionObject3D:
		if (body.collision_layer & 4) != 0:
			enemy_interceptions += 1
		elif (body.collision_layer & 1) != 0:
			world_interceptions += 1
	if prior.is_valid():
		prior.call(body)
	elif body.has_method("receive_enemy_hit"):
		body.receive_enemy_hit(bolt.damage, bolt._origin)


func _sample() -> void:
	ticks += 1
	if fixture == "moving":
		var seconds := ticks / 60.0
		var east := smoothstep(17.0, 19.0, seconds) * 3.0
		var south := smoothstep(10.0, 12.0, seconds) * 4.0
		arena.player.position = Vector3(east, 0.04, 6.0 + south)
	if ticks != 1800:
		return
	var archers := 0
	for enemy in arena.units.get_children():
		archers += int(enemy.ranged)
	var total: int = arena.units.get_child_count()
	print("%s | enemies=%d archers=%d launches=%d hero=%d enemy=%d world=%d" % [
		fixture, total, archers, launches, hero_contacts, enemy_interceptions, world_interceptions
	])
	quit(0 if total == 100 and archers == 11 else 1)
```

```powershell
$arenaFixture = Join-Path $env:TEMP 'godot-ai-arena-fixture.gd'
foreach ($case in 'stationary', 'moving', 'wall', 'cover') {
    & $godot --headless --path $arenaProject --script $arenaFixture --fixed-fps 60 --quit-after 1850 -- $case
    if ($LASTEXITCODE -ne 0) { throw "Arena fixture failed for $case" }
}
```

Expect 100 enemies, including 11 archers, in each run. A launch can still be in flight or miss at the 30-second cutoff. Run the cover case several times and report the range because physics and navigation timing can vary despite the seed. The headless fixture measures behavior and contacts. Use the rendered stress scene for frame-rate measurements.

