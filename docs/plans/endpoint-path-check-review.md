# Preserve common PATH checks

Goal: keep the endpoint-only warnings quiet on an unmanaged Mac while
retaining common zsh checks. Review of #401 found its broad gate also hides
three zsh checks. Prediction committed in TASKS.md as 35429fc before tests.

1. Apply the original contribution from #401 without rewriting its branch.
2. Register actual PATH checks with a recording advisory handler. With
   endpoint hardening off, require four zsh IDs and no bash IDs. With it on,
   require four of each. Measurement:
   `bats tests/endpoint-bootstrap-check-gate.bats`.
3. Scope each bash gate separately so interleaved zsh checks remain visible.
   Keep the original publisher and Homebrew-sandbox gates.
4. Run `heavy-run make check` and independent review before delivery.

Success: zero failed assertions and the exact counts above. Pivot: if any
check set differs, abandon the broad block approach and inspect boundaries.
GQM anchor: Basili, Caldiera, Rombach (1994). Each declaration test records
registration only; it does not execute host probes or change the machine.
