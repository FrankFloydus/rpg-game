# Authored data agent guide

Read the [project agent guide](../AGENTS.md) and [Workbench and runtime data](../docs/agents/workbench-and-data.md) before changing a schema, catalogue, or tuning resource here.

- Follow the authored resource from its exported property through the actual runtime consumer. Keep one source of truth for each tuning value and use the existing Workbench route when present.
- Preserve persistent IDs, typed serialized values, seeded selection order, and legacy restore paths. When adding or removing a record, check its references in scenes, loot and crafting, saves, and any explicit order list.
- Keep units and eligibility explicit. Verify both the Workbench write path and representative gameplay against the resulting resource. Use scoped seeded checks for balance changes and a prior save for migrations.
- Update [Workbench and runtime data](../docs/agents/workbench-and-data.md) and any other affected agent docs in the same change when adding, changing, or removing a resource, schema contract, data owner, compatibility rule, or tuning workflow.
