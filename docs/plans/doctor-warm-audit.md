# Restore the warm doctor budget

The same scratch-user warm-security then whole-doctor profile took 123 seconds.
Per-module profiling showed VS Code 24 s and memory 28 s. VS Code starts the
extension-list CLI once for each of 17 desired extensions. The memory schema
probe imports heavy upstream storage modules before checking a missing DB.

## Pre-registered experiment
- Hypothesis: one extension-list snapshot per read-only module run reduces
  17 CLI calls to 1 while preserving all extension results. Combined with the
  separately verified AgentBrew missing-DB fast failure, whole-doctor time
  falls from 123 seconds to less than 90 seconds.
- Measurement: `heavy-run bats tests/module-vscode.bats`; the unchanged
  `doctor --quiet completes in under 90 seconds` test; and the existing
  `DOTFILES_DOCTOR_TIMING=1` per-module profile under a scratch HOME after
  warming the security module.
- Success: all extension assertions retained; 1 list invocation per normal
  module run; a second run refreshes its snapshot; fix mode sees newly
  installed extensions; whole-doctor wall time below 90 seconds.
- Pivot: at or above 90 seconds, abandon this two-lever combination as the
  complete remedy and profile the remaining cost. Any lost check rejects
  the implementation regardless of time saved.
- Anchor: Basili, Caldiera, Rombach (1994), Goal Question Metric.

The extension snapshot belongs to one sourced module run, resets each run,
and is not persisted. Fix mode must not reuse stale installed-extension data.
No timing threshold, test skip, or health-check result is relaxed.
