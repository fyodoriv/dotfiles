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
