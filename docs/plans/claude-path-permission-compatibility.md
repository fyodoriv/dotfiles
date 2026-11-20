# Preserve Claude Bash approvals and the Dotfiles path

Use the installed Claude Code 2.1.312 host in a disposable home. Reuse
the loopback-only scripted provider from the earlier hook-order control.
The provider requests only pwd and echo of PATH. Record counts and whether
the private fixture path came first.

- **Hypothesis**: The current command prefix causes two denials in
  acceptEdits. Moving the path setup to the SessionStart environment file
  lets the same two calls run with Dotfiles first.
- **Measurement**: Run `heavy-run python3 permission-path-probe.py` in
  the scratch fixture. Compare current hooks, neutral PreToolUse with the
  current SessionStart JSON, and neutral PreToolUse with an environment
  file. Check acceptEdits, dontAsk and bypassPermissions for the candidate.
- **Success**: The candidate runs both allowed calls in all three modes.
  Each case has zero permission denials, one path result with the fixture
  directory first, and zero permission decisions from the path hook.
  Default and auto keep their existing PreToolUse responses.
- **Pivot**: Reject any case with 1 or more missing path receipts, denials,
  unexpected commands or network boundary failures. Keep approval decisions
  with Claude. If the host cannot preserve PATH outside a command rewrite,
  document the remaining lookup gap before making a source change.
- **Anchor**: [Claude Code SessionStart environment](https://code.claude.com/docs/en/hooks#persist-environment-variables)
  and the [registered harmless hook control](guard-order-benign-control.md).
