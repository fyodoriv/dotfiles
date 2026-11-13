# Scratch helper-selection observation prediction

Register before implementing or running this fixture. Retained timing and RSS
results remain inconclusive. This experiment cannot qualify them.

- **Hypothesis:** A fixed, scratch-only insertion immediately at the bootstrap
  helper-source decision can record a closed selection classification without
  changing observable fixture behavior.
- **Measurement:** `heavy-run bats tests/hook-scratch-selection.bats`, using
  only fixture-owned helper files and scratch roots.
- **Success:** At least six cases cover configured selection, fallback,
  missing helper, stale configured root, symlink and a transform mismatch.
  The unmodified and transformed scratch copies agree on status, stdout,
  stderr, relevant exports and fixed helper marker in every admitted case.
  The private receipt contains at most one bounded closed classification; a
  failed receipt write is surfaced. A transform mismatch refuses before
  execution. A missing helper returns before the insertion: it has no receipt
  or helper marker and is inconclusive, not an admitted selection. An outside
  canary stays unchanged.
- **Pivot:** Stop on any changed observable result, unclassified selection,
  transform mismatch that executes, outside write, or unbounded receipt.
  A setup failure is inconclusive, not a pass.
- **Anchor:** [Effective-input audit](hook-effective-input-audit.md),
  `agent-hooks/bootstrap-endpoint-path.sh`, and Basili, Caldiera and Rombach
  (1994), Goal Question Metric.

Use byte-verified scratch copies of the tracked bootstrap. Insert only fixed
test code at an exact, uniquely matched location; never interpolate arbitrary
commands, use `eval`, add a production opt-in, or alter the real hook. Keep
the same actual fixture path sequentially, restoring and byte-verifying each
copy before invocation, because `BASH_SOURCE` affects fallback and exported
paths. Use fixture-only PATH and HOME, fixed helpers, an isolated
startup environment and an already-open private receipt descriptor. Unknown or
missing selections are explicitly inconclusive. The receipt contains no raw
path, command, environment value or private data.

Independent review must check the transformation, exact source boundary,
fixture ownership, parity assertions and outside-canary protection before
execution. The insertion changes code and can affect state or timing; fixture
parity does not prove deployed behavior, startup or interpreter closure,
continuous identity, or descendant completion. No live hook timing, process
signal, external service or production path is part of this experiment.

## Focused result

All seven scratch cases passed after independent safety review. Both admitted
copies returned zero and matched the recorded output, error output, exports and
helper marker. The missing case had no receipt or marker; a closed receipt
descriptor surfaced failure. The review corrected source-copy verification and
isolated Python startup before the first run. This does not cover arbitrary
nonzero parity, deployed selection, timing or descendant completion.
