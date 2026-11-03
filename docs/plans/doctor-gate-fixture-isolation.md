# Isolate doctor gate fixtures

Predictions committed in 9ed2c71 and a7165ba before fixture or guard edits.
Goal: deterministic doctor-gate evidence and coverage of complete literal
Perl alarm wrappers. Baseline source had one alarm-guard violation; seeded
multiline, morning-code, ignored-handler, and late-handler cases were missed.
A controlled private-HOME reproduction of concurrent doctor log trimming
produced one invalid captured JSON result from two invocations because both
used the same `.log.tmp` path. The brew-skip tests had no private HOME.

1. Give brew-skip fixtures a per-test HOME and load the shared helper to
   scrub inherited shell startup hooks. Do not change production logging.
2. Reset the heavy-run FIFO fixture's inherited alarm handler.
3. Scan complete literal Perl snippets, including line-continued commands.
   Ignore comments rather than all morning test code; exclude only this
   guard's own seeded negative test file and external symlink targets.
4. Keep the scanner bounded: it checks an explicit active handler before the
   each alarm in a literal snippet; it does not interpret variable programs
   or prove control flow. Reject missed seeds before accepting the gate.
5. Measure with `bats tests/perl-alarm.bats tests/heavy-run.bats
   tests/doctor-brew-skip.bats`, then the full `heavy-run make check` gate.
   Success: zero failed assertions. Pivot: any remaining fixture failure
   requires tracing child environment and log writers before production edits.

Metric anchor: Basili, Caldiera, Rombach (1994), Goal Question Metric;
Forsgren, Humble, Kim (2018), stability.

The later default-branch composition added a slot-holder fixture alongside
the original FIFO holder. Its literal alarm also resets SIGALRM before arming
it, as required by the same pre-registered complete-wrapper guard. Preserve
the default branch's one-slot and real-time application pause behavior.
