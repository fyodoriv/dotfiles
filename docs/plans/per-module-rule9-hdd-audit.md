# Plan: per-module-rule9-hdd-audit

## Goal
Make dotfiles enforce rule-9 hypothesis-driven metadata for every P0/P1 task: `Hypothesis`, `Success`, `Pivot`, `Measurement`, and `Anchor` must be present as single-line fields, and `bin/add-task` must require those fields when creating new P0/P1 entries.

## Why
This implements `TASKS.md` P1 `per-module-rule9-hdd-audit` and traces to:
- Vision goal: `VISION.md` G1 — Self-healing > documented manual steps. The task queue is the source of future self-healing work, so high-priority entries need falsifiable success criteria instead of vague prose.
- User story: `docs/user-stories/03-add-and-maintain-config.md` / US-03 — contributors add and maintain config through repo-supported commands and health checks; `docs/user-stories/06-stay-safe-from-damage.md` / US-06 — multi-agent safety needs deterministic gates around shared workflow files.
- Competitor prior art: N/A — this is a repo-local task metadata discipline copied from the sibling Minsky/agentbrew workflow, not a market-facing product feature with a competitor corpus in this repo.
- Anchor: Minsky `vision.md` § 9 "Pre-registered hypothesis-driven development (iron rule)" and Basili/Caldiera/Rombach 1994 Goal-Question-Metric.

## Scope (in)
- Add a deterministic lint path that runs as part of `make lint-tasks` and fails when any P0/P1 task in `TASKS.md` lacks a non-empty single-line `**Hypothesis**`, `**Success**`, `**Pivot**`, `**Measurement**`, or `**Anchor**` field.
- Keep the existing `@tasks-md/lint` invocation; wrap or extend it rather than replacing the upstream linter.
- Extend `bin/add-task` so creating a P0/P1 task requires all five rule-9 fields, supports non-interactive flags for those fields, and writes the fields into the generated task block.
- Sweep existing P0/P1 entries in `TASKS.md` so the new gate is green.
- Update `AGENTS.md` and `CLAUDE.md` task queue guidance with the rule and the verification command.
- Remove the completed task block from `TASKS.md` in the implementation commit.

## Scope (out)
- Do not change P2/P3 task requirements; they may keep lightweight metadata.
- Do not replace the tasks.md linter package or fork its parser.
- Do not introduce a generated/backend migration for this task.
- Do not contact or modify sibling repos. Agentbrew/Minsky cross-links stay textual unless a later task targets those repos.
- Do not rewrite unrelated task prose beyond adding or normalizing the required fields.

## GET-before-IMPLEMENT decision
- GET: Keep using the existing pinned `@tasks-md/lint` for baseline tasks.md shape validation.
- WRAP: Add a small repo-local rule-9 checker after the upstream linter because the required fields are a dotfiles/Minsky constitutional overlay, not a generic tasks.md requirement.
- CONTRIBUTE: Not needed for this task. If the field requirement becomes generic across tasks.md users, file a follow-up against `tasks.md` for custom required metadata schemas.
- ABSORB: The bespoke code is limited to a narrow validator plus `bin/add-task` flag/prompt handling. If it grows past this repo's metadata discipline, file a Replace? Relocate? task for tasks.md or agentbrew.

## Implementation steps
1. Inspect `Makefile`, `bin/add-task`, and existing task-lint tests to identify the narrowest integration seam.
2. Add a RED test in `tests/tasks-lint.bats` proving `make lint-tasks` fails for a fixture P1 task missing one rule-9 field, plus focused coverage in `tests/tasks-rule9-fields.bats`.
3. Implement the minimal rule-9 checker and wire it into `make lint-tasks` after the pinned tasks-md linter.
4. Add a RED `bin/add-task` test proving P1 creation without the five fields is rejected non-interactively, then implement the required flags/prompts.
5. Add `bin/add-task` coverage proving a P1 task with all five fields includes them in the output.
6. Sweep all existing P0/P1 task blocks so each has single-line `Hypothesis`, `Success`, `Pivot`, `Measurement`, and `Anchor` fields.
7. Update `AGENTS.md` and `CLAUDE.md` task queue guidance with the rule-9 requirement and `make lint-tasks` verification command.
8. Remove the completed `per-module-rule9-hdd-audit` task block from `TASKS.md`.
9. Verify with focused Bats, `make lint-tasks`, and `make check`.

## Risks and mitigations
- Risk: a custom parser misreads continuation lines. Mitigation: enforce the explicit task requirement: each required field must be a single line matching `^\s*-?\s*\*\*<Field>\*\*:\s*(.+)$`; multiline values do not count.
- Risk: `make lint-tasks` becomes noisy for lower-priority scout tasks. Mitigation: scope the checker to P0/P1 only.
- Risk: `bin/add-task` gets too many flags. Mitigation: only P0/P1 require the five new values; P2/P3 behavior remains unchanged.
- Risk: existing P0/P1 tasks need honest metrics but not all are naturally measurable. Mitigation: write concrete command-shaped measurements where available; demote only if a task is clearly not P0/P1-worthy.
- Risk: duplicating `AGENTS.md` and `CLAUDE.md` drifts. Mitigation: make identical targeted edits in both files, matching the repo's existing synced-copy pattern.

## Acceptance criteria
- `make lint-tasks` fails on a synthetic P1 task missing any of the five required fields.
- Existing P0/P1 entries in `TASKS.md` pass the new rule-9 gate.
- `bin/add-task --priority P1` refuses to insert without all five fields and can insert a P1 task with all five fields provided.
- `AGENTS.md` and `CLAUDE.md` document the rule plus `make lint-tasks`.
- Focused Bats tests pass.
- `make check` passes.
- The completed `per-module-rule9-hdd-audit` task block is removed from `TASKS.md` in the implementation commit.

## Reviewer verdict
- **Verdict**: approved
- **Reviewer**: reviewer
- **Date**: 2026-06-11
- **Concerns**:
  - None
