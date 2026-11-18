# Preserve the calling mode mask for queued commands

The queue needs private metadata. A wrapped program also needs the file
permissions it would use without the queue. Issue
[#731](https://github.com/fyodoriv/dotfiles/issues/731) reports a mismatch
in managed-file checks. The wrapper currently applies its private mask
before starting the command. The result is independent of why a given
doctor check reports a difference.

- **Hypothesis**: Restoring the incoming mask immediately before the
  command preserves the same generated modes for 022 and 027 in normal,
  exclusive, and verified nested runs. A restrictive caller remains
  restrictive. Queue privacy stays unchanged.
- **Measurement**: On a hosted runner, use
  `bats -f 'caller mask|the state folder is private' tests/heavy-run.bats`.
  Assert normal, exclusive, nested and restricted cases from real mode
  bits on disposable files. Run the tracked queue suite in standard CI.
- **Success**: All four command cases and the existing queue privacy
  control pass. The state directory remains 0700 and its files 0600.
  The command exit status and slot behavior remain as before.
- **Pivot**: Any widened metadata mode, wrong nested mask, unrelated
  directory or job change, or failed required check rejects the patch.
- **Anchor**: Issue #731, the existing queue privacy test, and the
  `umask` before the current Perl controller.

The [hosted baseline](https://github.com/fyodoriv/dotfiles/actions/runs/44327322421)
failed the normal, exclusive and nested caller-mode controls. The
restrictive case and queue privacy control passed. The fix changes only
the mask immediately before starting the command. Scheduler state keeps
its private mask.
