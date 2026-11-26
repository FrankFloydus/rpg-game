# Hearth Below agent guide

## Start here

Hearth Below is a first-person dark fantasy action RPG built with Godot 4.7 and GDScript. Players manage their characters in Cinderhold Refuge and test combat in the Training Ground. Both locations use the same player, grid inventory, and equipment systems.

The project root contains [project.godot](project.godot). [main.tscn](main.tscn) composes the game and [main.gd](main.gd) coordinates session transitions. Work in this tree and identify the affected owner before editing. Read the nearest AGENTS.md for each directory you touch and open the relevant reference guide below.

## Important: keep documentation current in every change

**Every addition, change, move, or deletion requires a documentation update in the same task and the same change set.** This applies to code, scenes, resources, assets, tests, settings, tools, and workflows. The task is incomplete until its affected documentation is current.

- Update the guide that owns the changed contract. Describe new behavior, the source of truth, and how to verify it. Update user-facing instructions when a workflow, control, or setting changes.
- Remove obsolete statements and links for deleted features. Replace moved paths in guides, launch instructions, and any other documented callers.
- For a narrow internal change, update the smallest relevant section with the durable effect or invariant. Keep unrelated guides stable. If a gap has no owner, add a short section to the closest guide and link it from the appropriate scope.
- Review code and documentation together before handoff. Use repository-relative links. Keep verification claims tied to checks that actually ran.

## Find the owner

| Task | Read before editing |
| --- | --- |
| Running, testing, repository conventions, release checks, or cross-system changes | [Engineering and verification](docs/agents/engineering-and-verification.md) |
| Player movement, weapon motion, melee, casting, enemy AI, animation, hit feedback | [Combat and player](docs/agents/combat-and-player.md) |
| Inventory, merchant or stash screens, HUD, title, cards, Training Ground UI | [UI and inventory](docs/agents/ui-and-inventory.md) |
| Workbench, balancing, loot data, definitions, adjustable properties | [Workbench and data](docs/agents/workbench-and-data.md) |
| Authored locations and routes, world props, lighting, models, textures, VFX or audio assets | [World and assets](docs/agents/world-and-assets.md) |
| Character slots, saves, character progression, deck and lifetime records | [Campaign and saves](docs/agents/campaign-and-saves.md) |

[Model catalogue](MODEL_CATALOGUE.md) tracks authored models and provenance. Use current code, resources, and the task brief to establish today's behavior.

## Run and check

Use **Godot 4.7, Windows x86-64, standard single-precision** for the bundled native addons. Launch [main.tscn](main.tscn) from the project. Forward+ is the baseline for graphics and visual acceptance. See [README](README.md) for setup.

From the project root, using Godot on PATH or the equivalent console executable:

~~~powershell
godot --headless --path . --import
godot --headless --path . --quit-after 4
godot --headless --path . --script res://tests/inventory_revision.gd
godot --path . --rendering-method forward_plus --script res://tests/inventory_appearance_render.gd
~~~

Import when assets or dependencies require it. Select the test matching the change. Open the normal user-facing path for changes involving visuals, input, authoring, scene wiring, or persistence. Check the Godot log for script errors as well as the exit code.

## Working contracts

- Keep authored UI layouts in editable PackedScenes. Bind runtime data and signals in scripts. Use the shared theme for general chrome and retain semantic feedback for gameplay states.
- Store tunable gameplay values in the existing owner resources and Workbench routes. Follow common inventory and save transactions. Keep generated IDs, authored record IDs, scene interfaces, and saved-state compatibility stable.
- Resolve targeting and collision in their owning coordinate space. Compare behavior under actual parent transforms, entry points, and lifecycle transitions where they matter.
- Reuse the existing project services and schemas. Preserve unrelated work and verify compatibility before changing core scene or addon interfaces.
- Publish project sources, editable assets, import settings, and required native dependencies with their notices. Keep local saves, caches, temporary creative work, external references, and credentials out of version control.

## Code Review Rules

- Flag a new control or property whose value changes in the editor but fails to save, reload, or affect gameplay. A preview alone covers only one step.
- Flag a state mutation that can partially succeed, strand a cursor item, double-pay a reward, or lose older saved data.
- Flag a world-space direction assigned to local-facing state where a rotated parent can redirect animation or traces.
- Flag visual changes justified only by a headless or Compatibility run when the affected experience uses Forward+.
- Flag behavior or paths that changed without updating their owning docs.

## Handoff

Summarize the outcome, important decisions, and verified checks. Give concrete limits on validation. Check local links and the final change set before reporting completion.
