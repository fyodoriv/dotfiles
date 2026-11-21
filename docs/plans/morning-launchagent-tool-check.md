# Check the morning LaunchAgent's startup tools

The morning job uses its rendered launchd PATH for shell utilities.
A missing temporary-file or disk-report tool can stop the job. Reuse
the existing drift check to test executable paths before repair.

- **Hypothesis**: The drift check reports each missing required
  startup or disk-report utility without executing the job or a tool.
- **Measurement**: Run hosted
  `bats tests/dotfiles-launchagent-drift.bats`. Use a scratch rendered
  morning job and remove each of `dirname`, `mktemp`, `rm`, `tail`,
  `date`, `df`, and `awk` in turn. Check repair mode for a missing
  `mktemp` and report mode with all seven tools in place.
- **Success**: 7 missing-tool reports that name the correct utility,
  0 launchctl repair calls with the required utility missing, 0 tool or
  job executions, and 1 healthy report with the complete PATH.
- **Pivot**: One missed tool, false drift on the healthy job, unsafe
  repair call, or tool or job execution rejects the check.
- **Anchor**: The required commands in `bin/morning`, its rendered
  plist template, and the existing registered-tool probe.

This step covers the unconditional tools for startup, temporary-file
cleanup, the date, and the disk report. Calendar and update programs
have their own availability checks. Git is used only when a checkout
is present and is outside this fixture's oracle.
