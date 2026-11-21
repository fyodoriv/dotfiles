# Check the scratch cleanup job's startup tool

The scratch cleanup job uses `dirname` at startup to load its
real-time activity check. Reuse the registered LaunchAgent tool
probe so the drift check can find a missing executable before repair.

- **Hypothesis**: The drift check reports a missing `dirname` in
  both report and repair mode without starting the cleanup job.
- **Measurement**: Run hosted
  `bats tests/dotfiles-launchagent-drift.bats` with a scratch plist
  and an inert executable at the registered script path. Check a
  loaded job with an empty PATH directory, an unloaded job in repair
  mode with the same PATH, and a loaded job with an executable
`dirname` stub. Both canaries use a shell built-in so they can record
unexpected execution even when the PATH is empty.
- **Success**: Both missing-tool cases exit 1 and report `dirname`.
  The complete PATH reports one healthy job. The missing-tool cases
  make 0 repair calls, and all 3 cases make 0 job or tool calls and
  expose 0 fixture paths.
- **Pivot**: One missed tool, healthy-job warning, repair with the
  tool absent, or touched canary rejects the check.
- **Anchor**: Startup in `bin/agent-scratch-prune`, its rendered
  plist and the registered probe in `bin/dotfiles-launchagent-drift`.

This step covers only the startup dependency. Tools for conditional
worktree, disk scan and model cleanup need separate path checks.
The four-week LaunchAgent field measurement remains open.

The [hosted baseline](https://github.com/fyodoriv/dotfiles/actions/runs/44888157657/job/136797889165)
failed the missing-tool assertions in report and repair modes.
The healthy PATH passed.
The drift check did not recognize the scratch cleanup job label,
so it skipped the required tool check in both modes.
