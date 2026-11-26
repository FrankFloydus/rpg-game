# Systems agent guide

Read [Campaign and saves](../docs/agents/campaign-and-saves.md) before changing session, recovery, inventory, deck, progression, or reward behavior. Use [UI and inventory](../docs/agents/ui-and-inventory.md) for interaction and presentation and [Workbench and data](../docs/agents/workbench-and-data.md) for authored defaults and tuning.

- Keep durable character records and temporary practice state with their existing owners. Preserve stable record IDs. Use the existing seed and migration boundaries when a change affects saved reconstruction.
- Commit item identity, occupancy, and any cost together through Inventory. Resolve a result once across failed placement, retry, cancellation, reentry, and reload. Keep the player's current model usable if an attempted restore fails.
- Exercise checkpoint changes through a new scene or model and an isolated save directory. Fixtures must never write to a player's slots.
- For every addition, change, or removal, update the relevant agent guide in the same task. Record changed ownership, public entry points, defaults, compatibility or failure behavior, and the verification command when they apply. Update neighboring guides when a contract crosses directories.
