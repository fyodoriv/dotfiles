# Current lifecycle reconciliation

Registered before the current-source reconciliation. The historical ledger
stays pinned to its original revision. Its three later lifecycle changes need
source-bound records before they can inform the eventual validator manifest.

- **Hypothesis:** Reopening the three files at commit
  `b44d386373acb7b66e2233703d8d3ff69b667806` can bind each previously
  reviewed relationship to its current source, or mark it unresolved. The
  LaunchAgent file changed again after the previous review; the other two
  file identities match the previous candidate.
- **Measurement:** Compare each file at that commit with candidate
  `94eef660b9d531b401f1f78c7c788101eb3e7bfb` using `git diff` and inspect
  the current source using `git show`. Record Git blob IDs, line ranges,
  source-declared conditions and unresolved boundaries.
- **Success:** Three of three files have current blob IDs and a documented
  relationship or explicit unresolved status; zero historical receipts are
  overwritten and zero source declarations are presented as observed runs.
- **Pivot:** If a current relationship cannot be bound unambiguously, mark it
  unresolved and do not reuse its old classification as current evidence.
- **Anchor:** [source inventory](rust-source-inventory.md),
  [historical range prediction](stale-lifecycle-ranges-prediction.md),
  and Basili, Caldiera and Rombach (1994), Goal Question Metric.

This source review cannot establish runtime selection, ownership, complete
caller coverage, or validator acceptance. It does not modify the scripts.
