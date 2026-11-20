# Check Git before repairing the hourly tooling sync job

Registered on 2026-11-20. Target: `0cc6d828`. Task: `launchagent-drift-launchd-safe-paths`.

- **Hypothesis**: Checking Git on the exact hourly job's rendered PATH raises detection from 0 of 2 to 2 of 2 for an eligible checkout in read and repair mode.
- **Measurement**: Run `bats tests/dotfiles-launchagent-drift.bats` on hosted macOS before and after the fix. Keep the scratch job, launchctl and Git controls. Read only the aggregate findings from the installed command after delivery.
- **Success**: Detect both missing-Git cases and make zero job, tool or repair calls. An available executable, absent checkout, and worktree with a .git file pass their controls. Unsupported argv, HOME and overrides keep repair off. The disabled case remains off. The read-only installed scan adds no false drift.
- **Pivot**: Stop after 1 missed detection, 1 false drift, 1 unsafe repair, 1 executed job or tool, or 1 private path in a diagnostic.
- **Anchor**: The [job template](../../launchagents/com.dotfiles.tooling-sync.plist.tmpl), [hourly sync entry point](../../bin/tooling-sync), and existing [LaunchAgent tool checks](../module-reference.md).

The scope is the managed Bash command with no extra arguments, the rendered
user HOME and the default checkout. It checks Git executable presence only.
Git wrapper delegation, other tools and the four-week field result remain open.
