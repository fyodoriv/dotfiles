# Doctor override CI diagnostic

Registered before changing the fixture on 2026-11-11.

The hosted test `a per-machine override skips its check in a doctor run`
failed twice at the exit-status assertion. The doctor output was hidden.
The same case passed ten times on the candidate and ten on the base locally.
The cause is unknown.

- **Hypothesis:** printing the synthetic doctor's status and output only on
  failure will expose the failing boundary without changing the test verdict.
- **Measurement:** a planted failing fixture must print its diagnostic and
  exit nonzero; the unmodified fixture must pass locally. The hosted rerun
  supplies the missing evidence if the failure recurs.
- **Success:** 1/1 planted failure has a diagnostic; 1/1 normal local case
  passes; no credentials or real user data appear in the diagnostic.
- **Pivot:** if output is unsafe or does not identify the boundary, remove
  the diagnostic and design a closed, content-free failure receipt instead.
- **Anchor:** Basili, Caldiera and Rombach 1994 (GQM); Munafò et al. 2017
  (pre-registration).
