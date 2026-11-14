# Heavy-run hook status shortcut prediction

Registered before implementation on 2026-11-14. The heavy-run hook runs on
each agent shell call. Its existing parser must still run and retain its exit
behavior, including when Perl fails.

**Hypothesis:** After the existing parser succeeds, exit for the exact input
and parsed result `git status`. This removes later grep and segment parsing,
with no changed verdicts, and cuts the registered gate row to at most 0.50.

**Measurement:** Hosted CI runs the existing hook tests and a focused test
covering exact status, appended commands and parser failure; the queued
performance gate compares the unchanged hook entrypoint with the merge base.

**Success:** Zero changed verdicts and no new false permits; the gate ratio
is at most 0.50. **Pivot:** If safety differs or the ratio exceeds 0.50, retain
the current hook and record the result. A failed shortcut does not qualify a
Rust port.

**Anchor:** `rust-agent-hooks` in `TASKS.md`; Basili, Caldiera, Rombach 1994;
Munafò et al. 2017.
