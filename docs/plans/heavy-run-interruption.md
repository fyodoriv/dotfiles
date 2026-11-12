# Queued interruption investigation

Registered before the fixture on 2026-11-11. One earlier queued check returned
130 while a later process had the same log open. Two invocations used that
log, so their identities cannot be linked and the cause is unknown.

A caller dying is not the same as a waiter receiving SIGINT. The documented
queue keeps an orphan when its output goes to a file. An explicitly signaled
waiter is expected to remove its own ticket and exit 130 even with file output.
The existing tests cover the two rules separately, but do not combine file
output, SIGINT, and a post-release check.

Hypothesis: in an isolated one-slot queue, 20 owned waiters explicitly sent
SIGINT retire before starting and cannot run after the holder releases.

Measurement: extend `tests/heavy-run.bats` using its private queue and existing
fixture holder. For each of 20 trials use a distinct private log and output
marker, wait until the owned waiter is queued, signal only its direct child
identity, wait for exit 130, and verify the queue is empty. Release the owned
holder, wait for it, and check that no cancelled marker was created. Hosted CI
runs the affected suite. Never inspect, pause, or signal the live queue or an
unowned process.

Success: 20/20 signaled waiters exit 130 and leave the queue; zero cancelled
commands start after release; no unrelated process is signaled. Pivot: any
uncertain identity, live-queue access, stale ticket or started command stops
the experiment. Preserve the original observation as inconclusive. Do not
change orphan retention or infer a production bug from this fixture alone.

Anchor: `heavy-run-interrupted-caller-cleanup`, existing orphan and signal
controls in `tests/heavy-run.bats`; Basili, Caldiera and Rombach 1994 (GQM);
Munafò et al. 2017 (pre-registration).
