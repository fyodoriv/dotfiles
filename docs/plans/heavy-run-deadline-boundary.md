# Check the process limit before adding it to heavy-run

Issue #741 asks for an optional command deadline. A test must show which
processes the timeout can stop before it becomes a slot-owner decision.
Use short fixture jobs. Do not signal any process that the fixture did
not start.

- **Hypothesis**: GNU timeout bounds an owned foreground process group,
  preserves a normal exit, and leaves a distinct group untouched. A
  surviving child after its parent exits would disqualify this reuse.
- **Measurement**: On hosted Mac and Linux, run the same wrapper through
  four isolated cases: normal exit status 7, a default-signal command and
  descendant, a TERM-resistant command that needs KILL, and a parent
  which exits on TERM while its descendant ignores TERM. Give the fifth
  case a separate process group as a negative control. Use explicit
  process handles or captured identities, bounded waits, and cleanup.
- **Success**: The normal status stays 7. All three timeout cases leave
  zero active processes in the original command group. The separate
  group remains active until fixture cleanup. Both hosts agree.
- **Pivot**: Any active owned descendant or unrelated signal in any
  case rejects direct timeout reuse for freeing a heavy-run slot. Record
  the case before designing an alternative. Leave the current scheduler
  and idle behavior in place during qualification.
- **Anchor**: [Dotfiles issue #741](https://github.com/fyodoriv/dotfiles/issues/741),
  [GNU timeout](https://www.gnu.org/software/coreutils/manual/html_node/timeout-invocation.html),
  and the existing parent and slot ownership in `bin/heavy-run`.

## Hosted Linux result

The original lookup could not find GNU timeout. The updated lookup
found GNU coreutils 9.7 in the [second run](https://github.com/fyodoriv/dotfiles/actions/runs/44346155414). A short
command returned 7. A normal command and its descendant both stopped
on TERM. For the TERM-resistant primary, Python reported -9 for
the timeout wrapper, which a shell reports as 137. The primary was
no longer active. The separate group was still active after the controls.

The counterexample returned 124 with one of its two group members
still active. The primary command exited on TERM, so GNU timeout
returned before its grace timer could signal the resistant descendant.
The [GNU wait loop](https://github.com/coreutils/coreutils/blob/v9.7/src/timeout.c#L531-L580)
waits for the primary process.
That descendant reached its own fixture deadline. This rejects using
the wrapper alone to release a heavy-run slot. A Mac replay is queued.

## Keep the fixture process group owned through the deadline

- **Hypothesis**: An isolated supervisor stays alive through TERM, so
  the deadline continues to cover the original process group after
  the command it started exits.
- **Measurement**: Run the same synthetic commands on hosted Linux and
  Mac. Use a supervisor in a distinct session. Check all group members
  after TERM and again after its grace interval. Keep a separate
  negative-control group and compare start behavior, exit status, and
  active workers under the same deadline.
- **Success**: A normal command keeps exit 7, the default TERM case returns
  124, the two resistant cases require bounded escalation and return
  137, the owned group has zero active workers at exit in all cases,
  and the separate group remains active.
- **Pivot**: A lost supervisor, reused or uncertain group identity,
  unobserved completion, surviving worker, or unexpected signal rejects
  the prototype. Leave the real scheduler out of this experiment.
- **Anchor**: The hosted wrapper counterexample above and the existing
  slot-parent fork and wait in `bin/heavy-run`.

The [hosted Linux and Mac supervisor controls](https://github.com/fyodoriv/dotfiles/actions/runs/44354733342)
both returned 7 for the short command, 124 for the cooperative group,
and 137 for both resistant cases. All four checks ended with zero
active workers in the owned group. The independent group remained
active after the controls. The fixture starts its signal check once
the workers are ready. It qualifies teardown in the fixture on both hosts. The real
scheduler must still prove the timer starts after admission, behaves
correctly while paused, and retains ownership through a launcher failure.

## Observe the deadline through the real queue

- **Hypothesis**: With one slot, a command can wait longer than its
  configured run limit, then get its full run time. A later ticket
  starts only after the deadline controller has verified group teardown.
- **Measurement**: Run the real heavy-run entry point in a private
  hosted fixture with one slot. Start an owned short holder, then a
  prototype deadline controller, then a successor. Record monotonic
  times at queue submission, job start, deadline, teardown, and
  successor start. Keep the same resistant descendant as the
  primary-exit control.
- **Success**: Time queued exceeds one second. The one-second deadline
  is measured after the controller starts. All owned workers are gone
  before the successor starts. The successor uses the same slot and
  exits zero. Each process belongs to the fixture.
- **Pivot**: A deadline spent in queue, an early successor, a surviving
  worker, an unowned process, or unavailable timing evidence rejects
  the control. This fixture does not change the production scheduler.
- **Anchor**: The Linux and Mac group supervisor controls and the
  slot lifetime in `bin/heavy-run`.

The [hosted admission control](https://github.com/fyodoriv/dotfiles/actions/runs/44356622795)
observed 1.663 seconds in the Linux queue and 1.803 seconds in the Mac
queue. TERM followed 1.000 and 1.062 seconds after the command started,
respectively. On both hosts, the next job acquired the same slot after
all owned workers had stopped. The three jobs exited 0, 137 and 0.


## Check the prototype while the scheduler pauses its group

- **Hypothesis**: When heavy-run pauses the command tree, it also pauses
  a deadline controller placed inside that tree. The deadline can pass
  before the controller sends its first signal.
- **Measurement**: On hosted Linux, start the prototype under the real
  queue with a three-second limit. Launch a uniquely named fixture
  process that triggers the existing real-time pause signal. Observe the
  pause mark and the controller's stopped status. Keep the probe active
  past the deadline. Remove only the fixture process and check teardown.
- **Success**: The controller is stopped before three seconds. It sends
  no deadline signal while paused. After release, the signal timestamp
  exceeds three seconds and all owned workers stop.
- **Pivot**: No pause, unreliable timestamps, an early deadline signal,
  or a surviving worker invalidates the result. A stopped-controller
  result rejects placement inside the paused command tree for a wall
  clock deadline.
- **Anchor**: Temporal admission control above and the process-tree
  pause logic in `bin/heavy-run`.

The [hosted Linux pause control](https://github.com/fyodoriv/dotfiles/actions/runs/44358081478)
stopped the controller at 1.631 seconds. It sent its first TERM at
3.619 seconds, after the probe process exited and the scheduler resumed
the group. All owned workers stopped. A controller inside the stopped
tree cannot enforce a wall clock deadline. The scheduler or another
process outside that tree must own the timer.

## Test loss of the slot launcher

- **Hypothesis**: Killing the exact foreground heavy-run controller releases
  its slot even when the process it started is still active. An ordinary
  control retains the slot until its worker exits.
- **Measurement**: Use the real script in a hosted private temporary queue
  with one slot. A Python worker records its parent identity and stays
  active until a separate fixture release. A queued successor reports
  admission and the worker confirms activity after that report.
  Kill only the fixture controller after checking its identity.
- **Success**: Both hosts admit a successor into the same slot before
  the worker exits after controller loss, and neither host admits it
  early in the ordinary control. All fixture workers stop after release.
- **Pivot**: Refuse any result with uncertain identity, a worker that
  did not acknowledge admission while alive, a missing ordinary control,
  or an unknown cleanup outcome. If the slot remains held in both
  cases, investigate the existing retained lease before changing it.
- **Anchor**: The current heavy-run parent and child fork and wait, and
  the hosted admission and pause results above.

This measures an existing limitation. It installs no watchdog and sends
no signal to a process outside the scratch queue.

## Test a surviving slot owner in the scratch queue

- **Hypothesis**: A separate waiting owner can retain the two inherited
  slot locks until its exact worker exits after launcher loss. The worker
  can still run outside the waiting owner's own pause scope.
- **Measurement**: Add the waiting owner to the scratch copy of heavy-run.
  It must close inherited scheduler gate and leadership handles and wait
  only for its worker. Repeat the ordinary and launcher-loss controls on
  both hosts. Bound the fixture and keep the worker active after the
  launcher dies until the test releases it.
- **Success**: An active worker reports after the controller is gone.
  There are zero early admissions in two cases on each host. The same slot
  starts the successor after worker exit. Both known worker releases finish.
- **Pivot**: Any early successor, missed worker activity, unhealthy
  ordinary case, wrong process ownership, or handle leak rejects the
  candidate. Descendant teardown and group eligibility remain separate.
- **Anchor**: The real Linux launcher-loss job, and the current
  `heavy-run` slot, leadership and child-wait paths.
