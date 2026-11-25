# Hearth Below

Hearth Below is a first-person dark fantasy dungeon crawler. Prepare in Cinderhold Refuge, then descend into seeded expeditions with connected floors, traps, secrets, loot, and enemy encounters. Create a character to play the campaign or open the Training Ground to try weapons, cards, and enemies.

## Run the project

1. Install the standard **Godot 4.7 for Windows x86-64**. This checkout includes the Windows native addons for inventory, enemy AI, and dismemberment.
2. Import [project.godot](project.godot) in the Godot project manager. Let the first asset import finish.
3. Press **F6** with [main.tscn](main.tscn) open, or **F5** to run the project's main scene. Use Forward+ for the intended rendering.

The checked-in [Blender sources](assets/source) are for mesh and animation editing. The game imports its runtime models from the project, so a normal play session needs Godot and the bundled addon binaries.

## Start playing

Create or load a character from the title screen. Visit the altar in Cinderhold Refuge to start an expedition. Press **I** for inventory, **Q** for cards, **Tab** for the dungeon map, and **Esc** for the pause menu. In the Training Ground, **F1** opens enemy, weapon, and card options. [Input owner](main.gd)

## Contribute or use Codex

Start with [AGENTS.md](AGENTS.md). It routes to detailed guides for gameplay, scenes, world assets, tuning, save and expedition state, and verification. The main layout files are under [ui](ui), the editor Workbench is under [addons/hearth_workbench](addons/hearth_workbench), and test scripts are under [tests](tests).

Third-party notices live with their addons. [AI system notices](addons/godot-ai-system/LICENSE.md) · [Dismemberment notices](addons/godot-dismemberment/THIRD_PARTY_NOTICES.md)
