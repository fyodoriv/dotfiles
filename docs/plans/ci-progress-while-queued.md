# Progress while local checks queue

Date: 2026-11-12

## Prediction

- Hypothesis: A shared rule that distinguishes hosted coverage from local-only checks will keep agents working while a local heavy run waits, without letting them skip required evidence.
- Measurement: `bats tests/agent-artifact-coverage.bats -f 'queued checks'` checks the shared instruction for hosted coverage, pending or failing CI, and local-only checks.
- Success: All three cases are present and the check passes; the rule forbids bypassing the local queue and preserves required gates.
- Pivot: Revise the rule if any of the three cases is missing or the check fails.
- Anchor: `docs/ci-setup.md` documents the hosted gate and its local-only exceptions. `Agentfile.yaml` owns the shared heavy-run rule.
