# Stop-hook action guidance

Goal: prevent a time review from deferring unblocked, in-scope speedups. Question: does the existing hook give the same action boundary for a slow turn, a blocked-call turn, and a turn with both? Metric: synthetic cases in `hooks/checks/perf-task-review.test.sh`.

Prediction: all three cases name the observed cause, tell the agent to fix unblocked in-scope work, and defer remaining task filing to user and repository policy. Short turns, bypasses and the stop-loop guard remain silent. No synthetic private canary appears in the output. Measurement: `bash hooks/checks/perf-task-review.test.sh`. Success: 3/3 new contexts and all existing controls pass, with zero canary disclosure. Pivot: abandon this guidance if any context loses its cause, violates task policy, leaks a canary, or changes a guard.

A preliminary local wording probe covered one slow-turn message before this plan. It is not evidence for the three-context prediction.

Anchor: Basili, Caldiera and Rombach, Goal Question Metric Paradigm (1994).
