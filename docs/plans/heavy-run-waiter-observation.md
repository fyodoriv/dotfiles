# Observe a live waiter before killing it

## Registered experiment

Goal: make the waiter-death regression observe a genuinely queued process under parallel host work. Question: does an explicit holder-release handshake prevent the victim from completing between observation and SIGKILL? Metric: outcomes from the existing named test with a fixed test-only three-second observation gap.

Hypothesis: replacing the two-second holder with a release handshake reduces premature victim completion from one seeded case to zero. The victim must exit 137 after SIGKILL; the following command must exit 0 and the queue must clear. Keep the existing fifteen-second following-command bound and the helper's sixty-second abandoned-fixture guard. Any early completion, wrong exit, stale ticket or failed required gate rejects the fixture approach. Do not lengthen a timer, skip the assertion or change queue admission.

Anchor: Basili, Caldiera and Rombach (1994), Goal Question Metric; Munafò et al. (2017), preregistration. The injected gap is a controlled scheduling fault, not a speed benchmark or estimated field failure rate.

## Exact measurement

After this prediction is committed, add only a test-specific delay before the existing kill. Keep the original two-second holder for the red run:

```sh
heavy-run env BATS_HEAVY_RUN_WAITER_DELAY=3 bats --filter 'a SIGKILLed waiter does not block the queue' ./tests/heavy-run.bats
```

A dependency, setup or command error is inconclusive. Record the actual premature victim/kill assertion before changing the holder. Then use the existing FIFO holder, keep it held until the victim is killed and reaped, release it before the following command, and require the victim's 137 status. The delay defaults to zero and belongs only to this test invocation. It changes no owner setting or production action.

Run the identical seeded command, then the complete scheduling file and required gate:

```sh
heavy-run bats ./tests/heavy-run.bats
heavy-run make check BATS_JOBS= TEST_FILE_JOBS=
```

Success is zero failed seeded outcomes and zero failed scheduling or required checks. The first observed natural failure was the Phase A full-gate fixture: the victim printed and no longer existed at the kill. That diagnostic is retained separately; it is not a passing experiment or proof of a product queue defect.

## Lifecycle and delivery

The scratch test owns its holder, victim, release file and following command. Cleanup releases only those children. A sixty-second alarm bounds an abandoned holder; it does not replace the explicit release. Restore the default SIGALRM disposition when arming that existing guard, as required by the already registered alarm contract.

Commit this plan before the delay seed or holder edit. Preserve all existing test assertions and the original privacy cases. A full gate failure remains a failure. This common fixture correction can land independently of the Phase A reader; Phase A remains blocked on its own complete green gate.

## Observed results

Prediction `9be5df5` preceded both the delay seed and the holder change.
The seeded timer baseline failed at `kill -KILL`: the victim had already
printed and exited. The same three-second seed passed with the explicit
holder release and required victim status 137. The following command exited
zero, and the queue was empty. All existing scheduling cases passed. The
required full gate also passed on the same source tree. Its retained valid
cache passes and fresh scheduling/docs checks are reported separately in
the delivery evidence; no timing or field-failure rate is inferred.

The completed task block is removed from the queue. This documentation-only
result update still receives the required final gate before delivery.
