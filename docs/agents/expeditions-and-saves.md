# Expeditions, characters, and saves

Use this guide when changing session entry, character slots, save data, dungeon restoration, encounter lifetime, loot, card persistence, or merchant state. [main.gd](../../main.gd) wires those paths together from [main.tscn](../../main.tscn). The systems below own their records and validation. See [World and assets](world-and-assets.md) for geometry and authored placement, [Workbench and data](workbench-and-data.md) for tuning, and [UI and inventory](ui-and-inventory.md) for interaction and presentation.

## Session and character entry

| Entry | Owner and result |
| --- | --- |
| Title screen | `_show_title()` obtains slot summaries through [CharacterSlots](../../systems/character_slots.gd). `_select_character(slot)` loads the selected slot. |
| Create a character | `_create_character(slot, name)` requires the title session and a free slot. Names are trimmed, must contain 1–24 characters, and reject ASCII control characters. The slot number is the identity. A fresh campaign receives 30 gold, a starter weapon, and a stocked hub vendor. |
| Resume a character | `_begin_campaign()` restores inventory, deck, progression, lifetime statistics, bestiary, and a retained expedition if one exists. Equipment and progression are applied before saved Life, Mana, Ward, and Stamina are clamped to the current caps. Login starts at the hub. |
| Enter Training | Title entry creates a `PRACTICE` session. A character entering from the hub temporarily receives a separate inventory, progression object, and card deck. Leaving restores the campaign bindings, vitals, and card effects. Training unlocks the bestiary view and allows test weapon drops, enemies, and card use. Practice progress stays in the temporary session. |

[CharacterSlots](../../systems/character_slots.gd) translates zero-based slots 0–9 into `character_01` through `character_10` beneath `SaveStore.SAVE_DIRECTORY` (`user://checkpoints`). Give tests their own `main.save_directory`. `main.save_enabled` is the persistence switch, and an isolated temporary directory is required when testing writes or reloading a slot. Avoid binding fixtures to personal characters.

[CharacterProgression](../../systems/character_progression.gd) owns player level, XP, and attribute allocation. Dungeon depth is an expedition input and currently supplies its generated enemy level. Treat these as distinct values in new gameplay. [CharacterStatistics](../../systems/character_statistics.gd) stores the totals, recorded kills and deaths, and awarded achievement IDs. The bestiary is keyed by archetype ID through [Bestiary](../../data/bestiary.gd). Keep generated names available for display while counting kills and discoveries against the stable archetype.

## Checkpoint format and failure handling

[SaveStore](../../systems/save_store.gd) publishes append-only `RPGSAVE` checkpoints. The version-1 record uses `g-%020d-%s.save` filenames with a sequence and nonce. The writer serializes a bounded JSON payload, flushes a temporary file, verifies the staged contents, renames to a new generation in the same directory, verifies the published file, and retains three healthy generations. The reader verifies header, filename, SHA-256, and payload, then walks back from a damaged generation. A valid checkpoint with a future format version stops the read and prevents an older generation from being used for a replacement write.

Only JSON-compatible values belong in a checkpoint. The store caps files at 8 MiB and JSON nesting at 32, accepts finite numbers, and bounds integers to the exact JSON integer range (±9,007,199,254,740,991). Serialize RNG state and the run seed as strings. Use string keys for floor and actor IDs and use the existing coordinate array helpers for positions. Model durable state explicitly before saving it. Scene nodes, projectiles, timers, tweens, drag visuals, and pending input are runtime state.

`_save_now()` writes the character name, inventory, expedition, depth unlocks and completions, RNG state, vitals, bestiary, card deck, progression, and lifetime counters. It returns without writing for title/practice sessions, disabled saving, or an in-progress campaign setup. When a character saves from the Training Ground, the checkpoint uses the parked campaign vitals and effects. `_save_and_quit()` saves before returning to title. The OS window close path saves before quitting and keeps the player in the game with a failure message if the write fails. Focus loss pauses. These are explicit checkpoint paths.

[WindowPreferences](../../systems/window_preferences.gd) lives separately in `user://settings.cfg`. It stages and verifies updates and reads a backup if required. Startup can read the prior fullscreen preference as a fallback. Character selection and progression use their slot checkpoint.

Keep compatibility boundaries distinct. The checkpoint file format protects publication and parser compatibility. Dungeon generation and rarity versions preserve deterministic reconstruction. Item restoration and inventory layout migrations normalize previously saved records. Give new fields documented defaults, and test both the new write/read path and a representative prior payload.

## Expedition lifecycle

1. `_select_depth()` accepts an unlocked depth when outside Training and no expedition is active. It selects a seed and tileset, freezes the equipped card loadout, and initializes each floor's state plus expedition-wide counters.
2. [ExpeditionFeatures](../../world/expedition_features.gd) plans per-floor masks using an independent seed from the expedition seed. Floors share a budget for major events and can generate quietly. [Expedition rules](../../data/expedition_rules.gd) set the defaults for floor count, stair direction, encounter pace, and grace periods. Current runs start with two floors and use three from Depth 7. The floor geometry seed is `int(run.seed) + floor_index * 2654435761`. Rarity draws use a separate RNG.
3. `_build_dungeon()` assembles and joins connected floor scenes, creates floor runtime ownership, then populates enemies, props, hazards, loot, and special sites. The player switches logical floors by walking the connector. `_use_dungeon_floor()` updates the active aliases, water, and HUD/map ownership.
4. `_mark_cleared()` records each required floor and marks the expedition cleared once connected floors and their required enemies are resolved. Completion advances unlocks, grants clear XP, increments the completion count, and restocks the hub vendor once. Ordinary hazards shut down on clear. Revealed secret challenge traps can still operate.
5. `T` creates a return portal at a valid point. Returning to the hub parks the same live dungeon root and remembers the player transform for the current session. Relogging starts in the hub and reentry via the altar starts at the safe entrance on floor 0. The restored layout, exploration, portals, loot, and recorded actor state survive a retained expedition.
6. Current defaults keep an uncleared expedition for 480 seconds on logout and a cleared expedition for 30 seconds after first leaving it. Saving from within a cleared expedition initializes its grace window if needed. The saved deadline is wall-clock time. An existing deadline survives another save, and resuming play clears only the uncleared logout deadline. A timeout or explicit seal frees the parked dungeon and clears unclaimed ground loot and expedition keys. Banked items and campaign progression stay in the character.

`run` stores the expedition-wide seed, depth, generation and rarity versions, tileset, feature masks, floor metadata, clear progress, shared ground-loot sequence, key-drop budget, card state, one-use effects and recap. Its current-floor keys are defined in `FLOOR_STATE_DEFAULTS`. They cover defeated and live actor records, opened props and remaining loot, explored tiles and map landmarks, return portal, opened secrets and broken props, activated ambush waves, clue history, route locks and collected keys, extra and revived actors, and broker stock. The same floor keys live under `run.floor_states[str(index)]` when parked. Use `_floor_state(index)` for callbacks carrying an explicit floor index. Add new floor keys to the defaults so restoring and switching apply the same behavior.

A `DungeonFloor` is the runtime owner of geometry, actors, props, hazards, loot, room counters, portals, water, merchants, and encounter references for that floor. Limit uses of active-floor aliases to current interactions. Actor checkpoints save remaining health, max health, origin-local position, and explicit behavior or metamorphosis state. Stable actor names, append-only extra encounter IDs, and convergence destinations have their respective persisted fields. Persist a feature's actual gameplay state and reconstruct its presentation.

### Deterministic compatibility

[Dungeon](../../world/dungeon.gd) currently uses generator version 10. Connected floors start at version 5, dormant encounters at 6, route gates at 7, trial coffers and planned events at 8, expanded rosters at 9, and authored secret challenges at 10. Earlier saved versions replay their prior floor construction and roster branches. Missing generation versions are read as 1. Main's rarity profile is version 2. Changes to random draw order, roster iteration, encounter IDs, or feature placement can change which actor a saved record refers to. Keep the older branch intact or migrate explicitly and cover it with fixed seeds.

`_remember_active_floor()` records map state and live actors across all built floors. `_select_floor_state()` moves only the known floor keys between the active and parked sections. Map fog, landmarks, and secret knowledge must move with their physical floor. Apply the floor transform at world interaction boundaries. A moved actor retains an origin and can have a different physical floor.

## Encounters, rewards, and trading

### Encounter activation and clear accounting

- `_populate_dungeon_floor()` assigns IDs in deterministic spawn order and skips defeated actors. It restores saved additions and revived actors. Dormant records with `spawn_trigger` of `threshold` or `coffer` register when that room trigger fires. An unopened optional ambush is outside the clear requirement. Its live actors count once awakened.
- A trial coffer activates one wave at a time. The highest triggered room wave is persisted. Resolve the current guards before advancing or opening the reward. When changing a trigger path, test reentering and reloading during the sequence.
- The Blood Altar commits one oath to the entire expedition. If the choice grants a Treasure Key, the pack must accept it before the oath is recorded. Applied modifiers affect the current and later-populated eligible enemies, gold, and gear through the existing owner. Keep choice IDs stable so a retained oath replays. See [Blood Altar rules](../../data/blood_altar_rules.tres).
- Convergence considers active enemies across the expedition and waits for valid footing. The current thresholds are four remaining actors and a 1.4-second delay. [DungeonEnemyConvergence](../../world/dungeon_enemy_convergence.gd) preserves the same actors, life, identity, rarity, and affixes as it relocates eligible stragglers. Untriggered encounters stay dormant.
- Death and room completion use the actor's origin floor. Loot uses the actor's physical floor. Keep the origin binding for kill XP and progression after convergence. Use the current physical floor's world-to-local transform for the drop. A moth cocoon keeps the enemy's encounter alive until terminal resolution. The optional Grave Legate incursion uses a combat-time trigger and persisted actor records. Its raised actors return to room accounting without repeating ordinary kill XP or drops.
- Expedition recap lives in `run.recap` plus counts built from completed floor and card state. Lifetime counters live on the character. The 1,000-entry Combat Log is a rolling session record. These consumers use resolved events at different scopes.

### Item ownership and pickup

[Inventory](../../systems/inventory.gd) owns item records and their occupancy through the existing spatial grid. The current pack is 12×6, the vendor grid baseline is 10×7, and the ten equipment slots include Belt and the locked Off Hand while using a two-hander. [StashInventory](../../systems/stash_inventory.gd) contributes five independent 12×12 grids with stable `stash:0` through `stash:4` IDs. The snapshot reconstructs a recoverable layout for a carried item without changing live cursor ownership. Restoration stages and validates the replacement model before swapping it in. Keep compatibility for supported 10×7 and rotated legacy pack records through the existing migrations.

[PackSupplies](../../systems/pack_supplies.gd) defines crafting materials, Treasure Keys, route keys, and the identification currency (Scribe's Seal). Supplies use one cell. Materials and seals stack to 50. `inventory.materials` is a count derived from pack records. Crafting consumes the actual items in a single operation. Expedition keys are individual units, unavailable to trade or stash. A route gate requires the stable ID of its own route key. Ordinary locked coffers use Treasure Keys. Tollkeeper's Mercy can refund its eligible ordinary coffer key once per expedition.

`_store_loot()` allocates a ground ID from the expedition-wide counter and records a concrete payload and floor-local point before spawning a visible prop. Item, supply, and key pickups remove that record only when inventory accepts the item. A failed placement leaves the prop available for retry. Gold has a separate nearby pickup path. Rolled data is stored at drop time and reused at restore. When changing reward code, verify that a retry or reentry grants each reward once and that a full pack leaves the item available. [Loot records](../../data/items/loot_records.tres) author the economy inputs.

### Hub and secret merchants

The hub vendor is stocked at campaign creation and after an expedition clear. Its difficulty baseline derives from the highest clear (`maxi(1, unlocked - 1)`) through the item catalogue. Ordinary menu opening reads its present stock. The Lantern Broker is possible at Depth 10 and above behind a concealed passage. `_open_secret_broker()` seeds its first catalogue from the expedition seed and floor, opens a separate expedition vendor, then saves remaining rows and grid height to that floor on close or checkpoint. Reopening or relogging uses the same stock, including purchase depletion. Route buying and selling through the inventory transaction so currency and record changes agree. See [Secret merchant rules](../../data/secret_merchant_rules.tres).

## Card ownership and consumption

[CardDeck](../../systems/card_deck.gd) owns permanent unlocks and the equipped loadout. [CardCatalog](../../data/card_catalog.gd) defines the three-slot default and authored cards. A normal character edits the loadout from the hub with no active expedition. An expedition snapshots that loadout on entry. Training uses a temporary deck with all cards available.

`_choose_card()` validates the active hand and queues the choice for the physics update. The update rechecks stun, invokes the effect, and records the spent ID only on the accepted cast path. `used_cards` lasts for that expedition. Active card buffs have an explicit checkpoint snapshot. The open hand, cursor and time-scale changes, and pending selection are transient and settle when the hand closes or the session changes.

Magic and rare enemy rewards use the existing deterministic drop path and skip duplicate cards already owned, carried or on a retained floor. [CardItems](../../systems/card_items.gd) defines the physical 1×1 unidentified reward. Identification uses Scribe's Seal. Learning through `Inventory.learn_card()` and `CardDeck.unlock_when()` consumes the item only as part of a successful permanent unlock. Preserve the legacy reward adapter when converting older ground payloads.

## Verification entry points

Run the focused Godot scripts from the project root with a Godot 4.7 console executable. The command below runs the integration fixture in an isolated session.

```text
godot --headless --path . --script res://tests/integration.gd
```

| Changed behavior | Start here |
| --- | --- |
| Slot save/reload, reentry, ordinary expedition lifecycle | [Integration](../../tests/integration.gd) |
| Seed replay, traversal, exploration persisted by floor | [Dungeon generation](../../tests/dungeon_generation.gd), [Map reveal](../../tests/map_reveal.gd) |
| Gates, ambush timing, trials, altar, Legate and revival | [Expedition events](../../tests/expedition_events.gd) |
| Global active-enemy threshold and origin/physical floor identity | [Convergence](../../tests/dungeon_convergence.gd) |
| Hidden broker site and stock, exploration legendary state | [Secret merchant site](../../tests/secret_merchant_site.gd), [Broker trade](../../tests/secret_broker_trade.gd), [Legendary exploration](../../tests/legendary_exploration.gd) |
| Character/training isolation, card rewards, timed effects and loadouts | [Training Ground](../../tests/training_ground.gd), [Deck cards](../../tests/deck_cards.gd) |
| Pack layout migration, cursor state and stack/key/stash ownership | [Inventory revision](../../tests/inventory_revision.gd), [Supplies](../../tests/inventory_supplies.gd), [Stash](../../tests/stash_inventory.gd) |
| Level, attributes, and gear interactions | [Character progression](../../tests/character_progression.gd), [Progression combat](../../tests/player_progression_combat.gd) |

Test saved-state changes against a read-back in a new scene or new model. Include a failure path whenever you change a transaction. Cover generated encounter changes with both a fresh seed and an older save's generation epoch. Use a running renderer to verify visible transitions and input when a headless assertion cannot observe the result.
