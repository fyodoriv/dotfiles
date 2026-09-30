# Roadmap

> Capability tracker for dotfiles. See [`VISION.md`](VISION.md) for the strategic frame, [`docs/user-stories/`](docs/user-stories/) for per-capability acceptance criteria, and [`TASKS.md`](TASKS.md) for active work.

This file is the root-level milestone summary the `load-project-context` rule expects. Calendar-driven sweeps and quarterly reviews are tracked separately — see the agentbrew-managed shared rules under `~/.config/agentbrew/shared-rules.md`.

## Capability tracker (per user story)

The 10 numbered user stories under [`docs/user-stories/`](docs/user-stories/) are the contract. Status at 2026-05-23:

| US | Capability | Status |
|---|---|---|
| 01 | Fully configured Mac from clean image | ✅ Stable |
| 02 | Start day ready to code | ✅ Stable |
| 03 | Add and maintain config (chezmoi flow, doctor checks) | ✅ Stable |
| 04 | Switch profiles and customize (per-host / per-context layers) | ✅ Stable |
| 05 | Config heals itself (`dotfiles doctor --fix`) | ✅ Stable |
| 06 | Stay safe from damage (no-leak contract, multi-agent git safety) | ✅ Stable — three nested guards |
| 07 | Git workflow helpers | ✅ Stable |
| 08 | Time saved by automation | ✅ Stable — `bin/dotfiles-stats` |
| 09 | Run local models fast (Ollama + qwen3-coder) | 🟡 In progress — watching Ollama PRs #8134, #15980 (speculative decoding for qwen3-coder) |
| 10 | Fork for your company | ✅ Stable — overlay model via `EXTRA_AGENTFILE` |

## Infrastructure tracker

| Capability | Status | Where |
|---|---|---|
| chezmoi-based source-to-target sync | ✅ Stable | `.chezmoi*`, `home/*`, `dot_*` |
| Shell startup < 200ms | ✅ Stable | tracked by `modules/shell-startup/doctor.sh`; regression = P1 |
| bats test suite, cached | ✅ Stable | `make test` (cached, git-aware), `make test-all` (full) |
| `dotfiles-doctor` self-healing audit | ✅ Stable | Modules under `modules/<name>/doctor.sh` |
| Single canonical repo on github.com with pre-push privacy gate | ✅ Stable | `github.com/fyodoriv/dotfiles` on `feat/chezmoi`; `git-hooks/pre-push` |
| `Agentfile.yaml` ↔ agentbrew sync | ✅ Stable | `.chezmoiscripts/run_after_agentbrew-sync.sh` |
| Global git hooks (secret scan + commit-msg) | ✅ Stable | `git-hooks/pre-commit`, `git-hooks/commit-msg`, `git-hooks/pre-push` |
| `EXTRA_AGENTFILE` overlay hook | ✅ Stable | `~/apps/dotfiles-<org>/Agentfile.yaml` rides this |
| Endpoint-policy compliance for python venvs | ✅ Stable | `modules/security/doctor.sh` flags `Python.framework` paths |
| Adoption checklist for fresh contributors | ✅ Stable | [`docs/adoption-checklist.md`](docs/adoption-checklist.md) |
| Team onboarding flow | ✅ Stable | [`docs/team-onboarding.md`](docs/team-onboarding.md) |

## Active focus

The repo is feature-stable for the documented user stories. Current operating mode is **hardening + drift detection**:

1. **Doctor-check coverage on recurring issues.** Every manually-fixed drift becomes a `modules/<name>/doctor.sh` check. The bar is "you should never fix the same thing twice." Tracked in [`TASKS.md`](TASKS.md) (P2 unless the drift is user-visible regularly, then P1).
2. **Local-LLM watch list.** [`docs/local-ai-roadmap.md`](docs/local-ai-roadmap.md) tracks upstream Ollama PRs that would unlock qwen3-coder MLX support and structured tool-call decoding. Reviewed monthly.

## Out-of-scope (won't do)

Per [`VISION.md` § "Non-goals"](VISION.md#non-goals):
- Linux / non-macOS support (forks' problem)
- Other shell ecosystems (fish, nu)
- Becoming a secrets manager (defer to 1Password / age)
- Hosting org-internal tooling (overlay repos like `dotfiles-<org>/` do that)

## Decision log

- **2026-05-13 — Canonical branch is `feat/chezmoi`**. Legacy `main` preserved for history; do not push to it. Rationale + future move-to-`main` plan in [`docs/architecture.md` § "Canonical branch"](docs/architecture.md#canonical-branch-featchezmoi).
- **2026-05-21 — Standing approval for tasksmd.** The `tasksmd/tasks.md` repo gets standing push + merge approval per the global agentbrew rule (see `~/.config/devin/AGENTS.md` § "Standing approvals").
- **2026-05-23 — Canonical doc structure adopted.** The `load-project-context` rule lands, and VISION/ARCHITECTURE/ROADMAP live at repo roots.
- **2026-09-29 — Single canonical home.** `github.com/fyodoriv/dotfiles` is the canonical home, on `feat/chezmoi`. The pre-push hook blocks private emails and private-pattern matches before they reach github.com.

## Where work happens

| Surface | Authoritative file | Cadence |
|---|---|---|
| Open tasks | [`TASKS.md`](TASKS.md) | Continuous |
| User stories | [`docs/user-stories/`](docs/user-stories/) (10 numbered) | New US per shipped capability |
| Architecture | [`ARCHITECTURE.md`](ARCHITECTURE.md) + [`docs/architecture.md`](docs/architecture.md) | Updated in same commit as behavior changes |
| Privacy contract | [`SECURITY.md`](SECURITY.md) | Each new identifier → overlay pattern + bats coverage; each new contributor → public-safe `user.email` |
| Local-LLM upstream watch | [`docs/local-ai-roadmap.md`](docs/local-ai-roadmap.md) | Monthly |
