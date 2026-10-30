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

## Pivot after independent review
The memory shortcut was rejected: upstream import-time dotenv loading can
select a healthy database that the shortcut would not see. Its 1,889 ms
result is not an accepted speedup and will not ship.

The VS Code snapshot measured 24 to 4 seconds. The next lever is a separate
GitHub auth snapshot: read-only audits currently run gh auth status once for
auth and again for each scope. Hypothesis: 4 or 7 probes become 1 per module
run while auth exit-code and per-scope output checks stay unchanged; fix mode
keeps fresh probes. Expected Git module time: 13 to about 4 seconds. Together,
the estimate is 123 to about 94 seconds, which is not yet a completed remedy.
Measurement: targeted Git module tests with CLI call counters, re-source and
fix-mode cases, followed by the same whole-doctor profile. Success: exactly
1 read-only probe, unchanged results and fresh later module runs. Pivot: any
semantic difference or unchanged call count rejects this snapshot; a whole
run at or above 90 seconds requires another measured lever before merge.
Anchor: Basili, Caldiera, Rombach (1994), Goal Question Metric.
