# Hook memory load-gate reason prediction

Register before implementation or execution. This changes the private failure
receipt only; it does not qualify any retained measurement.

- **Hypothesis:** A closed reason distinguishes unavailable CPU count from
  excessive load without changing admission or disclosing host values.
- **Measurement:** `heavy-run python3 tests/hook_rss_provenance_test.py` with
  separately planted unavailable-count and excessive-load cases.
- **Success:** Both planted causes receive distinct correct closed reasons;
  both still reject before a timed command, existing admission decisions stay
  unchanged, and zero raw CPU or load values appear in the receipts. A clean
  post-window high-load failure gets the load reason; an earlier sample
  failure keeps its original class, window and index.
- **Pivot:** Keep the existing receipt if a reason is ambiguous, a decision
  changes, or a raw host value leaks. A setup failure is inconclusive.
- **Anchor:** `rust-hook-load-diagnosis`, the private 2026-11-12 receipt, and
  Basili, Caldiera and Rombach (1994), Goal Question Metric.

Preserve the existing load test and thresholds. For its existing early
`class: load` failure, add only a closed `reason` selected from
`cpu-unavailable` and `load-over-limit`; preserve the class, window and index.
`cpu-unavailable` means exactly the existing falsy `not cpus` condition; it
takes precedence if both early conditions hold. The existing post-window
high-load path uses `load-over-limit` only when no earlier failure exists.
Do not record
the actual count, load, process data or path. No timing run is part of this
change. Confirm no active hook-memory retry before changing the receipt code.
The task block currently exists on the migration draft, not the default branch;
remove it from that draft after this fix is merged into its base.

## Focused result

The three new reason assertions failed before the fix, as expected. After the
change all 17 focused tests passed. The planted CPU and load values did not
appear in the serialized receipts; the earlier sample failure retained its
original class and position. Independent review found no changed gate decision.
The migration draft needs its scratch fixtures adapted and its source/audit
provenance renewed after it incorporates this change.
