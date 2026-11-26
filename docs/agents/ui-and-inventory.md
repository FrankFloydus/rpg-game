# UI and inventory

This guide covers the game screens, item presentation, inventory transactions, and physical cards. Changes to these systems often cross a scene, an interaction script, and a data owner. Follow the production path before changing any one of them.

## Find the owner

| Work | Start here |
| --- | --- |
| Screen composition, menu transitions, input routing | [Main scene](../../main.tscn), [game session](../../main.gd), [project settings](../../project.godot) |
| Shared game theme and palette | [Theme resource](../../ui/hearth_gear_theme.tres), [MenuFrame](../../ui/menu_frame.gd) |
| Pack, equipment, stash, merchant, blacksmith | [Inventory scene](../../ui/inventory_ui.tscn), [screen controller](../../ui/inventory_ui.gd) |
| Cursor, drag, split, and grid interaction | [Carry controller](../../ui/inventory_carry.gd), [grid view](../../ui/inventory_grid.gd), [equipment slot](../../ui/inventory_equipment_slot.gd) |
| Placement, ownership, eligibility, transactions, and inventory persistence | [Inventory model](../../systems/inventory.gd), [cursor journal](../../systems/backpack_cursor.gd), [stash endpoints](../../systems/stash_inventory.gd), [native equipment adapter](../../addons/godot-spatial-inventory/inventory_equipment.gd) |
| Item definitions, names, stats, filtering text, affixes, and prices | [Item API](../../systems/items.gd), [gear records](../../data/items/gear_records.tres), [affix records](../../data/items/affix_records.tres), [loot records](../../data/items/loot_records.tres) |
| Inventory icon lookup and tooltip format | [Item art](../../ui/item_art.gd), [tooltip controller](../../ui/item_tooltip.gd), [tooltip pane](../../ui/item_tooltip_pane.tscn) |
| Inventory colors and Workbench swatches | [Appearance resource](../../data/inventory_item_style.tres), [property definitions](../../data/inventory_item_style.gd), [shared painter](../../ui/inventory_appearance.gd), [preview](../../ui/inventory_appearance_preview.gd), [Workbench window](../../addons/hearth_workbench/workbench_window.gd) |
| Physical cards, collection, loadout, and casting | [Card item model](../../systems/card_items.gd), [deck model](../../systems/card_deck.gd), [card catalogue](../../data/card_catalog.gd), [card interface](../../ui/card_interface.gd), [shared loadout](../../ui/card_loadout.gd) |

## Work with the authored scenes

The production game instances its major UI screens under the `Interface` CanvasLayer in [main.tscn](../../main.tscn). Open the relevant `.tscn` in Godot to edit layout, spacing, typography, scroll regions, and visible controls. Scripts bind data and signals, present the selected mode, and instance the authored templates for variable-length lists and cards. Keep new fixed controls, fixed layout, empty states, and repeatable visual templates in scenes.

| Scene | Editor and runtime responsibilities |
| --- | --- |
| [Inventory](../../ui/inventory_ui.tscn) | Defaults to an editor preview of Equipment, Your Pack, and Character. Toggle the hidden Catalogue, Storage, or Smith and SmithPack branches to inspect their layouts. The controller turns the appropriate branches on for `inventory`, `vendor`, `stash`, or `smith`. Equipment wells and grid controls are actual scene nodes. The real model supplies their contents at runtime. |
| [Inventory carry](../../ui/inventory_carry.tscn) | Owns the authored split dialog under `SplitLayer`. The controller opens it, focuses the quantity input, and handles what the cursor holds. |
| [Item tooltip](../../ui/item_tooltip.tscn) and [pane](../../ui/item_tooltip_pane.tscn) | The shell follows the pointer. It instances pane templates for the target item and any equipped counterparts. The pane owns heading, art, detail rows, and optional price. The tooltip never takes mouse focus. |
| [HUD](../../ui/hud.tscn) and [menus](../../ui/hud_menus.tscn) | Distinguish always-visible gameplay content from menu pages. The controller fills vitals, status badges, notices, pause/settings, lifetime stats, and achievements from the appropriate model or game session. |
| [Title](../../ui/title_screen.tscn) | Ten character slots plus the creation form, Training Ground, Settings, and Quit. The title emits selection and creation intent. [CharacterSlots](../../systems/character_slots.gd) validates 1–24-character names, lists the saved roster, and resolves storage by numeric slot. |
| [Training roster](../../ui/training_roster.tscn) | F1 opens Enemy, Weaponry, and Cards tabs. The roster presents test choices and emits requests. The session owns spawning, training state, and the separate inventory/deck. |
| [Card interface](../../ui/card_interface.tscn) and [loadout](../../ui/card_loadout.tscn) | The interface owns the in-combat fan, grip art, and mode-specific shade. The loadout scene handles collection browsing and equipped slots, including its Training Ground instance. |
| [Bestiary](../../ui/bestiary_ui.tscn) and [Combat Log](../../ui/combat_log_ui.tscn) | Bestiary owns portrait/record browsing, discovery presentation, and ability chips. Combat Log owns browsing and filtering existing combat events. Their controllers receive session data. |
| [Destruction confirmation](../../ui/destroy_item_dialog.tscn) | The session instances it only for an eligible item discarded in the Refuge. A successful confirm is the point at which ownership changes. |

### Layout, visual states, and focus

- Use the shared theme resources for near-black surfaces, thin iron-grey borders, typography, and normal, hover, focus, pressed, and disabled states. Preserve semantic colors such as item identity state, combat feedback, and placement validity. Change shared theme tokens or variations when a visual treatment belongs to multiple screens.
- Preserve `unique_name_in_owner` for scene nodes referenced as `%Name`. Check other hard-coded node paths before renaming or moving nodes. Keep an editor-readable default view and runtime visibility wiring.
- Compose with Godot containers and anchors. The authored logical viewport is 1280×800, with `canvas_items` stretch and `expand` aspect. Test the actual viewport bounds at short and narrow window sizes. Treat logical UI dimensions and physical image pixels separately when capturing samples.
- Bound the body of long galleries and lists with a scroll container. Include scrollbar width in column calculations and preserve the minimum interactive size of children. Training reflows the current tab and builds its focus chain from that tab's real controls. Retain wheel access to the last cards and rows.
- Put initial focus on a meaningful visible control. Keep hidden mode and tab branches outside focus navigation. Restore focus on returning from character creation or a nested menu. In the inventory, a focused stash search accepts the letter I as text. Escape clears a split, carry, identification cursor, or native drag before it closes the board.
- Keep purely decorative and overlay controls set to `MOUSE_FILTER_IGNORE` where appropriate. Test actual `gui_get_hovered_control()`, focus, and mouse delivery before adjusting click handlers. Use `get_global_transform_with_canvas()` when crossing local, viewport, or scrolled grid coordinates.
- Route gameplay modal changes through [the game session](../../main.gd). It manages input capture, gameplay activity, player movement, whether world effects may advance, and return to the prior mode. A modal drawing over gameplay can still consume gameplay input.

## Inventory model and persistence

### Ownership and dimensions

[Inventory](../../systems/inventory.gd) owns the per-ID item dictionaries, gold, equipped placements, grid endpoints, and transaction results. Godot's `SpatialInventory` extension holds placement geometry and provides the checked placement and transfer operations. The UI reads `get_item`, `get_grid`, `equipped_id`, and `equipped_anchor`. Use the gameplay model to preview and commit changes so ownership, gold, equipment requirements, sounds, and save signals remain consistent.

| Owner | Baseline geometry or role |
| --- | --- |
| `bag` | 12 columns × 6 rows. The runtime view scrolls migrated saves with additional rows. |
| `vendor` | 10 columns × 7 rows for Cinderhold's provisioner stock. |
| `stash:0` through `stash:4` | Five per-character 12×12 grids. Each has independent placements and may gain recovery rows during migration. |
| `equipment` | Ten named slots, including two rings, two hands, and belt. Equipment anchors the item once and can reserve an extra slot for a two-handed weapon. |
| Displaced backpack item | One temporarily detached item still owned by the inventory. The [cursor journal](../../systems/backpack_cursor.gd) remembers each swap's original and expected placements. |

Footprints come from the item definition and remain in authored orientation. A weapon well has its own fixed scene dimensions. It centers the item using its actual cell footprint. The main-hand and off-hand wells keep their frame when a 1×3 weapon, a shield, or a two-handed weapon occupies them. `equipped_anchor` identifies the actual owner when the other hand is reserved. The reserved slot shows the lock and rejects incompatible actions. Empty wells show their empty state and faint slot art.

Standard one-handed weapons can use either hand and rings can use either ring slot. Other slot requirements, unidentified gear restrictions, and displaced-item fit checks belong to the model and native equipment adapter. A click returning an item to the equipment slot that still owns it succeeds without a new equipment transaction. Keep that source-return path distinct from previewing a move into another slot.

### Placement and transaction boundaries

1. The grid and carry views translate an input position into an item ID or a candidate top-left cell. The art under the cursor uses the center of the complete footprint. A footprint overlapping a clipped grid can still target its in-bounds clamped position just outside the visible edge.
2. The same footprint must drive both highlight and commit. Apply the model's preview functions to the candidate cell and show a valid or invalid state. The placement stays in that cell when blocked. Quick transfer and other explicit first-fit actions may search for space.
3. Click carry and native drag both use the checked backpack cursor transaction when moving a pack item within the pack. An accepted single-item swap paints only the overlap cells yellow and places the incoming item while carrying the displaced one. The displaced item can be placed or swapped again. Multiple distinct overlaps reject the entire candidate. Compatible supply stacks follow their normal merge rules. Cancel restores the swap journal or uses the model's safe fallback. The merchant, stash transfer, split, and identification routes use their own checks.
4. Use atomic changes for both placements and item records. A success updates the authoritative state before emitting the relevant notifications. A denial leaves ownership and gold intact. [Inventory sounds](../../ui/inventory_sounds.gd) sends one grab cue when picking up and one item-specific placement cue on a successful place or quick action. The session owns world pickup/drop audio and keeps trade and lifetime accounting on committed events.
5. Outside-panel drop emits intent to the session. The pack or equipment still owns the item at that point. The session finds a valid world drop point in the Training Ground, or asks for destruction confirmation in the Refuge. Merchant stock, stash stock, a split stack, and an identification cursor are never promoted to world drops by that gesture.

[Inventory save and restore](../../systems/inventory.gd) serializes stable item IDs, full records, valid placements, equipment, gold, five stash tabs, and the permanent merchant stock. The save uses a safe layout during a cursor swap and can add recovery rows when needed. Restore stages a fresh model, migrates legacy orientation and dimensions, and replaces the live data only on success. Preserve older records rather than depending on today's default bag height. [Character slots](../../systems/character_slots.gd) route this state to the correct character checkpoint through [SaveStore](../../systems/save_store.gd). Training binds a temporary inventory/deck. The campaign objects are restored on exit.

### Stash, merchant, and blacksmith

- Stash tabs use the same inventory model and grid view. Changing the tab reroutes the endpoint without moving held stock implicitly. Text search requires all terms to match the visible item name, base, type, or visible details. Rarity and type filters highlight or dim without altering the native layout. Unidentified gear never supplies hidden affixes to search, and unidentified cards supply no catalogue rarity, title, art, or description.
- Stackable supplies can merge during a checked movement. A split remains part of its source until the selected quantity commits. Bulk stash transfer can use available partial stacks and retains any remainder.
- The Refuge provisioner uses the merchant surface and the shared buy and sell operations. The character checkpoint carries that merchant stock. Gold is shared with the active character, and stock changes only after the trade's funds and placement checks pass.
- The blacksmith selects an identified gear item in the pack. Recipes and material requirements come from authored item data. Inventory crafting consumes the ingredients and applies the forged item record in one transaction. The UI shows recipe needs and the model's availability result.

## Controls and item lifecycle

| Context | Input |
| --- | --- |
| Gameplay | I opens the pack. E interacts with targeted actors such as the merchant, stash, and blacksmith. Q opens the character deck in Cinderhold and the practice hand in the Training Ground. |
| General inventory use | Left-click an item to carry it, then left-click a destination to place it. Native left drag is also supported. Right-click ordinary gear in the pack to quick-equip, or right-click worn gear to return it to the bag when it fits. |
| Item tooltip | Hover for details, hold Shift for equipped comparisons, and hold Alt for advanced affix information. Comparisons show signed changes on shared stats. Hidden records are filtered before either tooltip variant. |
| Stash | Ctrl+left-click transfers the selected item or stack between pack and the current tab. Ctrl+right-click transfers matching stackable supplies up to capacity. Click carry and native drag support exact placement. |
| Merchant | Ctrl+left-click a catalogue item to buy or a pack item to sell. Carry between the grids to trade through the checked placement path. The merchant tooltip shows the purchase price. |
| Stack splitting | Shift+left-click a stack with at least two units in the pack or stash. Set an amount from 1 to one less than the stack and confirm with Enter or Split. Place the carried amount in the pack or stash. Escape or right-click cancels the carry or the quantity dialog. |
| Identification | Right-click a Scribe's Seal in the pack, then left-click eligible unidentified gear or a physical card in the pack. Escape or right-click cancels. Invalid targets leave the Seal and target untouched. |
| Learning a card | Right-click the identified physical card in the pack to add it to the bound collection. Duplicate cards stay in the pack. |
| Training Ground | F1 opens the roster. Weaponry requests a weapon on the ground for pickup and can show the player's weapon traces. Choose a **Contact Preset** to compare how that weapon strikes walls and nearby targets. Cards edits a practice loadout. Close F1 and press Q to play from it. Reset the arena to refresh spent training cards. |
| Menu navigation | Escape cancels the current sub-action or navigates back. Inventory handles I and Escape while open. The title handles Escape in character creation. |

Equip a two-handed mace and tap **left mouse button** for the left, right, down-left, and down-right light swings in order. Tap again within the combo window to repeat from the left swing. Hold **A** as you start a charge to sweep left, or **D** to sweep right. Keep holding attack through automatic release at about 1.5 seconds at normal attack speed, or release after about half a second to start the heavy sooner.

In **F1 → Weaponry → Contact Preset**, **Training** uses standard reach and lets solid contacts stop the weapon. **Carry Through** uses standard reach with solid-surface effects and follow-through. **Refuge** shortens and narrows the sweep and allows solid stops. A new practice visit starts in Training. Changes apply only in the arena. Verify selection and trace rendering in [the Training Ground fixture](../../tests/training_ground.gd).

The two-handed mace uses its close ready pose with normal weapon sway in the Training Ground. Check the ready pose on pickup, then watch the mace settle back into it after a swing.

### Identification and cards

[PackSupplies](../../systems/pack_supplies.gd) defines ordinary 1×1 materials, Scribe's Seals, and the physical card format delegated to CardItems. Only crafting materials and Seals stack, with a maximum of 50. Cards use individual placements.

Rare gear can store full affix rolls while remaining marked `unidentified`. Render `Items.visible_name` and the concealed tooltip branch. Keep private rolled data out of the UI until identification. The model denies equip and forge while unidentified. `Inventory.identify_item` consumes exactly one Seal and reveals the target at its existing location with its existing ID and gear roll. If the Seal's last unit is used its cell is freed.

A physical card from an older save uses a 1×1 placement. Before identification, the card has generic art and hides the catalogue effect. Identification reconstructs display fields from [the catalogue](../../data/card_catalog.gd). The model can store or sell a physical card under the normal rules. Learning uses the bound [CardDeck](../../systems/card_deck.gd), adds the unlock, consumes the physical item, and rolls the unlock back if consumption fails.

A campaign loadout has three slots and accepts owned cards. Edit it in the Refuge. In the Training Ground, Q presents the fan under a dim shade, releases the mouse, and temporarily slows the world. Selecting a card queues the real cast for physics. The session restores input and time scale on close and marks a cast as used when its gameplay use resolves. Training opens all registered cards in a separate practice deck while preserving the campaign's collection, loadout, and tracked buffs.

## Appearance authoring and renderer parity

Open **Workbench → Gear → Inventory appearance**. The authored [appearance resource](../../data/inventory_item_style.tres) is the single game source. The page's draft appears in the [Workbench preview](../../ui/inventory_appearance_preview.gd) as identified, unidentified, hovered, valid drop, invalid drop, swap overlap, and compatible equipment samples. Use **Save** to persist the draft and **Reload** to reread the source on disk.

| Properties | Visible use |
| --- | --- |
| Identified / unidentified fill | Resting placed-item tint, selected by identification state and shared across pack, stash, merchant, and filled equipment. RGBA. |
| Identified / unidentified hover fill | Alternative fill for a highlighted item when Highlight Items is enabled. RGBA independent of the matching resting color. |
| Highlight Items | Switches selection and hover behavior between their highlight fills and resting fills. |
| Outline Color | Thin item outline. Alpha zero leaves the outline invisible. |
| Grain Opacity | Optional texture drawn over the placed fill. Zero skips the texture. |
| Valid / Invalid Drop Color | Color of the footprint feedback for approved or denied placement. Compatible equipment uses the valid color. |
| Drop Fill Opacity | Interior opacity of placement previews, including the yellow swap intersection. The outline stays visible at zero. |
| Equipment Highlight Opacity | Opacity of the compatible equipment-slot treatment. Zero hides that treatment. |

The current placed-fill contract is **display RGB interpolated from `MenuFrame.WELL` to the authored color by its alpha, then drawn opaque**. This intentionally gives the game and the editor preview the same perceived fill. Alpha zero matches the empty well, alpha one displays the authored RGB, and the grain and outline are separate layers. Keep project HDR 2D enabled for unrelated rendering. Grid placement overlays and equipment fit have their own drawing paths. Test those layers separately when changing opacity.

The resource setters emit `changed` and the existing views queue a redraw. Workbench edits a draft so that an unsaved change only affects the draft preview. Workbench refreshes cached resources after Save. A running editor game also checks the authored file on opening an inventory surface and at 0.75-second intervals while it remains visible. A bundled game reads the packaged asset at launch. When diagnosing a report, verify the production asset and values, determine whether the edited controls are the resting or hover state, check the fill away from the item icon and outline, and compare the editor preview with a fresh native game render. Keep the user's resource intact by using an isolated project copy for disk-mutation tests.

## Verification

Run these commands from the project root with the Godot 4.7 editor executable. Replace `godot` with the project's configured binary if it has a different command name. Import a fresh checkout before running scenes or scripts. The inventory model needs the bundled native `SpatialInventory` extension.

```powershell
godot --headless --path . --import
godot --headless --path . --script res://tests/inventory_revision.gd
godot --headless --path . --script res://tests/inventory_supplies.gd
godot --headless --path . --script res://tests/stash_inventory.gd
godot --headless --path . --script res://tests/deck_cards.gd
godot --headless --path . --script res://tests/training_ground.gd
godot --headless --path . --script res://tests/ui_presentation.gd
godot --headless --path . --script res://tests/map_reveal.gd
godot --path . --rendering-method forward_plus --resolution 1280x800 --script res://tests/inventory_appearance_render.gd
```

Choose the affected checks. [Inventory revision](../../tests/inventory_revision.gd) covers click carry, native drag, swaps and cancellation, equipped ownership, identification, physical cards, UI feedback, and item cues. [Supplies](../../tests/inventory_supplies.gd) and [stash](../../tests/stash_inventory.gd) cover their model and session seams. [Card tests](../../tests/deck_cards.gd) and [training tests](../../tests/training_ground.gd) cover campaign/training separation. [UI presentation](../../tests/ui_presentation.gd) checks card shades and content-sized achievement toasts. [Appearance render](../../tests/inventory_appearance_render.gd) needs a native display and samples pixels. Its headless branch deliberately skips rendering.

For visual or input changes, open the affected scene in the editor and run the normal game entry point at normal and compact window sizes. Exercise keyboard focus, Escape recovery, scroll to the last entry, and real pointer hover/drag. In a native HDR pixel check, convert the viewport's linear readback to display RGB before comparing it with an authored color or screen capture. Keep art, borders, and hover out of a resting-fill sample. If a second Godot editor reports locked Windows extension DLLs, use an isolated project copy for mutation tests. Leave a user's open editor and character checkpoints alone.

Update this guide when adding, changing, or removing a UI system, owner, input behavior, authored path, inventory format, or verification command. Update the closest [UI agent guide](../../ui/AGENTS.md) when its routing or obligations change.
