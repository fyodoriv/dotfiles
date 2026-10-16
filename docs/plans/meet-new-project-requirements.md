# Plan: meet the new-project requirements

- **Repo**: `tooling/dotfiles`
- **Task**: `meet-new-project-requirements` (P0, TASKS.md)
- **Author**: Claude Code goal session 2026-10-16
- **Status**: in progress
- **Reviewer verdict**: approve with changes (reviewer subagent, 2026-10-16); changes folded in below

## Goal

`bash ~/.claude/skills/new-project/scripts/check-setup.sh . --profile tool`
reaches 100% on `feat/chezmoi` (baseline 2026-10-16: 11/24, 45%). Each area is
met, mapped in `.agents/requirements.yaml` to files that truly meet its intent,
or waived there with a reason. `make check` stays green. Rules:
agentbrew `skill-plugins/workflow/new-project` (`SKILL.md`,
`references/requirements-map.md`, `references/owner-practices.md`).

## Decisions per area

| Area | Decision | Files |
|---|---|---|
| agents | Meet: cut `AGENTS.md` below 10000 bytes | `AGENTS.md` |
| vision | Map: root `VISION.md` gains a dated success metric with goal, pivot, and command, kill criteria per wrapper, and `## Prior art` | `VISION.md` |
| metrics | Map: new `docs/metrics.md` (Metric, Goal, Pivot, Command); scorecard rows gain Goal and Pivot; missing data prints `(stub)`; `bin/dotfiles-metrics` prints the table, gate speed included | `docs/metrics.md`, `docs/competition/scorecard.md`, `bin/dotfiles-metrics` |
| setup | Map: the README's first code block is the one-line install and ends with `dotfiles-doctor`; optional steps warn | `README.md`, `bin/dotfiles-install` |
| user-stories | Map: each story gets `Metric:` (an outcome, test counts only after `Guard:`) and `Tests:` lines; each e2e test names its story ID; `tests/user-stories.bats` fails on drift. US-07 and US-09 use unit bats (accepted push back) | `docs/user-stories/README.md`, `tests/user-stories.bats`, `tests/e2e/` |
| observability | Map: new `docs/observability.md` (Logs, Errors, Health check). Errors go to `~/.local/state/dotfiles/errors.jsonl` with a `story` field and allow-listed string fields; tests turn the log off. Health check is `bin/dotfiles-doctor`; every failing line carries its fix. No external reporter (accepted push back) | `docs/observability.md`, `lib/errors-log.sh`, `bin/dotfiles-doctor` |
| self-improving | Map: `make check` appends per-step durations to `~/.local/state/dotfiles/gate-timings.jsonl` (accepted push back: not `.metrics/`); the speed review lives in `/tooling-checkup`; new `docs/learnings.md` logs predicted vs observed | `Makefile`, `scripts/gate-timed.sh`, `skills/tooling-checkup/SKILL.md`, `docs/learnings.md` |
| decisions | Meet: `docs/decisions/` ADRs from the ROADMAP decision log | `docs/decisions/*.md` |
| secrets | Map: `.gitignore` ignores `.env` and `.env.*`; the pre-commit secret scan blocks tracked secrets. No `.metrics/` dir exists here (timings live in `~/.local/state/dotfiles`) | `.gitignore`, `git-hooks/pre-commit` |
| docs, e2e, checkup, caching, tasks, tool | Already met or mapped | — |

Accepted push back (map or waive, never build): no `scripts/*.sh` aliases for
`bin/` commands; setup may prompt when macOS requires it; no external error
reporter; timings under `~/.local/state/dotfiles`; no hermetic e2e for US-07
and US-09; the speed review lives in `/tooling-checkup`.

## PR order

Each PR adds the map lines it makes true, with a comment that says why.

1. Plan, the two failing tests (`load-sampler` row, AGENTS.md size).
2. Vision and metrics (`VISION.md`, `docs/metrics.md`, scorecard Goal/Pivot).
3. Setup and user stories (README first block, story `Metric:`/`Tests:`, drift check).
4. Observability (`docs/observability.md`, errors log, doctor fix lines).
5. Self-improving (gate timings, `docs/learnings.md`, speed review pointer).
6. Decisions and secrets (ADRs, `.gitignore`, rule-9 lint scope).
7. Fresh-context grader; fix any FAIL; remove the task block; record the audit.

## Reviewer changes (folded in)

- Caching and checkup are re-verified, not assumed: edit one input per gate
  step and confirm the step re-runs; confirm `/tooling-checkup` covers health,
  the cached gate, broken stories, speed, P0s, the monthly audit, and questions.
- The speed review names its cadence (monthly) and reads `gate-timings.jsonl`.
  `docs/learnings.md` is append-only, seeded with predicted vs observed rows.
- Setup: `bin/dotfiles-install` stays idempotent with no `sudo`; a test fails
  when the README's first code block stops ending with `dotfiles-doctor`.
- Stories: the drift test asserts a `Metric:` line that names a
  `docs/metrics.md` row, with test counts only after `Guard:`.
- Observability: the allow-list lives in `lib/errors-log.sh`; tests prove a
  free-text field is dropped and that bats turns the log off.
- Metrics: a test proves `(stub)` prints when a source answers 0 for a missing thing.
- Secrets: say why there is no `.env.example`; extend rule-9 lint to P2 or
  record the exemption.
- New `docs/*.md` files get docs-map rows; run `docs-contract.bats` and
  `user-stories.bats` directly in each PR.

## Risks

- `AGENTS.md` has about 70 bytes of headroom; new rules go into `docs/`.
- `make check` runs only affected bats; run each touched test file directly too.
- The repo is public: run the oss-readiness leak check on every diff.

## Measurement

`bash ~/.claude/skills/new-project/scripts/check-setup.sh . --profile tool`
after every merge; `make check` exit status before every commit.
