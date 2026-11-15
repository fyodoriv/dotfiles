# Bats test-file inventory records

Registered before implementation on 2026-11-15 for `rust-source-inventory`.
The plan keeps Bats as test tooling and moves tests with each changed slice.
The ledger does not yet account for the tracked Bats test files themselves.

**Hypothesis:** File-level records for tracked regular Bats files account for
the test harness without claiming that their embedded programs, callers, or
port parity are complete.

**Measurement:** Hosted controls compare eligible paths and Git blobs with the
ledger, reject a planted omission, and require the incomplete inventory check
to remain nonzero.

**Success:** 100% of eligible test paths match; duplicate or omitted records
are rejected; no complete source reviews are invented; and the overall check
still fails while discovery is incomplete. **Pivot:** A stale identity,
misclassified path, accepted omission or successful incomplete check rejects
the change.

These file records use the existing test-build-tooling exception. They do not
replace tests for a migrated component, prove test parity, or account for
embedded and generated programs within tests.

**Anchor:** `rust-source-inventory`, the test-build-tooling exception and the
rule that tests follow each slice; Basili, Caldiera and Rombach 1994 (GQM).
