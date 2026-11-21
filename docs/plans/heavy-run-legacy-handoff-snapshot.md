# Count an older waiter as it takes its slot

The [full Dotfiles check](https://github.com/fyodoriv/dotfiles/actions/runs/44889436624/job/136801811686)
expected the older waiter to write first. The recorded order was
`new`, then `old`. The scheduler can sample slots before the older
waiter takes one, then scan the queue after that waiter drops its ticket.
The order log alone does not show which scheduling pass did that.

- **Hypothesis**: When the gate's older ticket disappears during a
  scheduling pass, an updated slot observation keeps a younger
  waiter out of the occupied slot budget.
- **Measurement**: Run hosted `bats tests/heavy-run.bats`. In a copy
  of the scheduler, pause one pass before it reads live tickets.
  A separate scratch process holds the old ticket and then takes
  the shared lock and numeric slot. It records the owner and drops
  the ticket before the scheduler scans. Keep the slot held until
  the pass completes and collect its wait reason.
- **Success**: The completed pass writes 1 busy reason and starts
  0 younger commands while the numeric slot is held. Once the
  fixture releases the slot, the younger command starts exactly once.
  The original mixed-version FIFO and scheduler gates pass.
- **Pivot**: At least 1 younger start or grant while the slot is held,
  a missing pass or handoff marker, any owner setting change, or a
  scheduling regression rejects the change.
- **Anchor**: The hosted failure, `bin/heavy-run`'s gate and slot
  reads, and the frozen 429 fixture's lock-before-ticket-removal order.

The fixture uses a complete synthetic owner record and real scratch
locks. The frozen 429 source and installed queue are outside this run.
Keep the ordinary mixed-version control as a separate check.

The [hosted reproduction](https://github.com/fyodoriv/dotfiles/actions/runs/44892003832/job/136809660974)
recorded an empty wait reason and grant `s1` while the old slot was
held. The earlier slot sample did not include the completed handoff.
The scheduler now refreshes its slot sample when the gated ticket
disappears, before applying existing reservations. The scratch run
does not qualify a new cutover or change any configured slot limit.
