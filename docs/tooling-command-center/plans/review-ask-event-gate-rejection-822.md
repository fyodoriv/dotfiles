# Reviewer event gate: rejected approach

The registered gate oracle returned exit 2. Its temporary report was removed,
so a separate diagnostic was captured at
`/tmp/review-event-gate-diagnostic.log`. The fake cases ran, but the shell
function replaced the outer loop's `mode` variable. As a result, the gate
printed `valid_stock`, `duplicate` and `forged_failed` in place of registered
mode names. The exact six-name oracle did not pass. The rejection threshold
applies; a later diagnostic pass is not a successful registered measurement.

Preserve the uncommitted attempt in the `test/review-ask-event-envelope-822`
worktree. The independent synthetic event-adapter controls passed, but their
gate is unqualified and the adapter is not enabled as a hook. Register a
distinct gate approach before implementing or measuring it. No real event,
review request or message was used.
