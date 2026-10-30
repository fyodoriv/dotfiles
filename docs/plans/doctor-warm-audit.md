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

## Remaining input-lookup cost
The same manual profile is 95 seconds; the original isolated timing test now
passes without a skip. The Git auth snapshot reduced calls but saved only
about 1 second. Profiling 500 production-path override lookups took 8.918 s.
The doctor performs roughly one such lookup for each of 435 check results.

Hypothesis: one read-only override-ID snapshot per doctor process replaces
hundreds of grep processes, retaining exact literal full-line matching and
reducing the 95-second manual profile below 90 seconds. Measurement: new
CLI fixtures compare skipped/evaluated IDs and count grep invocations on the
overrides file, then rerun the same manual profile and original timing test.
Success: identical check selection, zero per-check grep processes, new
invocations see edited overrides, and manual wall time below 90 seconds.
Pivot: any selection difference rejects the snapshot; at or above 90 seconds,
profile the remaining cost before another approach. Anchor: Basili et al.
(1994), Goal Question Metric.
The snapshot lives in one doctor process and ends with that process. Watch
mode's child doctor reloads it each iteration. It never changes the file.

## Measured result before the full gate
The final same-style scratch-user profile reports 76 seconds, down from the
123-second baseline. The intermediate snapshot-only profile was 95 seconds.
The final two profiles report the same 309 pass / 122 fail / 4 skip counts
for their synthetic scratch users; this is timing evidence, not a claim
that the real machine is unhealthy. All 49 targeted tests pass. The original
isolated 90-second regression test also passes without a skip. Independent
review accepted all three snapshots; the unsafe memory shortcut was rejected.
The full repository gate is still required before delivery.

## Gate scheduling experiment

The final parallel gate checked 71 files: 1,162 tests passed and only
`doctor.bats:607` failed its unchanged `<90`-second assertion. The identical
fixture then passed alone without a skip. Peer-suite contention is supported
by that comparison; keep fixture and threshold unchanged when testing it.

- **Hypothesis (GQM):** run `doctor.bats` after the other selected files finish.
  Full-gate timing failures fall from 1 to 0 because the real-machine budget
  no longer competes with up to nine peer files. Scheduler state lasts for
  one Make invocation; existing cache ownership does not change.
- **Measurement:** `heavy-run bats tests/makefile-bats-jobs.bats`, the unchanged
  filtered timing case in `tests/doctor.bats`, and `heavy-run make check`.
- **Success:** 100% of selected files run exactly once, zero peer-file overlap
  with the doctor file, failure exits propagate, the original timing case
  passes without a skip, and zero required full-gate failures. Preserve
  doctor-only selection, selection without doctor, and no-parallel fallback.
- **Pivot:** if the isolated original case takes 90 seconds or more, or any
  selected file is omitted or duplicated, abandon this scheduling approach
  and profile the timed invocation again. Do not widen the time budget.
- **Anchor:** Basili, Caldiera and Rombach (1994), Goal-Question-Metric; Kohavi,
  Tang and Xu (2020), controlled experiment conditions.
