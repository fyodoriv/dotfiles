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

The first runner had a non-GNU utility at the generic timeout name.
The [second run](https://github.com/fyodoriv/dotfiles/actions/runs/44346155414)
selected the separate GNU binary and observed coreutils 9.7. A short
command returned 7. A normal command and its descendant both stopped
on TERM. The TERM-resistant primary command stopped on signal 9,
which Python reports as -9 and a shell reports as 137. The separate
group stayed active until fixture cleanup.

The counterexample returned 124 with one of its two group members
still active. The primary command exited on TERM, so GNU timeout
returned before its grace timer could signal the resistant descendant.
That descendant reached its own fixture deadline. This rejects using
the wrapper alone to release a heavy-run slot. A Mac replay is queued.
