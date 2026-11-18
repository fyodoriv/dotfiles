# Make the bare queue status command read-only

Issue [#741](https://github.com/fyodoriv/dotfiles/issues/741) reports
that `heavy-run status` can wait for the slot it is trying to inspect.
The existing `--status` reads the queue without requesting admission.

- **Hypothesis**: The one-word alias uses the existing read-only path.
  Idle and busy commands return the expected state without new queue
  files. A status command with arguments remains an ordinary program.
- **Measurement**: Use the hosted `bats -f 'bare status' tests/heavy-run.bats`.
  Compare the absent state directory for the idle read and queue entries
  before and after the busy read. Give the read an invalid scheduler
  priority to make the original misrouting fail immediately. Check a
  synthetic program called `status` with its argument.
- **Success**: Three of three controls pass. Zero new tickets or files
  for the reads, and the synthetic program receives its exact argument.
- **Pivot**: A queued status read, missed command argument, or queue
  state change blocks release. Leave idle process termination outside
  this change.
- **Anchor**: Issue #741, current `--status` path, and the existing
  Dotfiles queue fixture.

The [hosted baseline](https://github.com/fyodoriv/dotfiles/actions/runs/44328598305)
returned nonzero for both read cases. A command called status with an
argument ran and received it. The fix sends only the exact one-word
status alias to the existing read-only path.
