# godot-ai-system

A Godot 4.7 GDExtension for behavior trees, typed blackboards, utility decisions, encounter navigation, and horde pacing. Author trees as data and connect them to the host game's systems. The extension includes 31 compiled behavior blocks for common RPG and FPS decisions.

## Install

1. Extract `godot-ai-system-addon-windows-x86_64.zip` into the Godot project root. The archive writes under `addons/godot-ai-system/`.
2. Open the project in the matching Godot build. Godot registers the native classes from `godot-ai-system.gdextension` when it imports the project. For a new headless checkout, run `godot --headless --editor --path <project> --quit-after 180` first.
3. Create an `AIBehaviorTree` in GDScript or save it as a `.tres`. Assign it to one `AIBehaviorRunner` per actor, publish the inputs, and tick it from the host's update loop.

On Windows, an immediate headless `--import` shutdown can fail on a fresh extension scan. The delayed editor command above is the verified first-import path.

The supplied ZIPs contain Windows x86-64 debug and release libraries. For another platform, build for that target and verify the library path and tags in the manifest.

### Upgrading from an editor-enabled copy

Remove the old addon `plugin.cfg`, `editor/` files, and `runtime/behavior_debug_bridge.gd` with its `.uid`. Remove `res://addons/godot-ai-system/plugin.cfg` from `[editor_plugins]` and the old `AIBehaviorDebugBridge` entry from `[autoload]` if they are present in the host's `project.godot`. Preserve host-authored assets and unrelated settings. Existing behavior tree resources still load with their IDs, links, conditions, and services. Restart the host editor to pick up the replacement extension.

## Implement an NPC

Start with the [implementation playbook](docs/implementation-playbook.md). It covers interpreting a short request, locating the host's real APIs, choosing the smallest tree, wiring the actor, and verifying actual gameplay. For Codex tasks in a consuming game, add this line to the game's existing root `AGENTS.md` so agents working outside the addon can find the guide.

> For Godot AI behavior tasks, consult `addons/godot-ai-system/docs/implementation-playbook.md` and the API guide for the system being changed.

| Read | For |
| --- | --- |
| [Architecture](docs/architecture.md) | Runtime responsibilities, data ownership, and source map. |
| [Behavior trees](docs/behavior-trees.md) | Node schema, typed blackboard, callbacks, script tasks, attached decorators and services, utility, and history. |
| [Behavior blocks](docs/behavior-blocks.md) | Compiled task and service catalog, migration steps, and integration examples. |
| [Encounter and navigation](docs/encounter-and-navigation.md) | Target registration, melee slots, ranged lanes, movement recovery, and attack admission. |
| [Horde director](docs/horde-director.md) | Pressure, wave profiles, candidate gates, and population accounting. |
| [Diagnostics and verification](docs/diagnostics-and-verification.md) | Snapshots, headless checks, gameplay fixtures, and profiling. |
| [Arena demo](docs/arena-demo.md) | Saved trees, host scripts, arena controls, and the stress scene. |

## Run the demo

In the checkout, open `project/project.godot`. In the demo ZIP, open the included `project.godot`. Press **F5** to enter the first-person lab hub. Open `res://ai_demo/arena.tscn` or `res://ai_demo/stress_arena.tscn` and use **F6** for the regular or 100-enemy arena. See the [arena guide](docs/arena-demo.md) for the controls and test setup.

Open `res://ai_demo/boss/boss_arena.tscn` and press **F6** for the Warden encounter. Its designer settings and phase behavior are documented in the [boss demo guide](docs/boss-demo.md).

Open `res://ai_demo/behavior_blocks_arena.tscn` and press **F6** to exercise the movement, memory, and range blocks with the demo pawns.

Walk through a labeled portal to enter any of the five first-person labs. In a lab, choose **1–5** and follow the on-screen objective. Walk through the amber portal to return to the hub. [Lab controls and scene map](docs/native-block-labs.md)

## Build and package from source

Use the pinned `godot-cpp` submodule, Python, SCons, and a supported C++ compiler. The Windows build uses MSVC. Run these commands at the checkout root with Godot 4.7 available on PATH.

```powershell
git submodule update --init --recursive
scons platform=windows arch=x86_64 target=template_debug
scons platform=windows arch=x86_64 target=template_release
godot --headless --editor --path project --quit-after 180
godot --headless --path project --script "$PWD/tools/smoke_runtime.gd"
python tools/package.py
```

SCons installs the libraries under `project/addons/godot-ai-system/bin/windows/`. The packager writes both ZIPs to `../dist/`. For a native change, test the applicable game path in addition to the smoke test.
