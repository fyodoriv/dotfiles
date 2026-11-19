# Bound a heavy-run exclusive wait

- Hypothesis: an exclusive waiter exits with a retry status when its wait exceeds 15 minutes, instead of blocking the queue until the running job ends.
- Measurement: the hosted heavy-run fixture holds a shared slot, observes the holder's elapsed time in status, and uses a five-second exclusive deadline.
- Success: the exclusive waiter exits 75 within the fixture's 15-second outer wait, runs no command, and leaves the holder and following shared job alone.
- Pivot: reject a change that admits overlapping exclusive work, signals a different job, or leaves a blocked ticket after expiry.
- Anchor: task `heavy-run-exclusive-starvation` and the existing exclusive FIFO fixture.

Use the monotonic clock for the wait deadline. Report elapsed run time from the existing owner record. Preserve capacity and memory decisions.

Check the exclusive deadline before and after admission. A busy sequence lock
has the same limit. The hosted test keeps both the original holder and a later
waiter in the same isolated queue while the exclusive request expires.

## Sequence-lock fixture alarm

The default-branch full suite returned status 1 in the literal Perl alarm
check. It expected status 0. The sequence-lock test arms its holder alarm
without first resetting the inherited handler. The guard reports the holder
in `tests/heavy-run.bats`.

Reset the holder's `SIGALRM` to its default before arming it. Predict one
violation before the edit and zero after. Run the alarm guard and the exact
sequence-lock fixture. Success is zero new violations and the existing
exclusive deadline and cleanup assertions still passing. Reject any change
to the scheduler, fixture time limit or guard coverage. Anchor: hosted
default-branch run 44425352422 and the literal alarm reset guard.

### Check the alarm guard before a merge

The affected-test gate passed the preceding pull request. The default
suite caught the missing reset on three verified revisions. The guard
reads all of `bin/`, `lib/` and `tests/`, so a file-only test selection
cannot cover its inputs.

Run the existing alarm guard directly in the pull request job before
`make check`. Predict one visible guard step and zero missed failures
from that guard in the next pull request. Success is all eight alarm
controls passing and the normal affected gate still green. Keep the
default full suite. Reject a change that skips a guard case or removes an
existing check. Anchor: pull request #765 and default runs 44425352422,
44413519464 and 44403049527.
