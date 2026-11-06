# Amphetamine preference guidance experiment

Issue #475 asks the doctor to name the person and steps for a human-only
finding. A preference diff can fail because values drift or because macOS
blocks the caller from the app container. The doctor currently sends the
person to a second command without describing the possible privacy step.

- **Hypothesis (GQM):** Both synthetic failures remain failures (2 of 2), and
  their guidance includes the diagnostic command, a conditional privacy step,
  and both drift directions (four of four elements rather than three).
- **Measurement:** `heavy-run bats tests/module-resilience.bats`.
- **Success:** Both failure controls and all existing module controls pass.
- **Pivot:** A false pass, a claim that privacy access is always required, a
  missing guidance element, or any regression rejects this approach.
- **Anchor:** Basili, Caldiera and Rombach (1994), Goal Question Metric;
  Munafò et al. (2017), preregistration.

This changes guidance only. It does not determine the cause of a failure,
grant access, or change preferences. The rest of #475 stays open.
