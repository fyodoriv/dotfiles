# Changelog

## Unreleased

### Added

- **Shared-memory hardening visibility** — the memory doctor delegates
  project-sync freshness and read-only transport compatibility evidence to
  AgentBrew. Dotfiles keeps the daily compatibility shim and does not parse
  Claude memory files or reimplement MCP transport.
- **Pre-push gate covers every public repo** — `git-hooks/pre-push` now gates
  pushes to every repo in `config/public-push-remotes.txt`, not only
  dotfiles and agentbrew. It also checks file names and commit messages of
  each pushed commit, so a private name in a path or message is blocked.
- **Pre-push private-reference gate** — `git-hooks/pre-push` now blocks a push
  when a file changed in the pushed range matches the private-identifier
  pattern. The message lists paths only.
- **Generic debug Chrome** — the port 9224 purpose Chrome is now
  `com.dotfiles.debug-chrome` with profile `~/.agent-browser/debug-profile`.

### Fixed

- **Amphetamine script-error loop** — the agent keepawake manager enables and
  verifies Closed-Display Mode for its own sessions. Rejected AppleScript calls
  are quarantined instead of replayed every five seconds.
- **Agent sleep protection is process-scoped** — Cursor and Claude Code each
  get a manager-owned `caffeinate -ims` child only while they run.
- **Cursor audit hooks run once** — `chezmoi apply` no longer piles up copies
  of the audit hooks in `~/.cursor/hooks.json`. `dotfiles doctor` flags
  duplicates.
- **Doctor warm-run performance** — successful Homebrew bottle signature audits
  are cached for 24 hours. Auto-discovery ignores base repository worktrees.

### Removed

- **Windsurf and Devin support (2026-10-08)** — deleted the `windsurf` and
  `devin` doctor modules, the `windsurf/` config dir, the Devin CLI wrapper
  script, the `dv*`/`tdv*` aliases and `DEVIN_MODEL` export in
  `home/zshrc.ai-tools`, and their tests. Augment (Auggie) stays deprecated
  and frozen.

### Changed

- **One canonical repo** — `github.com/fyodoriv/dotfiles` on `feat/chezmoi` is
  the canonical home. `git-hooks/pre-push` blocks private author and committer
  emails on pushes of dotfiles and agentbrew to github.com.
- **Vendor-neutral endpoint handling** — managed-endpoint behavior is driven by
  `DOTFILES_MANAGED_ENDPOINT` and `DOTFILES_ENDPOINT_AGENT_APPS`. The org
  overlay sets them.

## v3.2.0 — Agent Runtime Reliability

Declarative shared agent memory through AgentBrew, freshness-first repository
learning (`/learn-repos`), process-scoped keepawake and wake recovery, stuck
agent self-healing, ad-hoc signing of Homebrew bottles, uv Pythons and tool
shims for managed Macs, and many new doctor checks.

## v3.1.0 — Adoption Readiness

Hardened for team-wide rollout. Expanded the bats suite substantially, added enterprise features, and documented every adoption path.

### New

- **Enterprise git hooks** — `commit-msg` enforces JIRA ticket references and conventional commit format; `pre-commit` scans for secrets and validates branch naming. Advisory by default (warn, not block), opt-out per-repo via `git config hooks.skipTicketCheck true`
- **Monthly brew audit workflow** — LaunchAgent runs `brew cleanup`, `brew autoremove`, and logs results monthly
- **Network watchdog interval** — configurable via `DOTFILES_NET_CHECK_INTERVAL` (default 300s)
- **Adoption guides** — `docs/onboarding-company.md` (step-by-step for new hires), `docs/forking-guide.md` (how to fork for your team), `docs/faq.md` (common questions), `docs/verify-setup.md`
- **Key rotation docs** — `docs/key-rotation.md` covers age key and SSH key rotation
- **Enterprise secrets labeling** — `home/secrets.example` clearly marks organization-specific vs generic variables
- **Portable timeout** — `morning` script uses POSIX-compatible timeout, works on stock macOS

### Testing

- Expanded bats coverage across the repo (see `make count` for live totals)
- Expanded doctor health checks across modules (see `make count` for live module/check totals)
- New test coverage: `macos.sh` defaults, `lib/apply-defaults.sh`, all doctor modules
- Zero shellcheck warnings

### Fixes

- `fnm` architecture detection on Apple Silicon
- `pipefail` masking in CI matrix builds
- Org-specific Homebrew taps gated behind the configured enterprise host check (no longer errors on personal machines)

---

## v3.0.0 — Chezmoi Migration

Complete rewrite from custom bash framework to [chezmoi](https://www.chezmoi.io/). See `docs/rfc-chezmoi-migration.md` for the full design decision.

### Breaking Changes

- **`install.sh` deleted** — replaced by `chezmoi apply` (or `dotfiles apply`)
- **`lib/utils.sh` deleted** — `link_file()`, backup rotation, archive vault replaced by chezmoi engine
- **`snapshot.sh` deleted** — replaced by `git log` + `chezmoi diff`
- **`revert.sh` deleted** — replaced by `git checkout` + `chezmoi apply`
- **`bootstrap.sh` deleted** — replaced by `chezmoi init --apply`
- **`modules/*/install.sh` deleted** — replaced by `.chezmoiscripts/` lifecycle scripts
- **Per-module `Brewfile` files consolidated** — single root `Brewfile` with profile conditions
- **`description.txt` and `profile.txt` removed** — profile selection via chezmoi prompts in `.chezmoi.yaml.tmpl`

### New

- **Chezmoi manages all files** — symlink mode (`symlink_dot_*.tmpl` → `home/`), copy mode (`dot_*`), private mode (`private_dot_*`), encrypted mode (`encrypted_*.age`)
- **Age encryption** — enterprise SSH config encrypted with age (chezmoi builtin, no external binary)
- **`check_managed()` doctor function** — verifies both symlink and copy-mode files
- **`dotfiles` CLI wrapper** — delegates to chezmoi (`apply`, `diff`, `init`, `update`, `managed`)
- **Chezmoi health section** in `dotfiles doctor` — parses `chezmoi doctor` output
- **Lifecycle scripts** — `run_once_bootstrap.sh`, `run_onchange_brew.sh.tmpl`, `run_onchange_macos.sh.tmpl`, `run_onchange_launchagents.sh.tmpl`

### Deleted

Custom bash removed in large chunks (see git history for line deltas). Legacy install/link/snapshot/revert test files deleted with the old framework.

### Testing (at v3.0.0 launch)

- Bats suite covered chezmoi migration paths (see git tag for historical totals)
- Doctor modules covered the pre-chezmoi layout
- Zero shellcheck warnings

---

## v2.x — Pre-Chezmoi (Historical)

Versions 2.0.0–2.2.0 built the modular architecture (auto-discovered health checks, profile picker, time tracking, LaunchAgents) using a custom bash framework (`install.sh`, `lib/utils.sh`, `link_file()`, per-module Brewfiles). All of that scaffolding was replaced by chezmoi in v3.0.0 — see the v3.0.0 entry above for what was deleted. Full v2.x details are available in git history.
