# Plan: Pre-merge sanity reviewer for the local-AI loop

- **Task**: local-ai-loop-pre-merge-reviewer
- **Repo**: ~/apps/tooling/dotfiles
- **Author**: devin session 2026-06-12
- **Status**: implemented
- **Validated-by**: subagent_explore (plan-reviewer) on 2026-06-12

## Goal

After the local-AI loop closes a task (agent rc=0, `make check` green, block removed, `commit_if_dirty` run), a deterministic reviewer pass verifies that the commit actually contains every file path declared in the task's `**Files**:` field. When the deliverable is missing, the loop refuses the close: it rolls the just-created commit back safely, restores the TASKS.md block, reverts the task's stray work via the existing `revert_uncommitted`, and counts the task as failed instead of completed.

## Why

Observed in PRs #24–#26: qwen3-coder left its `write_file` output untracked, the loop committed only the TASKS.md edit, and the squash-merged PR descriptions claimed test files shipped that did not exist on main (documented in `docs/audits/local-ai-failure-modes.md`, "Loop committed only TASKS.md, not the agent's write_file output"). `commit_if_dirty` now stages untracked work in safe prefixes, but nothing verifies the commit against the task's declared deliverables — a task whose agent produced *nothing* (or wrote to the wrong path, or only edited TASKS.md) still closes as "✓ completed". This is the exact false-closure mode the upcoming overnight-grind harness (`local-ai-loop-overnight-grind`) needs gated before it can merge-or-revert per task autonomously.

## Scope (in)

- Extract the path-token parsing of `_preload_files` into a shared `_files_field_paths(files_field)` helper (comma-split + path-like regex tokens), used by both preload and the reviewer.
- New `reviewer_missing_files(cwd, task, committed)` in `lib/local-ai-loop.py`: parses declared paths from `**Files**:` (globs kept, prose-only entries skipped), compares against `git show --name-only --format= HEAD` when `committed` else the empty set, returns the unmatched declared entries. Matching semantics, each pinned by a test: (a) exact path match; (b) glob entries via `fnmatch` (so `tests/*.bats` matches `tests/new.bats` but NOT `tests/subdir/foo.bats` — fnmatch `*` does not cross `/`); (c) directory entries match one-way: declared `tests/` is satisfied by committed `tests/foo.bats` (committed path starts with entry + `/` or entry ending in `/`), but a declared file is never satisfied by a committed directory-prefix; (d) a declared `TASKS.md` is auto-satisfied (the loop always edits it).
- New `reviewer_reject_close(cwd, task_id, committed)` rollback helper: when `committed`, `git reset --soft HEAD~1` (own just-created, never-pushed commit) then `git restore --staged -- .`; always `git restore --staged -- TASKS.md` defensively; then delegate to the existing `revert_uncommitted` (restores TASKS.md block + removes stray safe-prefix files).
- Wire both into `main()` after `commit_if_dirty`: dump `git show --stat HEAD` as the audit trail, compute missing, and on a non-empty result print a loud `loop: ✗ reviewer:` line, call `reviewer_reject_close`, mark the task failed/skipped (mirrors the existing `make check` failure branch).
- New `tests/local-ai-loop-reviewer.bats` following the `local-ai-loop-commit-staging.bats` importlib harness, with one case per matching rule:
  1. Green path: declared exact path present in HEAD commit → `[]`.
  2. Glob: declared `tests/local-ai-loop-*.bats` satisfied by committed `tests/local-ai-loop-reviewer.bats`; and `tests/*.bats` NOT satisfied by `tests/subdir/foo.bats` (fnmatch does not cross `/`).
  3. Directory one-way: declared `tests/` satisfied by committed `tests/foo.bats`; declared `tests/foo.bats` NOT satisfied by a commit touching only `tests/bar.bats`.
  4. Missing-file regression: declared `tests/foo.bats` absent from HEAD → `["tests/foo.bats"]`.
  5. Empty/prose-only Files field: empty string, absent field, and prose with no path-like tokens each → `[]` (gate passes).
  6. Declared `TASKS.md` auto-satisfied even when the commit contains only TASKS.md.
  7. committed=False with declared files → every declared path missing.
  8. Rollback mechanics: fixture commits a close (TASKS.md block removed + one tracked file modified) while an untracked `tests/new-task.bats` exists; after `reviewer_reject_close`: (a) `git rev-parse HEAD` equals the pre-close commit (one fewer commit in `git log`), (b) the TASKS.md block text is back in the file, (c) `tests/new-task.bats` is deleted, (d) the tracked file's modification is reverted, (e) `git diff --cached` is empty.
- Doc update in the same commit: `docs/audits/local-ai-failure-modes.md` gains the reviewer-gate entry (failure mode → now deterministically gated).

## Scope (out)

- Opening PRs from the loop, queue/CSV summary work — that's `local-ai-loop-overnight-grind`.
- Allowing task metadata to declare generated/renamed outputs (the task's documented Pivot) — only if strict matching proves too strict in practice; file a follow-up then.
- Any change to `commit_if_dirty` staging behavior or `SAFE_PREFIXES`.
- Workspace/multi-repo concerns (`local-ai-loop-cross-repo`).

## GET before IMPLEMENT

- Reuses the loop's own `revert_uncommitted` (multi-agent-safe revert) and `_preload_files` token extraction rather than new parsing; rollback uses stock git plumbing (`reset --soft`, `restore --staged`) already sanctioned by repo git-safety rules. Searched for an existing diff-vs-metadata verifier (`rg -l "name-only" bin lib`, agentbrew hooks manifest) — none covers commit-contents-vs-task-Files; no upstream tool models TASKS.md metadata, so this stays a ~40-line in-repo function.

## Implementation steps

<!-- Current status: specification-complete, implementation NOT yet started.
     This plan is validated pre-implementation per the next-task workflow;
     none of the steps below have been executed at validation time. -->

### Step 1: Failing tests (red)

Add `tests/local-ai-loop-reviewer.bats` with the eight cases above against the not-yet-existing functions. Verify: `bats tests/local-ai-loop-reviewer.bats` fails with function-not-found.

### Step 2: Implement reviewer + rollback (green)

Add `_files_field_paths`, `reviewer_missing_files`, `reviewer_reject_close`; refactor `_preload_files` onto the shared helper; wire the gate + `git show --stat HEAD` dump into `main()`. Verify: `bats tests/local-ai-loop-reviewer.bats tests/local-ai-loop-preload.bats tests/local-ai-loop-commit-staging.bats` exits 0.

### Step 3: Docs + full gate

Update `docs/audits/local-ai-failure-modes.md`; remove the task block from TASKS.md. Verify: `make check` exits 0.

## Risks and mitigations

- **Risk: strict path matching rejects legitimate work** (generated names, renames, prose-y Files fields).
  - Mitigation: glob entries use fnmatch; prose entries without path-like tokens are skipped; directory-prefix entries match contained paths; the task's Pivot (explicit generated-output metadata) is the documented escape hatch and the failure branch prints exactly which entries were unmatched.
- **Risk: `git show --stat` truncates long paths**, so text-matching against it would false-negative.
  - Mitigation: `--stat` output is printed for humans only; the assertion parses `git show --name-only --format= HEAD`.
- **Risk: rolling back the commit interferes with other agents' work in the same checkout.**
  - Mitigation: `reset --soft` only rewinds the branch tip to the pre-task commit created seconds earlier by this same process and never pushed; worktree files are untouched; cleanup then goes through the existing prefix-scoped `revert_uncommitted` (no `reset --hard` / `clean -fd` / `checkout .`).
- **Risk: tasks with empty/absent `**Files**:` would always fail the gate.**
  - Mitigation: empty declared set → reviewer returns no missing entries (gate passes); pinned by the prose-only test case.

## Acceptance criteria

1. With a fixture task declaring `tests/foo.bats` and a HEAD commit lacking it, `reviewer_missing_files` returns `["tests/foo.bats"]` — `bats tests/local-ai-loop-reviewer.bats` (missing-file case) passes.
2. With the declared exact + glob + directory paths present in HEAD per the matching rules above, it returns `[]` — green-path/glob/directory cases pass.
3. `reviewer_reject_close` restores HEAD to the pre-close commit, restores the TASKS.md block, removes the stray safe-prefix file, reverts the tracked modification, and leaves an empty index — rollback case passes.
4. `main()` refuses closure on missing files (failure branch mirrors the `make check` gate) and dumps `git show --stat HEAD` on success — verified by code review of the wiring plus the function-level tests above. The task's "asserts every path … appears in the diff" is implemented against `git show --name-only --format= HEAD` (machine-parseable path list); `git show --stat HEAD` output is printed for the human audit trail only, because `--stat` truncates long paths with `…` and is unsafe to assert against.
5. `make check` exits 0.

## Reviewer verdict

- **Verdict**: approved
- **Reviewer**: subagent_explore (plan-reviewer, cycle 3; cycles 1-2 produced the explicit 8-case test list, one-way directory matching, fnmatch-no-slash rule, TASKS.md auto-satisfy, empty/prose Files split, and the --name-only-vs---stat assertion note)
- **Date**: 2026-06-12
- **Concerns**:
- **Approval rationale** (only if approved):
  - The plan is specification-complete, internally consistent, and sufficient for implementation. The eight test cases are explicitly enumerated with clear matching semantics; the three new functions are precisely scoped; the rollback strategy reuses `reset --soft` + `restore --staged` (sanctioned by repo git-safety rules) and delegates to the existing `revert_uncommitted` for multi-agent safety. Implementation steps follow red-green with explicit verification gates, and the plan aligns with the TASKS.md entry's Acceptance.
