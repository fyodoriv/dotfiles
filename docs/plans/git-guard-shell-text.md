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
