# 0005. Rule-9 hypothesis fields are required on P0/P1 only

- **Status**: Accepted
- **Date**: 2026-10-16

## Context

Rule 11 (rule 9 in Minsky terms) requires `Hypothesis`, `Success`, `Pivot`,
`Measurement`, and `Anchor` on P0/P1 tasks, and `make lint-tasks-rule9`
enforces it. The new-project audit asked whether P2 should be covered too.

## Decision

Keep the lint on P0/P1. P2 is the default for `bin/add-task` and the landing
zone for quick captures from the GitHub web UI on a phone. Requiring five
fields there would make the gate fail on every quick capture. A task gets the
fields when it is promoted to P1. All P2 tasks had them on 2026-10-16 anyway.

## Consequences

- `bin/add-task --priority P2` keeps working with only a title.
- `make lint-tasks` prints a `rule-9-warn` line for each P2/P3 task without the
  fields, so gaps stay visible (added 2026-10-16 after the requirements
  grader asked for every task to carry them).
- Moving a task to P1 without the five fields fails `make lint-tasks`.
