# 0006. Rule-9 hypothesis fields are required on every task

- **Status**: Accepted
- **Date**: 2026-11-10
- **Supersedes**: [0005](0005-rule-9-fields-on-p0-p1-only.md)

## Context

ADR 0005 kept the five fields (`Hypothesis`, `Success`, `Pivot`,
`Measurement`, `Anchor`) mandatory on P0/P1 only, so a quick capture could
land in P2 with only a title. On 2026-11-10 the owner asked that every task
is done with its measurement in mind. Opt-in telemetry and a private
dashboard exist since that day, so a task can name a number that shows its
effect in use. Three P2/P3 tasks had no fields on that day.

## Decision

`make lint-tasks` fails for a task without the five fields at every
priority. `bin/add-task` asks for them at every priority. The shared agent
rules carry the same rule ("Measure every task").

## Consequences

- A quick capture needs the five fields, also from a phone. A capture
  without them fails `make lint-tasks` on the next PR that touches the queue.
- `bin/add-task --priority P2` with only a title exits 2 and names the flags.
- The `rule-9-warn` line is gone: a gap is a failure, not a warning.
- A task that cannot state a measurement becomes a preparation task that
  adds the measurement first.
