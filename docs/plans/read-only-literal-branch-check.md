# Check a literal branch name before starting a worktree task

The command guard refused a branch-name comparison while preparing
[Dotfiles #781](https://github.com/fyodoriv/dotfiles/issues/781).
The tool had received the shell source and had not run it.

- **Hypothesis:** The branch scanner keeps a read-only branch substitution
  in its candidate text and reads a later argument as if it belonged to
  that Git command.
- **Measurement:** Pass the original shell source to the Dotfiles guard
  as JSON. The fixture never executes the supplied command. Compare with
  a short leading literal-branch test, one harmless command after it, and
  later protected command controls.
- **Success:** The original fails on the baseline. The fix admits both
  verified read-only cases and keeps every changed, dynamic, nonleading
  and later destructive control blocked when the original guard blocks it.
- **Pivot:** If the source guard admits the original command, identify the
  installed guard before changing anything. If any existing refusal
  becomes an admission outside the proved leading condition, reject the fix.
- **Anchor:** The earlier [read-only branch preflight](read-only-branch-preflight.md)
  and the false refusal observed in this session.
