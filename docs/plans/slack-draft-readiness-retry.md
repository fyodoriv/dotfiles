# Leave room to retry Slack Drafts readiness

[Issue #635](https://github.com/fyodoriv/dotfiles/issues/635) reports a
wait that can stop after one slow probe. The current readiness loop
still gives its first read the entire time left after navigation.
Reserve part of that time for another read.

- **Hypothesis**: One stalled readiness read leaves time for the
  next read and count within the existing command limit.
- **Measurement**: Run hosted `bats tests/slack-draft.bats`. With an
  8-second command budget, stall the first fake readiness read while
  the second responds normally. Count attempted readiness reads,
  displayed matches and any mutation calls.
- **Success**: 2 readiness reads, 1 matching draft, 0 mutation calls
  and an elapsed time under 10 seconds. Existing closed-budget,
  stuck-tab and confirmation cases still pass.
- **Pivot**: 1 lost count, unexpected action, wrong exit status, or
  elapsed period at or above 10 seconds rejects the change.
- **Anchor**: Issue #635 and the [existing readiness deadline](slack-draft-readiness.md).

Use the existing absolute deadline for navigation and later actions.
Only reduce the first readiness read's allowance when more than
three seconds remain. The fixture uses no browser or workspace.

The [hosted baseline](https://github.com/fyodoriv/dotfiles/actions/runs/44874919833/job/136757407009)
made one readiness read and exited 1. The existing outside-Slack,
closed-budget and stalled-view checks passed.
