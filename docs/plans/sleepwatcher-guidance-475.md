# Sleepwatcher doctor guidance experiment

Issue: #475.

## Hypothesis

Goal: let the owner resolve a sleepwatcher LaunchAgent failure. Question:
does the doctor distinguish a missing plist from an unloaded service and give
the owner the matching steps? Metric: actionable guidance for both of 2
isolated failure cases; neither normal nor `--fix` runs the suggested
commands. A loaded service remains passing. The missing-file instruction must
render the actual source template with chezmoi, use the checked checkout even
when its path has spaces, and avoid replacing an existing file.

## Measurement and decision

Run `bats tests/sleepwatcher-doctor-guidance.bats tests/keep-awake-tools.bats`.
Keep only if both cases, the loaded control, output modes, `--fix`, and the
checked-path quoting pass. Pivot away from this approach if either scenario
has no usable action, changes files or services automatically, or mishandles
an existing file. The test uses temporary directories and stub services.

Anchor: Basili, Caldiera, and Rombach (1994), Goal Question Metric.
