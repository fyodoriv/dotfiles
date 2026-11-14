# Hook native dispatch prediction

Registered before changing the dispatch lookup on 2026-11-14. The installed
path measured a 0.698 gate ratio and missed the 0.50 target.

**Hypothesis:** Replace the external symlink lookup with Bash file-identity
checks while retaining the content checksum and fail-closed receipt. This
removes one child process and reduces the installed gate ratio to at most 0.50.

**Measurement:** Hosted `hook-status-fixture` runs the existing safety cases,
exclusive performance gate and paired timing and memory fixture.

**Success:** No changed guard verdicts, corrupt artifacts fall back, missing
receipts block, gate ratio at most 0.50, stable baseline RSS and candidate RSS
at most 1.10. **Pivot:** If the gate remains above 0.50, retain the existing
guard and record the result; do not claim a port or weaken the safety checks.

**Anchor:** `rust-hook-status-experiment.md`; Basili, Caldiera, Rombach 1994;
Munafò et al. 2017.
