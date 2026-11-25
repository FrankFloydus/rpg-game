# Hearth Workbench agent guide

Read the [project agent guide](../../AGENTS.md) and [Workbench and runtime data](../../docs/agents/workbench-and-data.md) before changing this addon.

- Register editing routes in [the catalogue](workbench_catalog.gd). Resolve the same source the runtime consumes. Use the native Inspector or an existing custom form when it matches the resource's typed contract.
- Keep drafts and persisted resources distinct, and keep hash conflict detection, owned subresource tracking, validation, cache refresh, and disk readback in [the Workbench window](workbench_window.gd). Preserve stable record IDs and read-only fields.
- Use scene and external resource links for data owned by those files. Treat scene/model previews as inspection. Verify real behavior at the runtime consumer.
- For editable-value changes, exercise the actual editor control, Save Changes, the serialized file, and Reload. Use an isolated copy for destructive test edits. Check a fresh game process where the value is consumed.
- Update [Workbench and runtime data](../../docs/agents/workbench-and-data.md) and any other affected agent docs in the same change when adding, changing, or removing a category, editor, validation rule, source route, preview, or authoring workflow.
