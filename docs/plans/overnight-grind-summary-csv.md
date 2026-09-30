# Plan: Overnight grind sub-task 2 — per-task summary CSV

- **Task**: overnight-grind-summary-csv
- **Repo**: ~/apps/tooling/dotfiles
- **Author**: devin session 2026-06-12
- **Status**: validated
- **Validated-by**: subagent_explore (plan-reviewer, 3 cycles) on 2026-06-12

## Goal

Every task the loop processes — completed or failed at any gate — appends one machine-readable row to `docs/audits/local-ai-loop-runs.csv` (a loop-owned ledger, separate from the agent's 14-column telemetry file): UTC timestamp, task id, source (`tasks-md`|`queue`), outcome (`completed`|`agent-failed`|`check-failed`|`reviewer-failed`), wall seconds, and turn budget. This makes the epic's pre-registered 80%-completion target measurable from the ledger instead of from log archaeology.

## Why

The epic (`local-ai-loop-overnight-grind`) pivots on a number — "An 8h run completes >=80% of seeded P0 tasks" — but today outcomes live only in scrollback. `docs/audits/local-ai-runs.csv` is the telemetry sink for `bin/local-ai-agent --telemetry` and writes 14 columns (`ts,model,outcome,turns,elapsed_s,writes,bashes,verifies,blocked_done,blocked_deny,input_toks,output_toks,median_tps,task` — verified in lib/local-ai-agent.py); the loop's 6-column rows are incompatible with that schema, so mixing writers in one file would corrupt parseability. The loop therefore owns its own ledger, `docs/audits/local-ai-loop-runs.csv`, reusing the established PERSIST_PATHS pattern so commit/revert machinery never touches it.

## Scope (in)

- `lib/local-ai-loop.py`:
  - `record_run_row(repo, task, outcome, wall_seconds, turns)` — appends to `docs/audits/local-ai-loop-runs.csv` under the repo root via the `csv` module; writes the header `timestamp_utc,task_id,source,outcome,wall_seconds,turn_budget` when the file is new/empty; `source` derived from `_queue_file` presence; creates `docs/audits/` if missing; never raises (OSError → warn line, loop continues — ledger loss must not fail a run).
  - `PERSIST_PATHS` in BOTH `commit_if_dirty` and `revert_uncommitted` gain `docs/audits/local-ai-loop-runs.csv` so the ledger survives reverts and is never auto-committed (same contract as the telemetry CSV).
  - `main()` wiring: capture `task_started` after pick; emit one row per processed task at each terminal branch — `agent-failed` (rc != 0), `check-failed` (make check gate), `reviewer-failed` (reviewer gate), `completed` (close path). `--dry-run` records nothing. `turns` = the `estimate_max_turns` budget.
- `tests/local-ai-loop-csv.bats` (new, importlib harness): (1) first row creates the file with the exact header + one well-formed row; (2) second append adds a row without duplicating the header; (3) `queue` source derived from `_queue_file`, failure outcome string recorded verbatim; (4) write failure (read-only dir) warns but returns without raising; (5) `main --dry-run` against a queue fixture leaves no CSV behind; (6) integration: in a tmp git fixture repo (stub `bin/local-ai-agent`, stub `Makefile` with a no-op `check` target, one queue spec whose Files the stub creates), a non-dry-run `main --queue` records a `completed` row, and with the stub exiting 1 records an `agent-failed` row — pinning the terminal-branch wiring for the success + agent-failure branches; the check-failed/reviewer-failed branch wiring is symmetric one-liner code review.
- TASKS.md: remove this sub-task's block; drop its reference from `overnight-grind-branch-per-task`'s `Blocked by` and the parent's chain.
- `docs/local-ai-roadmap.md`: tick the CSV slice off the "Remaining epic slices" note.

## Scope (out)

- Per-task dogfood branches / merge-or-revert / rollback notes (`overnight-grind-branch-per-task` — next slice; its rollback notes will reuse this row format).
- Analyzing/aggregating the CSV (success-rate report belongs to the epic's final acceptance).
- Changing the telemetry rows `bin/local-ai-agent` writes — loop rows use distinct columns; if the column sets collide in practice, the task's pre-registered Pivot (separate runs file) applies in a follow-up.

## GET before IMPLEMENT

- Python stdlib `csv` (no new dependency); reuses the PERSIST_PATHS persisted-ledger pattern — verified both `commit_if_dirty` and `revert_uncommitted` protect the telemetry CSV today, and this slice extends both tuples with the new loop ledger. The agent's telemetry file is NOT reused: its 14-column schema is incompatible with the loop's 6 columns (reviewer cycle-1 finding), so the loop writes its own file by design rather than as a pivot. No upstream runner exposes per-task outcome rows for this loop (minsky's ledger is its own daemon's).

## Implementation steps

<!-- Current status: specification-complete, implementation NOT yet started. -->

### Step 1: Failing tests (red)

Add `tests/local-ai-loop-csv.bats` (6 cases). Verify: fails with function-not-found.

### Step 2: Implement + wire (green)

Add `record_run_row`, wire the four terminal branches + `task_started`. Verify: `bats tests/local-ai-loop-csv.bats tests/local-ai-loop-queue.bats tests/local-ai-loop.bats tests/local-ai-loop-reviewer.bats` exits 0.

### Step 3: Docs + queue + gate

Roadmap tick; TASKS.md removal + blocker updates. Verify: `make check` exits 0.

## Risks and mitigations

- **Risk: CSV write failure aborts a long overnight run.**
  - Mitigation: `record_run_row` catches OSError, prints a `loop: ⚠` line, and returns; pinned by the read-only-dir test case.
- **Risk: two writers, one file (the cycle-1 reviewer finding).**
  - Mitigation: resolved at design level — the loop owns `local-ai-loop-runs.csv`; the agent keeps `local-ai-runs.csv`. The header is written only when the loop's file is new/empty.
- **Risk: double-counting a task that fails then is retried in a later run.**
  - Mitigation: rows are per-attempt by design (timestamped); the epic's success-rate metric is computed per run window, documented in the roadmap note.
- **Risk: outcome strings drift from the branch they label.**
  - Mitigation: outcomes are string literals at each terminal branch with a test pinning the exact vocabulary.

## Acceptance criteria

1. `bats tests/local-ai-loop-csv.bats` exits 0 (all six cases, including the stubbed-agent integration run).
2. `bats tests/local-ai-loop-queue.bats tests/local-ai-loop.bats tests/local-ai-loop-reviewer.bats tests/local-ai-loop-commit-staging.bats` stays green.
3. `make check` exits 0.

## Reviewer verdict

- **Verdict**: approved
- **Reviewer**: subagent_explore (plan-reviewer, cycle 3; cycle 1 forced the separate loop-owned CSV — the agent telemetry's 14-column schema is incompatible with the loop's 6 columns — plus PERSIST_PATHS coverage in both commit_if_dirty and revert_uncommitted and the stubbed-agent integration case; cycle 2 caught a 5-vs-6 case count inconsistency)
- **Date**: 2026-06-12
- **Concerns**:
- **Approval rationale** (only if approved):
  - The design (separate `docs/audits/local-ai-loop-runs.csv`, never-raise append contract, four terminal-branch wirings, dry-run exclusion) is consistent across Scope, Risks, and Acceptance; the six test cases including the stubbed-agent integration run pin the behavior; scope is one-commit-sized.
