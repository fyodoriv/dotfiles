# Plan: Overnight grind sub-task 1 — `--queue tasks-queue/` reader

- **Task**: overnight-grind-queue-reader
- **Repo**: ~/apps/tooling/dotfiles
- **Author**: devin session 2026-06-12
- **Status**: implemented
- **Validated-by**: subagent_explore (plan-reviewer) on 2026-06-12

## Goal

`./bin/local-ai-loop --queue tasks-queue/` drives the loop from a directory of one-task-per-file specs instead of the repo's TASKS.md: specs are parsed with the existing task parser, picked in lexical filename order, filtered by the existing `pickable()` rules, and a successfully closed queue task deletes its spec file (the queue-dir analogue of removing a TASKS.md block). This is the first one-commit-sized slice of the `local-ai-loop-overnight-grind` epic — branch-per-task and the summary CSV are follow-up sub-tasks.

## Why

Today the loop runs one TASKS.md task at a time (`--max-tasks 1`, observed in the 3 P0 dogfood runs); an unattended multi-hour grind needs a pre-seeded queue the operator curates ahead of time, isolated from the live TASKS.md so a long run can't race other agents editing the queue file. The epic's pre-registered Measurement starts with exactly this flag: "`./bin/local-ai-loop --queue tasks-queue/` writes one summary CSV row per task" — the reader is the prerequisite for the CSV and branch-per-task slices.

## Scope (in)

- `lib/local-ai-loop.py`:
  - `read_queue_dir(dir)` — for each `*.md` in lexical order, parse with the existing `read_tasks`; when a spec lacks a `## P*` section header, re-parse with a `## P0\n` prefix (tolerant hand-written specs); attach `_queue_file` (absolute path) to each task; missing/empty dir → `[]`.
  - `main()` gains `--queue DIR`: candidates come from `read_queue_dir` instead of `read_tasks(TASKS.md)`; the TASKS.md existence check is skipped in queue mode; on successful close, `close_queue_task(task)` deletes the spec file instead of `remove_task_block` + `git add TASKS.md` (specs are run-state, not repo content); dry-run prints the queue source.
- `bin/local-ai-loop` usage header documents `--queue tasks-queue/`.
- `tests/local-ai-loop-queue.bats` (new, importlib harness like `local-ai-loop-commit-staging.bats`): (1) lexical order + `_queue_file` set; (2) missing and empty dir → `[]`; (3) headerless spec parsed via the P0-prefix fallback; (4) spec with a `manual`-tagged task is excluded by the existing `pickable()`; (5) `close_queue_task` deletes the spec file; (6) `main --dry-run --queue <fixture>` picks the queue task (not the repo TASKS.md) and exits 0.
- TASKS.md: decomposition of the epic — 3 sub-tasks with `**Parent**: local-ai-loop-overnight-grind`; the parent gains `**Blocked by**:` on the three children; this sub-task's block is removed when the PR ships.
- `docs/local-ai-roadmap.md` run-mode note: `--queue` exists, CSV + branch-per-task pending (the epic's Acceptance doc target).

## Scope (out)

- Summary CSV rows (`overnight-grind-summary-csv`) and per-task dogfood branches / merge-or-revert / PR-opening (`overnight-grind-branch-per-task`) — follow-up sub-tasks created in the same decomposition.
- Tracking `tasks-queue/` in git or .gitignore policy for it — specs are ephemeral run inputs; a scout note covers ignoring the dir if it ever shows up in `git status`.
- Any change to the reviewer gate, `commit_if_dirty`, or `revert_uncommitted`.

## GET before IMPLEMENT

- Reuses the in-repo task parser (`read_tasks`), picker (`pickable`), and close pipeline — no new format, no new scheduler. Searched for an existing queue-dir runner: minsky's daemon owns multi-repo orchestration but drives cloud agents and its own task sources (`.minsky/repo.yaml` task_source), not the local-only qwen loop; `tasks` CLI has no execution mode. The loop remains the documented thin, local-only alternative (bin header), so the flag lands here.

## Implementation steps

<!-- Current status: specification-complete, implementation NOT yet started. -->

### Step 1: Decomposition + failing tests (red)

Commit the epic decomposition (`chore: decompose local-ai-loop-overnight-grind into sub-tasks`), then add `tests/local-ai-loop-queue.bats`. Verify: the new bats file fails (functions missing).

### Step 2: Implement reader + wiring (green)

Add `read_queue_dir`, `close_queue_task`, `--queue` argparse + main wiring, bin usage line. Verify: `bats tests/local-ai-loop-queue.bats tests/local-ai-loop.bats tests/local-ai-loop-reviewer.bats` exits 0.

### Step 3: Docs + queue + gate

Roadmap note; remove this sub-task's block. Verify: `make check` exits 0.

## Risks and mitigations

- **Risk: queue mode silently falls back to TASKS.md** (the epic's false-closure analogue).
  - Mitigation: queue mode never touches `read_tasks(tasks_md)`; the dry-run integration test pins that the picked id comes from the fixture spec, not the repo queue.
- **Risk: spec files with multiple blocks or extra prose confuse close/delete semantics.**
  - Mitigation: the reader takes every parsed task but `_queue_file` deletion happens only after the loop's full close gates (make check + reviewer) pass for the LAST task of that file in flight; v1 documents one-task-per-file as the contract (bin header + roadmap) and the tests pin single-block specs. Multi-block files degrade gracefully: each task carries the same `_queue_file`; deletion occurs on first success — acceptable for v1 and called out in the roadmap note.
- **Risk: deleting a spec file the operator still wanted** (failed-then-skipped tasks).
  - Mitigation: deletion happens only on the success path (same gates as a TASKS.md block removal); failures leave the spec in place for the next run.
- **Risk: headerless-spec fallback mis-prioritizes.**
  - Mitigation: fallback assigns P0 explicitly (queue files are operator-curated P0 work by the epic's definition) and the test pins it.

## Acceptance criteria

1. `bats tests/local-ai-loop-queue.bats` exits 0 (all six cases above).
2. `bats tests/local-ai-loop.bats tests/local-ai-loop-reviewer.bats tests/local-ai-loop-commit-staging.bats` stays green (no regression to TASKS.md mode).
3. `./bin/local-ai-loop --dry-run --queue <fixture-dir>` exits 0 and names the fixture task id (manual smoke + pinned by test 6).
4. `make check` exits 0.

## Reviewer verdict

- **Verdict**: approved
- **Reviewer**: subagent_explore (plan-reviewer)
- **Date**: 2026-06-12
- **Concerns**:
- **Approval rationale** (only if approved):
  - The plan is well-structured and consistent with the parent epic's pre-registered Measurement. Queue semantics are sound: parse-with-read_tasks + P0-prefix fallback, lexical order, pickable() filtering, and spec-file deletion only on the fully-gated success path (make check + reviewer). The six planned test cases are sufficient; all close-path interactions are correctly handled (TASKS.md existence check skipped, remove_task_block + git add TASKS.md skipped, close_queue_task fires after all gates, reviewer gate still applies). Risks adequately cover multi-block specs and failure-mode file preservation; scope is one-commit-sized.
