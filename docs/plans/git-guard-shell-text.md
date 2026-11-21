# Git guard shell text

Keep the destructive-command checks while excluding inert document bodies.
Prediction committed in 1509a41 before the reproduction: one prose false
positive falls to zero, with no lost safety cases. The custom scanner failed
three executable-input cases in independent review and was abandoned. The
replacement prediction in 754a0db preceded implementation with the established
shfmt parser. Measure with the two agent-hooks-block-dangerous-git bats files.
Any missed executable input abandons the replacement. Anchor: Basili,
Caldiera, Rombach (1994), GQM.

The read-only verbose branch listing already passed on the current base.
The quoted heredoc reproduction failed. Use shfmt's typed syntax tree to
recognize a single plain cat invocation with wholly quoted literal bodies.
Reject shells, pipelines, arithmetic, assignments and extra commands. Permit
only ordinary literal document destinations, excluding links and special
files. Clear literal values through the syntax tree printer, without slicing
source offsets. Missing parsers and unsupported syntax retain the original
input. The syntax tree and proof belong to one hook invocation. Process exit
releases them. No disk state is written by the guard.

The hook deployment links its helper in the same directory. Regression
fixtures cover comments, here-strings, nested quotes, unquoted substitutions,
multiple heredocs, and executable code after the terminator. Existing
branch-proof tests must remain green. Test commands are strings sent to the
guard, never executed as destructive git operations.

## Preserve a quoted GitHub issue body

- **Hypothesis**: The Git guard can ignore destructive-command words
  in a quoted body passed to one direct GitHub issue create operation.
- **Measurement**: Run hosted `bats tests/agent-hooks-block-dangerous-git.bats`.
  Submit separate short and long body flags and an inline long flag.
  Verify that command substitution and an additional destructive Git
  statement still refuse. The fixture never runs the supplied input.
- **Success**: Allow the 3 literal body forms and retain both refusals
  and the existing quoted heredoc and branch controls. Run 0 supplied
  invocations.
- **Pivot**: At least 1 ignored executable segment, 1 refused literal
  case, or 1 existing guard regression rejects the change.
- **Anchor**: [Dotfiles issue #761](https://github.com/fyodoriv/dotfiles/issues/761)
  and the existing typed shell proof above.

Qualify literal body text only when the parser identifies one direct
call. Preserve the original guard for missing parsers, unsupported
structures and any executable part of a body argument.
