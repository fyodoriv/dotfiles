---
schema: vision-v1
version: 1
last_reviewed: 2026-05-23
goals:
  - id: G1
    name: Self-healing > documented manual steps
    description: Every recurring issue becomes a doctor check; docs without an automated check are P2/P3 tasks.
  - id: G2
    name: Agent config is agentbrew's job, not dotfiles'
    description: dotfiles owns shell, git hooks, doctor, Agentfile.yaml. agentbrew owns ~/.claude/, ~/.cursor/, etc.
  - id: G3
    name: Zero-leak public repo
    description: No @company.example identifier, no secret, no organization reference outside the configured private-reference gate ever reaches github.com/fyodoriv/dotfiles.
  - id: G4
    name: Forkable for any org via overlay
    description: EXTRA_AGENTFILE hook lets a company layer its MCP servers / skills / rules without forking the core repo.
non_goals:
  - id: NG1
    name: Not a generic dotfiles framework
    description: macOS + chezmoi + the author's stack only. Linux / fish / nu are forks' problems.
  - id: NG2
    name: Not a secrets manager
    description: Secrets live in op (1Password CLI) and age. dotfiles fetches; never stores.
---

# Vision

> **Self-healing macOS developer dotfiles with a no-leak privacy contract.** Powered by [chezmoi](https://chezmoi.io); shell startup under 200ms; automated tests; per-module doctor checks.

## Problem

A Mac drifts. Settings change by hand, tools update, LaunchAgents die, and
config files get edited in place. Setting up a new Mac takes hours of copied
commands, and the result is never quite the same as the old one. Most dotfile
managers copy files and stop there. They do not notice that the machine is
unhealthy, and they do not fix it.

dotfiles gets a new or drifted Mac to the correct state with the fewest human
steps, and keeps it there with doctor checks that find and fix drift.

## Who it's for

**Primary user: any macOS developer who wants their config to be reproducible and to heal itself.** Clone the repo, run `chezmoi init --source ~/apps/dotfiles --apply`, run `dotfiles doctor --fix`, and you have a fully-configured Mac — Homebrew + casks + tap, macOS defaults across Finder/Spotlight/keyboard, shell with starship + atuin + zoxide + fnm + uv, terminal (Ghostty), git, SSH, launch agents, AI agent tooling, and 21 self-healing module check sets that auto-detect and offer to fix drift.

**Secondary user: any team that wants to fork these dotfiles for their company.** The privacy-and-secrets architecture (see `SECURITY.md`) cleanly separates public-safe content from organization-internal content. The `EXTRA_AGENTFILE` overlay hook lets an org layer its own MCP servers, skills, and rules without forking the core repo. The forking guide is in [`docs/forking-guide.md`](docs/forking-guide.md); an org overlay (for example `~/apps/dotfiles-<org>/`) rides this exact mechanism.

## Strategy: self-healing > documented manual steps

The repo's bet is that **documentation rots; check scripts don't.** Every "you should configure X this way" instruction either becomes a `modules/<name>/doctor.sh` check (which auto-detects drift and offers to fix) or it gets deleted. The doctor checks in `modules/*/doctor.sh` are the source of truth; the docs explain why each check exists (`make count` and `dotfiles doctor --list` show the live set).

Three derived rules:

1. **Every recurring issue earns a doctor check.** If you fixed it manually once, the next person should never have to — wire the detection + fix into a module's `doctor.sh`.
2. **No documented "you should" lines.** If a doc says "you should set X" without an automated check, that's a doctor-check task in [`TASKS.md`](TASKS.md) (P2 or P3 depending on impact).
3. **README drift is a bug.** Every behavior change updates the README in the same commit. The README is the front door; if it's wrong, contributors solve the wrong problem.

## Strategy: agent config is agentbrew's job, not dotfiles'

dotfiles owns the **shell environment, git hooks, doctor checks, and the `Agentfile.yaml` manifest** that tells `agentbrew` what MCP servers / skills / rules the machine should have. dotfiles does NOT own the deployed config under `~/.claude/`, `~/.cursor/`, `~/.config/devin/`, etc. — those are agentbrew-managed. The split keeps each repo's blast radius small. Detail in [`AGENTS.md` § "Agentfile Lifecycle"](AGENTS.md#agentfile-lifecycle) and [`docs/agentbrew-setup.md`](docs/agentbrew-setup.md).

## Strategy: zero-leak public repo

`github.com/fyodoriv/dotfiles` is the only canonical home. Nothing rewrites history. The repo has a **strict no-leak contract**: no `@company.example` email, no configured private identifier outside the configured private-reference gate, no hardcoded secret ever reaches github.com. The contract is enforced by `git-hooks/pre-commit` (secret + identifier + private committer email scan), `git-hooks/pre-push` (blocks private author and committer emails on pushes to github.com), and `bats tests/no-internal-refs.bats` + `oss-readiness-lib.bats`. The private patterns come from the org overlay. Full design in [`SECURITY.md`](SECURITY.md).

Every machine uses the same flow: feature branch, `git push origin <branch>`, PR on github.com, merge. A task can be added from a phone through the github.com web UI, or from any clone with `bin/add-task`.

## Capability frame (per user-story numbering)

User stories under [`docs/user-stories/`](docs/user-stories/) are the contract:

| US | Capability |
|---|---|
| 01 | Fully configured Mac from a clean image |
| 02 | Start day ready to code (shell + agents + workflows) |
| 03 | Add and maintain config (chezmoi flow, doctor checks) |
| 04 | Switch profiles and customize (per-host / per-context layers) |
| 05 | Config heals itself (`dotfiles doctor --fix`) |
| 06 | Stay safe from damage (no-leak contract, multi-agent git safety) |
| 07 | Git workflow helpers (`git-maintain`, `gh-wrapper`, custom hooks) |
| 08 | Time saved by automation (tracked via `bin/dotfiles-stats`) |
| 09 | Run local models fast (Ollama + qwen3-coder; warmup; minsky-aware) |
| 10 | Fork for your company (overlay model, secrets architecture) |

New capabilities earn a new user story; new user stories carry a numeric threshold and an SLI source per the constitution.

## Non-goals

- **Not a generic dotfiles framework.** dotfiles is macOS + chezmoi + the author's stack. Linux support and other shell ecosystems (fish, nu) are forks' problems.
- **Not a secrets manager.** Secrets live in `op` (1Password CLI) and `age`-encrypted files. dotfiles fetches; it never stores.
- **Not an agent config tool.** `agentbrew` owns `~/.claude/`, `~/.cursor/`, etc. dotfiles owns only the `Agentfile.yaml` manifest.
- **Not a system for sharing org-internal tooling.** Org-gated MCPs / skills / scripts live in an overlay repo (e.g. `~/apps/dotfiles-<org>/`) and are loaded via the `EXTRA_AGENTFILE` hook. The litmus test: if a fresh contributor outside the org runs `dotfiles apply`, does the MCP work? If no, it's overlay content.

## Success

Success is measured, not felt. [`docs/metrics.md`](docs/metrics.md) holds every
metric with its goal, pivot, and exact command; `dotfiles metrics --table`
prints them all. The headline ones:

| Metric | Baseline (2026-10-16) | Goal | Pivot | Command |
|---|---|---|---|---|
| North star: scorecard metrics where dotfiles beats the best competitor | 0 of 5 (2026-10-12) | ≥ 2 by 2027-04-30 | 0 on 2027-04-30 | `jq '.north_star.metrics_beaten \| if . == null then error("no value") else . end' ~/.local/state/dotfiles/scorecard.json` (refresh: `scripts/benchmark-run.sh`) |
| Interactive shell startup, median (ms) | 80 | < 200 | ≥ 300 | `for i in 1 2 3 4 5; do /usr/bin/time -p zsh -i -c exit 2>&1 >/dev/null \| awk '/^real/{print int($2*1000)}'; done \| sort -n \| sed -n 3p` |
| Commands a person types on a fresh Mac | 4 | 1 by 2027-01-31 | ≥ 3 on 2027-01-31 | `jq '.dotfiles.metrics.manual_bootstrap_steps \| if . == null then error("no value") else . end' ~/.local/state/dotfiles/scorecard.json` |

## Kill criteria

dotfiles is a set of wrappers around tools that exist without it. Each wrapper
must earn its place against the plain tool. A missed date below means the
wrapper goes, not a new deadline.

- **`dotfiles apply` (wraps chezmoi)**: if the north star is still 0 of 5 on
  2027-04-30, deprecate the wrapper and document plain `chezmoi apply` plus
  `dotfiles doctor`.
- **`bin/dotfiles-install` (wraps a backup, `chezmoi apply`, and the doctor)**:
  if a fresh Mac still needs 3 or more commands on 2027-01-31, delete it and
  document chezmoi's own one-line `init --apply` plus `dotfiles doctor --fix`.
- **`local-ai-warmup` LaunchAgent (wraps Ollama and LM Studio)**: if fewer than
  50% of its health checks find an engine on 2027-01-31, remove the
  LaunchAgent and make story 09 opt-in.
- **The company overlay (story 10)**: if dotfiles has no public forks on
  2027-06-30, fold the overlay docs into one page and stop growing the forking
  guide.
- **Shell config**: if the median shell startup is 300 ms or more at two
  monthly audits in a row, remove the slowest init block (find it with
  `zprof`) before adding anything new.

## Prior art

[`docs/competition/scorecard.md`](docs/competition/scorecard.md) compares
dotfiles with chezmoi, GNU Stow, yadm, dotbot, and home-manager on one shared
workload, with sources for every number. dotfiles is built on chezmoi (GET,
then WRAP, rule 0); the doctor checks, self-repair, macOS settings, and
LaunchAgents are what it adds on top.

## Core beliefs

- **Self-healing beats documented.** Every fixable drift becomes a doctor check; check failures become tasks.
- **Shell startup under 200ms is a hard contract.** Measured by the shell-startup row in [`docs/metrics.md`](docs/metrics.md); regressions are P1.
- **Multi-agent git safety is non-negotiable.** No `git reset --hard`, no `git checkout .`, no `git clean -fd`, no `git add -A` in any script or skill that runs in a multi-agent worktree. The class of bug — wiping another agent's changes — is too costly. Enforced by review and by the `commits-and-ci` rule synced from agentbrew.
- **Privacy is enforced by automation, not by trust.** Three nested guards (pre-commit hook, pre-push hook, bats tests) make leaks impossible by construction. Adding a new identifier or contributor follows the SECURITY.md flow.

## Reversibility

The `EXTRA_AGENTFILE` overlay is reversible by simply not loading it (`unset EXTRA_AGENTFILE`). The doctor checks are advisory — `--fix` is opt-in per check. Nothing dotfiles does to the host system is one-way.
