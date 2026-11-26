# Hearth Below

Hearth Below is a first-person dark fantasy action RPG. The playable locations are Cinderhold Refuge, where characters manage their equipment and deck, and the Training Ground, where you can test weapons, spells, cards, and enemies.

## Run the project

1. Install the standard **Godot 4.7 for Windows x86-64**. This checkout includes the Windows native addons for inventory, enemy AI, and dismemberment.
2. Import [project.godot](project.godot) in the Godot project manager. Let the first asset import finish.
3. Press **F6** with [main.tscn](main.tscn) open, or **F5** to run the project's main scene. Use Forward+ for the intended rendering.

The checked-in [Blender sources](assets/source) are for mesh and animation editing. The game imports its runtime models from the project, so a normal play session needs Godot and the bundled addon binaries.

## Start playing

Create or load a character from the title screen. Press **I** for inventory, **Q** for the deck or practice card hand, and **Esc** for the pause menu. In the Training Ground, **F1** opens enemy, weapon, and card options. Aim at the **Life Well** on the left or the **Mana Well** on the right near the entrance and press **E** to refill that resource. [Input owner](main.gd)

In **F1 → Weaponry**, enable **Show Player Weapon Traces** and use **Contact Preset** to test wall impacts. **Training** stops on valid solid hits at normal reach. **Carry Through** lets a swing continue after a wall impact. **Refuge** uses a shorter, narrower sweep with solid stops. Weapon reach and cleave are editable per family in [Workbench → Weapons & Player → Melee contact](docs/agents/workbench-and-data.md#forms-and-inspection).

In Cinderhold, aim at a station and press **E** to use the provisioner, blacksmith, stash, or Training Ground portal. You can also enter the Training Ground directly from the title screen. A character that leaves practice returns to Cinderhold with their campaign equipment and deck restored.

In your pack, a yellow intersection shows where a held item can replace one other item. Click or drop there to place the held item and take the other one onto the cursor.

## Contribute or use Codex

Start with [AGENTS.md](AGENTS.md). It routes to detailed guides for gameplay, scenes, world assets, tuning, character saves, and verification. The main layout files are under [ui](ui), the editor Workbench is under [addons/hearth_workbench](addons/hearth_workbench), and test scripts are under [tests](tests).

Third-party notices live with their addons. [AI system notices](addons/godot-ai-system/LICENSE.md) · [Dismemberment notices](addons/godot-dismemberment/THIRD_PARTY_NOTICES.md)
