# Test guidance

Read the [root agent guide](../AGENTS.md) and [engineering and verification](../docs/agents/engineering-and-verification.md) before editing test scripts.

- Tests are Godot SceneTree scripts. From project root, run `godot --headless --path . --script res://tests/<name>.gd` for a headless gameplay fixture. Use the native Forward+ route when the script or acceptance criteria require rendering, GUI input, or pixel sampling.
- Use the normal game or editor entry point where the behavior crosses subsystems. Cover the observed action, result, and failed or repeated cases that could regress. Keep input timing, seeded layouts, and scratch data deterministic where practical.
- Keep test writes in isolated fixture directories. Use fresh mounts for persistence checks. Verify the failure actually reproduces and the final test exercises the fix.
- Inspect the output and assertions in addition to the process exit status. State sample size and renderer when reporting a visual check, simulation or benchmark.
- Update the affected guides when a test is added, changed, moved, or removed. Update the command examples and coverage notes that refer to it.
