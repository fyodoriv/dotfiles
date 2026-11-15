# Shell inventory interpreter-option correction

Registered before implementation on 2026-11-15. The first scan of 147 tracked
`.sh` files returned 33 embedded candidates. Source review found 24 expressions
or interpreter bodies and nine option tokens. Some jq expressions after those
options were not reported. The review binds every candidate to its Git blob.

**Hypothesis:** Interpreter-aware option handling identifies jq filters after
its flags and does not treat Perl module flags as inline programs. It removes
the nine observed option-token false positives without losing a planted body.

**Measurement:** Hosted tests use real shfmt output and synthetic calls with
jq exit/status and value-taking options, Perl module and inline options, and
unknown or dynamic options. The recorded source review supplies the examples.

**Success:** All nine option-token cases stop being labeled embedded; every
planted inline body is found; unknown forms remain unresolved. **Pivot:** Any
missed planted body or silently accepted ambiguous option rejects the change.

This corrects a discovery candidate layer only. It does not prove a complete
inventory, classify migration states, execute repository source, or remove the
final check's fail-closed requirement.

**Anchor:** `rust-source-inventory` in TASKS.md; the shell candidate source
review; Basili, Caldiera and Rombach 1994 (GQM); Munafò et al. 2017.
