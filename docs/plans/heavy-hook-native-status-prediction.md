# Heavy-run hook native status experiment

Registered before implementation on 2026-11-15 for `rust-agent-hooks`. The
[hook baseline](rust-hook-baseline-2026-11-11.md) records a 50.090 ms first
A/A baseline for `hook-require-heavy-run`; the cheap after-parser shortcut
missed its 0.50 ratio in the [prior experiment](rust-hook-status-experiment.md#heavy-run-guard-shortcut).

**Hypothesis:** A supervised native path for a narrowly recognized literal
`git status` can preserve the existing Perl parser invocation and failure
behavior while removing enough shell and decoding work to reach a candidate /
base ratio at most 0.50 on the existing hook row. Unknown inputs use the old
hook. This is an experiment, not a completed port.

**Measurement:** Hosted macOS runs the unchanged performance row, paired
status variants, parser failure and missing-tool controls, old/new exit and
output comparisons, all existing heavy-run hook tests, and the plan's memory
and build bounds. Use the real supervised delivery path, not a fixture-only
binary. Preserve raw measurement receipts in hosted artifacts.

**Success:** Gate ratio at most 0.50, all registered parity and safety controls
pass, and memory/build bounds in gate G pass. **Pivot:** A missed ratio or any
changed unsafe decision, parser failure, unavailable measurement, or resource
bound rejects the candidate and retains the existing hook. Do not infer parity
from timing alone.

**Boundary:** Do not skip the Perl parser merely because the command appears
safe: the old hook can fail when that invocation fails. Preserve its effective
program, input, exit status and stderr; require a completion receipt and fall
back or block safely on uncertainty. Avoid changing the hook row's command path.
Do not dispatch this hook to an already installed status-only binary: it can
allow without running Perl. Use a distinct capability and retain the old hook
when that capability is absent. Keep bootstrap and opt-out behavior intact.

**Anchor:** `rust-agent-hooks` and [gate G](rust-migration.md#gate-g); Basili,
Caldiera and Rombach 1994 (GQM); Munafò et al. 2017 (pre-registration).
