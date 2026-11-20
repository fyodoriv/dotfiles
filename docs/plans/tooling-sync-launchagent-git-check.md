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

## Inherited environment controls

Independent review found that the job can inherit a checkout override from
launchd. The same user domain can also provide Bash startup code.

- **Hypothesis**: Reading those two named values without running startup code avoids falsely treating a custom user-domain checkout as absent.
- **Measurement**: Extend the hosted fixture with a user-domain checkout override, an inherited startup path, and a failed read. Keep every returned value in the scratch fixture.
- **Success**: All 3 unverified cases leave repair off and expose 0 environment values. A read-only report with an inherited startup path still checks the rendered plan.
- **Pivot**: Any unintended repair, environment disclosure, or startup execution rejects the candidate.
- **Anchor**: `tooling-sync` reads `TOOLING_ROOT` from its environment. The rendered plan remains separate from shell startup.

## Detect an inherited value made of line endings

- **Hypothesis**: Counting the query's output bytes preserves a value made entirely of line endings.
- **Measurement**: Reuse the inherited-setting fixture with a one-line-ending value and check its repair trace. Confirm the native launchd query returns zero bytes for an unset key.
- **Success**: The fixture reports 1 unverified job, makes 0 repair calls and prints 0 private values. The unset native query returns status 0 and zero bytes.
- **Pivot**: A missed nonempty value or a native unset key with output rejects this check.
- **Anchor**: Bash removes trailing newlines from command substitution.
