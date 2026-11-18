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
