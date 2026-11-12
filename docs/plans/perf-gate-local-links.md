# Performance gate: local executable links

Registered before implementation on 2026-11-11.

The live checkout has four ignored executable links that its clean comparison
checkout lacks. Two full gate runs failed both hook rows by 14–19% with no hook
changes. In a separate 20-pair probe of identical source copies, adding those
links increased the paired median by 12.48 ms and 7.73 ms for the two hooks.
The clean-versus-clean gate passed all 20 runs. These results identify a
checkout-state difference; they do not prove a candidate code regression.

- **Hypothesis:** exposing equivalent local executable links to both sides
  removes this false slowdown while preserving detection of real slowdowns.
- **Measurement:** `heavy-run bats tests/perf-gate.bats`, planted link and
  slowdown cases, and 20 exclusive clean comparisons with and without links.
- **Success:** 20 of 20 equal-source comparisons pass in each condition;
  every planted slowdown and unsafe link case fails; no user file changes.
- **Pivot:** any missed slowdown, unsafe write, or failed equal-source run
  stops the approach. Keep the gate strict and redesign the fixture boundary.
- **Anchor:** [measurement contract](rust-migration.md#measurement-contract);
  Basili, Caldiera and Rombach 1994 (GQM).
