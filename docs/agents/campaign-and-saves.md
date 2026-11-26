# Character sessions and saves

Use this guide when changing session entry, character slots, save data, Training Ground isolation, inventory, card persistence, or merchant state. [main.gd](../../main.gd) wires those paths together from [main.tscn](../../main.tscn). The systems below own their records and validation. See [World and assets](world-and-assets.md) for geometry and authored placement, [Workbench and data](workbench-and-data.md) for tuning, and [UI and inventory](ui-and-inventory.md) for interaction and presentation.

## Session and character entry

| Entry | Owner and result |
| --- | --- |
| Title screen | `_show_title()` obtains slot summaries through [CharacterSlots](../../systems/character_slots.gd). `_select_character(slot)` loads the selected slot. |
| Create a character | `_create_character(slot, name)` requires the title session and a free slot. Names are trimmed, must contain 1–24 characters, and reject ASCII control characters. The slot number is the identity. A fresh campaign receives 30 gold, a starter weapon, and a stocked hub vendor. |
| Resume a character | `_begin_campaign()` restores inventory, deck, progression, lifetime statistics, and bestiary. Equipment and progression are applied before saved Life, Mana, Ward, and Stamina are clamped to the current caps. Login starts at the hub. |
| Enter Training | Title entry creates a `PRACTICE` session. A character entering from the hub temporarily receives a separate inventory, progression object, and card deck. Leaving restores the campaign bindings, vitals, and card effects. Training unlocks the bestiary view and allows test weapon drops, enemies, and card use. Practice progress stays in the temporary session. |

[CharacterSlots](../../systems/character_slots.gd) translates zero-based slots 0–9 into `character_01` through `character_10` beneath `SaveStore.SAVE_DIRECTORY` (`user://checkpoints`). Give tests their own `main.save_directory`. `main.save_enabled` is the persistence switch, and an isolated temporary directory is required when testing writes or reloading a slot. Avoid binding fixtures to personal characters.

[CharacterProgression](../../systems/character_progression.gd) owns player level, XP, and attribute allocation. [CharacterStatistics](../../systems/character_statistics.gd) stores the totals, recorded kills and deaths, and awarded achievement IDs. The bestiary is keyed by archetype ID through [Bestiary](../../data/bestiary.gd). Keep generated names available for display while counting kills and discoveries against the stable archetype.

## Checkpoint format and failure handling

[SaveStore](../../systems/save_store.gd) publishes append-only `RPGSAVE` checkpoints. The version-1 record uses `g-%020d-%s.save` filenames with a sequence and nonce. The writer serializes a bounded JSON payload, flushes a temporary file, verifies the staged contents, renames to a new generation in the same directory, verifies the published file, and retains three healthy generations. The reader verifies header, filename, SHA-256, and payload, then walks back from a damaged generation. A valid checkpoint with a future format version stops the read and prevents an older generation from being used for a replacement write.

Only JSON-compatible values belong in a checkpoint. The store caps files at 8 MiB and JSON nesting at 32, accepts finite numbers, and bounds integers to the exact JSON integer range (±9,007,199,254,740,991). Serialize RNG state as a string. Model durable state explicitly before saving it. Scene nodes, projectiles, timers, tweens, drag visuals, and pending input are runtime state.

`_save_now()` writes the character name, inventory, RNG state, vitals, bestiary, card deck, progression, and lifetime counters. It returns without writing for title/practice sessions, disabled saving, or an in-progress campaign setup. When a character saves from the Training Ground, the checkpoint uses the parked campaign vitals. `_save_and_quit()` saves before returning to title. The OS window close path saves before quitting and keeps the player in the game with a failure message if the write fails. Focus loss pauses. These are explicit checkpoint paths.

[WindowPreferences](../../systems/window_preferences.gd) lives separately in `user://settings.cfg`. It stages and verifies updates and reads a backup if required. Startup can read the prior fullscreen preference as a fallback. Character selection and progression use their slot checkpoint.

Keep compatibility boundaries distinct. The checkpoint file format protects publication and parser compatibility. Item restoration and inventory layout migrations normalize previously saved records. Give new fields documented defaults, and test both the new write/read path and a representative prior payload.

[Item balance version 6](../../systems/items.gd) refreshes defensive core values on existing catalogued gear from its base record and item level. Stored identity, tier, price, affixes and fixed legendary bonuses are carried into the refreshed item. The [campaign integration test](../../tests/integration.gd) loads a pre-v6 armor record and checks that a second restore produces the same result.

## Compatibility with retired areas

Older slots can contain an in-progress procedural expedition or Open World state. Loading one opens Cinderhold Refuge and restores permanent inventory, gold, attributes, XP, deck, bestiary, and lifetime history. Already claimed items and rewards remain part of the character. The checkpoint reader ignores retired area state, including local ground loot, quest and cache progress, and the outdoor clock. Temporary expedition keys are cleared on load. Former dungeon statistics stay in the saved history, and earned awards keep their points. The current menus omit retired dungeon goals and counters. The next ordinary save writes the current schema. Use an isolated older slot to check loading, saving, and reopening the new generation.

## Inventory, rewards, and trading

[Inventory](../../systems/inventory.gd) owns item records and their occupancy through the existing spatial grid. The current pack is 12×6, the vendor grid baseline is 10×7, and the ten equipment slots include Belt and the locked Off Hand while using a two-hander. [StashInventory](../../systems/stash_inventory.gd) contributes five independent 12×12 grids with stable `stash:0` through `stash:4` IDs. The snapshot reconstructs a recoverable layout for a carried item without changing live cursor ownership. Restoration stages and validates the replacement model before swapping it in. Keep compatibility for supported 10×7 and rotated legacy pack records through the existing migrations.

Backpack drag and click swaps use the same [cursor journal](../../systems/backpack_cursor.gd). A successful swap detaches one backpack placement and keeps its item record available until the cursor settles. Cancelling either input route restores the journal. See the [inventory interaction tests](../../tests/inventory_revision.gd) for rollback and saves taken during a swap.

[PackSupplies](../../systems/pack_supplies.gd) defines stackable crafting materials and the Scribe's Seal used for identification. Supplies use one cell and stack to 50. Crafting consumes their actual pack placements through the inventory transaction. The hub vendor is stocked at character creation and keeps its own catalog in the character checkpoint. Trade uses the shared pack model so currency, stock, and ownership commit together.

## Cards

[CardDeck](../../systems/card_deck.gd) owns permanent unlocks and the character's three-slot loadout. Existing physical cards load using [CardItems](../../systems/card_items.gd) and can still be identified with a Scribe's Seal, moved, sold, or learned. Learning commits the unlock and consumes the item together.

The Training Ground opens a separate practice deck with all registered cards. The real Q combat hand queues a choice for the physics update, consumes it when its effect is accepted, and restores the normal input and time scale on close. Resetting practice refreshes the practice cards. The hub deck edits the campaign character's owned cards.

## Verification

- [Campaign integration](../../tests/integration.gd) covers starting, loading, and saving isolated named characters.
- [Training Ground](../../tests/training_ground.gd) and [deck cards](../../tests/deck_cards.gd) cover practice isolation, casting, and loadouts.
- [Inventory revision](../../tests/inventory_revision.gd), [supplies](../../tests/inventory_supplies.gd), and [stash](../../tests/stash_inventory.gd) cover item ownership and compatibility.

Use a Godot 4.7 console executable with `--headless --path . --script res://tests/integration.gd` for the campaign fixture. Use a fresh character and a representative legacy slot for changed persistence. Check visible transitions through the actual Forward+ menus and interactions.
