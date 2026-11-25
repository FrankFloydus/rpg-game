# Engineering and verification

Use this guide when a task crosses owners or needs a repeatable test, a native visual check, or a clean-checkout validation. Start with the [root agent guide](../../AGENTS.md) and the nearest scoped AGENTS.md.

## Runtime and toolchain

- [project.godot](../../project.godot) identifies Godot 4.7, Forward+, 2D HDR, canvas stretch, and the enabled Workbench plugin. It declares the project main scene and the Services autoload.
- The checked-in GDExtensions provide Windows x86-64 single-precision debug and release DLLs. Other library entries in a manifest do not prove that this checkout ships those binaries. Qualify an additional platform by confirming all required libraries and running it. [AI manifest](../../addons/godot-ai-system/godot-ai-system.gdextension) · [Inventory manifest](../../addons/godot-spatial-inventory/godot-spatial-inventory.gdextension) · [Dismemberment manifest](../../addons/godot-dismemberment/godot-dismemberment.gdextension)
- Use the Windows console executable when scripting Godot so diagnostics and exit status reach the shell. The commands below use the name godot as a shortcut for your installed 4.7 executable.
- Editable Blender sources are separated from runtime imports by the [source ignore marker](../../assets/source/.gdignore). Follow the [world and asset guide](world-and-assets.md) before changing a mesh, scene import, or material.
- Keep .uid and .import sidecars alongside authored sources where Godot creates them. Keep the generated .godot cache and extension hot-reload copies outside the staged source tree. [Ignore rules](../../.gitignore)

## Composition and ownership

| Surface | Entry point | Regression boundary |
| --- | --- | --- |
| Session, scene lifetime, modal input and engine time scale | [Game scene](../../main.tscn) and [controller](../../main.gd) | The title, hub, expedition and Training Ground must enter and leave through their production paths. |
| Global service lookup | [Services autoload](../../systems/game_services.gd) | A service is registered by the composing scene and released with its scope. |
| Data tuning and editor integration | [Workbench](../../addons/hearth_workbench) and [definitions](../../data) | Separate draft editing, persistent save, and the live consumer. |
| Character and expedition state | [Systems](../../systems) and [expedition guide](expeditions-and-saves.md) | Save/reopen restores actual behavior and ownership. |
| Runtime presentation | [UI guide](ui-and-inventory.md) and [authored scenes](../../ui) | Opening the scene in the editor and opening it in gameplay both show the expected layout. |
| First-person input and combat | [Player](../../player) and [combat guide](combat-and-player.md) | Timing, transforms, damage, and VFX stay aligned after ordinary gameplay transitions. |

Avoid a second mutable copy of save state, item ownership, active floor state, or editable settings. Use the existing typed resource and signal APIs. Derived render state can be rebuilt from the owner and must refresh after the owning state changes. Keep private testing hooks out of the normal runtime unless the existing Training Ground or Workbench already owns that function.

For complex changes, find the user-visible outcome and list the involved owners, stable inputs or saved data, and observable acceptance criteria. Read scenes as well as scripts since scene values can override exported defaults. Trace an affected value from its authoring entry to its actual runtime use. When delegating, give each agent disjoint files or clear read-only roles, and integrate their work through a single coordinated edit.

## Commands from the project root

~~~powershell
godot --version
godot --headless --path . --import
godot --headless --path . --quit-after 4
godot --headless --path . --script res://tests/integration.gd
godot --path . --rendering-method forward_plus --script res://tests/inventory_appearance_render.gd
~~~

Import a fresh checkout and reimport when changed assets or addons need it. The short quit-after invocation checks project startup, not a full playthrough. Each test script is run separately. Some probes require a real window or GPU, and a headless run might skip the assertion of interest. Read the test for prerequisites and inspect the output summary. Treat Godot script, resource-load, and assertion errors as failures even if the executable returns zero.

Run the smallest set of tests that covers the behavior and its interacting owners. For a first publication or a dependency change, also verify a clean import because an existing .godot cache can conceal missing sources or binary dependencies. Large seeded balance sweeps are useful when tuning outcomes or proving distribution changes. Report their sample size, seed, and covered conditions if citing the results.

## Choose checks by changed behavior

| Change | Start with | Expand if needed |
| --- | --- | --- |
| UI state, inventory, or focus | [Inventory interaction](../../tests/inventory_revision.gd) and [UI presentation](../../tests/ui_presentation.gd) | [Native appearance](../../tests/inventory_appearance_render.gd), [stash](../../tests/stash_inventory.gd), [cards](../../tests/deck_cards.gd) |
| Scene bindings, player input and Training Ground | [Training Ground](../../tests/training_ground.gd) and [combat input](../../tests/player_combat_input.gd) | [Timeline editing](../../tests/combat_timeline_editing.gd), [facing at different headings](../../tests/enemy_attack_facing.gd) |
| Damage, effects or actor lifetime | [Combat impact](../../tests/combat_impact.gd) and [creature abilities](../../tests/creature_abilities.gd) | [Projectile reuse](../../tests/enemy_projectile_pool.gd), [ragdoll](../../tests/enemy_ragdoll.gd), effect-specific tests |
| Generation, navigation or fog | [Dungeon generation](../../tests/dungeon_generation.gd) and [map reveal](../../tests/map_reveal.gd) | [Secret route layouts](../../tests/secret_challenge_layouts.gd), [trap content](../../tests/secret_challenge_content.gd) |
| Persistence, rewards or run lifecycle | [Campaign integration](../../tests/integration.gd) and [expedition events](../../tests/expedition_events.gd) | [Broker trade](../../tests/secret_broker_trade.gd), [supply interactions](../../tests/inventory_supplies.gd) |
| Workbench resource or native inspector | Edit and save an isolated copy through the actual editor control | Reopen the record and launch a clean game using that resource. See [Workbench verification](workbench-and-data.md). |

### Native visual and input checks

1. Open the actual production screen, room, or weapon under the renderer that the user reported. Preserve the relevant game state, viewport size, and input sequence.
2. Verify what is visibly drawn and what receives input. Include a narrow viewport if layout and fit are affected. Exercise rebuild, close and reopen, and state switches if those could change layout or temporal effects.
3. Inspect the capture or record pixel samples when appearance is quantitative. Interpret HDR texture readback in the right color space. UI colors can be encoded for display while the viewport readback is linear.
4. Check the game log and summarize the verified platform, renderer, and scenario. A code review, a mockup, and a headless fixture cover different parts of the feature.

### Save and editor checks

- Use scratch saves and isolated authoring fixtures for destructive or persistent trials. Never point a fixture at the user's live slot directory.
- Verify old data when changing a schema. Exercise load, action, save, reload, and blocked or failed transitions.
- For exported data, inspect the exact property edited, whether the Workbench marks the intended source dirty, the bytes written by Save Changes, the reloaded record, and the in-game observation. Respect timing or restart requirements of the owning system.
- For runtime asset edits, keep the authored source and its imported representation in sync. Reimport in a clean cache before concluding a resource identifier or dependency path is portable.

## Documentation requirements

Apply [the root maintenance rule](../../AGENTS.md#important-keep-documentation-current-in-every-change) in the same task as each change. Keep instructions concise in AGENTS.md and put detailed explanation in the topic guide. Put required commands and constraints up front, then add owner paths, symptoms, and verification that an agent can execute. Use headings that let readers load one topic without reading everything. Use relative links and refer to source code for exact constants.

A new owner, removed file, altered input, schema migration, revised asset pipeline, or changed test invocation should be traceable from the topical guide. State current behavior. Preserve historical experiments in their own plan or report and distinguish past evidence from current qualification. Check links when moving or deleting files.

These guides use compact repository and scoped instructions backed by linked references, following [OpenAI's AGENTS.md guidance](https://developers.openai.com/codex/guides/agents-md) and [Codex best practices](https://developers.openai.com/codex/learn/best-practices).

## Review before publishing

1. Review the complete staged change set for the authorized scope. Check for user-specific saves, logs, credentials, copied reference materials, generated import caches, and temporary native libraries.
2. Run the relevant tests against the final inputs. Review the changed docs alongside the code. When Git is available, use git diff --check for changed text and git diff --cached --check for the staged text in scope.
3. Preserve required addon notices and runtime binaries. Verify a clean checkout when publishing or altering import/build dependencies. Keep original user resources when reproducing persistence failures.
4. Push only to the requested remote and branch and verify the published ref. Record concrete limitations, exact test commands when useful, and any verification that could not run.
