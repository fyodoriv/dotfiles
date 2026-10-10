# AGENTS.md — Dotfiles Codebase Guide

This file is always loaded, so it stays short. Each section gives the rule and
links to the full text. Read the linked doc before you change that area.

## What This Repo Is

macOS developer dotfiles with self-healing health checks. Chezmoi-based, shell scripts, bats tests. Source dir: `~/apps/dotfiles`.

## Main use cases — first-class AI coding agents

dotfiles, agentbrew, and minsky support **Claude Code, Cursor, and Codex** as equal first-class agents. Every agent-config surface syncs to all three. Long-tail agents are best-effort. A dotfiles feature that touches agent config but works only for Claude Code is a P0 regression. Full text and the test-enforced invariants: [`docs/repo-map.md`](docs/repo-map.md#main-use-cases--first-class-ai-coding-agents).

### Deprecated agents — frozen

Owner decision 2026-10-08: **Windsurf and Devin support was removed** from dotfiles. Doctor modules, configs, shell aliases, and tests for them are gone.

**Augment (Auggie) stays deprecated and frozen** in every tooling repo (dotfiles, agentbrew, minsky, tasks.md, and the org overlays).

- Existing Augment support stays. Do not delete its modules, configs, sync targets, or tests.
- Never implement a fix or a feature for Augment. Do not file tasks for it, and do not fix its failing checks.
- Doctor reports an `augment` module as skipped ("deprecated agent, frozen"). Set `DOTFILES_DEPRECATED_AGENT_CHECKS=1` to run it once for diagnosis.
- If work for a supported agent breaks a frozen agent's existing test, skip that test with a note naming this section. Do not fix the agent.

## agent-browser attach-first policy

Attach to the launchd-owned Chrome for the task. Do not start a new Chrome by default.

| Port | LaunchAgent | Purpose |
|------|-------------|---------|
| `9223` | `com.dotfiles.agent-browser-chrome` | dashboard / general SSO |
| `9224` | `com.dotfiles.debug-chrome` | debug work |
| `9225` | `com.dotfiles.tooling-chrome` | tooling repo work |

- These Chromes are headless and `RunAtLoad` only, never `KeepAlive`. Do not reopen one the operator quit.
- Never `osascript activate` or hide apps. Open your own tab, act only on your tabs, close extra tabs.
- Never set `AGENT_BROWSER_PROFILE` to a launchd-owned profile. For task-local checks use a random debugging port, never `9222`-`9225`.

Full policy: [`docs/agent-browser-policy.md`](docs/agent-browser-policy.md).

## Hook-based enforcement (post-2026-05-27)

agentbrew Claude Code hooks are the primary enforcement (PreToolUse). `bin/gh` and `git-hooks/commit-msg` are the backstop for shells outside Claude Code: the hook warns, the wrapper mutates. `lib/strip-agent-attribution.sh` is the single source of truth for the attribution regex set. The hook list and the reasons the wrappers stay: [`docs/agent-hooks.md`](docs/agent-hooks.md).

## Development

```bash
make lint       # shellcheck all scripts
make lint-tasks # validate TASKS.md queue format
make test       # affected tests only (cached, git-aware)
make test-all   # full bats suite (cached)
make test-force # full suite, no cache
make check      # lint + TASKS.md lint + test (run before committing)
```

Repo layout and data flow: [`docs/repo-map.md`](docs/repo-map.md).

## Rules for Editing

These are the dotfiles constitutional rules: the repo-local projection of
Minsky's `vision.md` constitution and agentbrew's global agent rules. Keep the
rule numbers; other files cite them. Each rule's anchors and gate/status are in
[`docs/constitution.md`](docs/constitution.md#rules-for-editing).

0. **GET, don't IMPLEMENT.** Ask how to GET the outcome before you write a script, lint, module, or workflow: GET, then WRAP, then CONTRIBUTE upstream, and ABSORB only when those are blocked. Pair every new module with a "Replace? Relocate?" task.
1. **Prefer the modern CLI cohort over POSIX defaults** (`fd`, `rg`, `sd`, `xh`, `btm`, `dust`, `procs`, …). Fall back to POSIX only when the tool is missing, in strict `/bin/sh` scripts, or in CI/customer environments.
2. **Quote pip specs and keep command-output debris out of repo root.** Use `pip install 'pkg>=1.2.3'`. Never redirect exploratory output to the repo root.
3. **Never hardcode `$HOME` paths** — use `~`, environment variables, helper resolvers, or chezmoi templates.
4. **Run `make check` before committing.** It is the default gate: shellcheck + TASKS.md lint + affected Bats tests. GitHub Actions are off on `fyodoriv/dotfiles`, so local gates are the gate.
5. **Update README alongside behavior changes** in the same commit.
6. **New modules need `modules/<name>/doctor.sh`.** Doctor modules are auto-discovered.
7. **Brewfile is inlined** in `.chezmoiscripts/run_onchange_brew.sh.tmpl`, not a root `Brewfile`.
8. **Agent config is managed by agentbrew, not dotfiles.** Dotfiles owns `Agentfile.yaml`, the shell environment, git wrappers/hooks, and doctor checks. Edit sources, then run `agentbrew sync`; never hand-edit generated agent config.
9. **Always open a PR by default — never commit straight to a long-running branch.** Use a short-lived feature branch and a squash-merged PR. Never push `main`/`master` directly, never bypass hooks (`--no-verify`), and never `git add -A`/`.`/`-u` in multi-agent worktrees. Minsky's autonomous loop is the only carve-out. **Approved-family standing approval**: in tooling repos under `~/apps/tooling/**`, own repos on `github.com/<owner>/*`, and overlay-declared families, `/ship-it` means verify, commit, push the feature branch, open/update the PR, read CI, and merge once substantive checks are green. In other repos named by the request, `/ship-it` covers feature-branch push/PR/CI and a `--force-with-lease=<ref>:<old-oid>` rebase of a user-owned or current-session branch only. Verify PR author/head owner before admin/bypass PR merges. Never cover plain `--force`, hook bypasses, protected-branch pushes, unrelated branch deletion, secrets, production state, someone else's PR, or out-of-scope cross-workspace publication. After delivery, refresh the canonical checkout, apply tooling config, and confirm `agentbrew status` is clean. Full text: [`docs/constitution.md`](docs/constitution.md#rules-for-editing).

**Visual proof for every PR.** Attach proof to the PR description before handoff or merge: a live-browser screenshot for UI work, a pasted terminal transcript for non-UI work. Never drive AppleScript, keystrokes, or window activation to stage an image. Never commit proof images. If safe proof is blocked, record the blocker and do not call the PR ready.

10. **Prefer user-dir version managers over admin-path installs for dev tools** (uv, fnm, rustup, sdkman, mise). No `#!/usr/bin/env` shebangs in dotfiles executables on a managed endpoint. The per-tool table, Apple Silicon rules, and signing details: [`docs/constitution.md`](docs/constitution.md#rules-for-editing).
11. **Hypothesis-driven metadata for P0/P1 tasks.** P0/P1 tasks need single-line `Hypothesis`, `Success`, `Pivot`, `Measurement`, and `Anchor` fields before work starts.
12. **Proactive healing: observed recurring errors become same-session fixes or tasks.** Fix the class now when local and safe; otherwise file a task with the blocker and unblock path.
13. **Default by default.** Make safe, useful behavior the default. Keep opt-outs narrow and documented.

## Task Queue

Pending work lives in `TASKS.md` in the [tasks.md](https://github.com/tasksmd/tasks.md) shape: `# Tasks`, then `## P0`–`## P3`, checkbox lines with bold metadata labels. P0/P1 tasks need the rule-11 fields. Remove completed tasks entirely in the same commit as the fix. Read `<!-- policy: ... -->` comments before editing. Validate with `make lint-tasks`. Non-trivial tasks need a plan in `docs/plans/<task-id>.md`. Full text: [`docs/constitution.md`](docs/constitution.md#task-queue).

## Agentfile Lifecycle

`Agentfile.yaml` declares this machine's AI-agent setup. `dotfiles apply` merges it with any overlay Agentfile into `~/.config/agentbrew/Agentfile.yaml` and runs `agentbrew sync` on that file. Org-gated MCPs belong in the org overlay Agentfile, never here. Keep entries explicit. After Agentfile changes, run `dotfiles apply`, then `make check`. Never edit generated agent config under `~/.claude/`, `~/.cursor/`, or other agent directories to make a dotfiles change. Full text: [`docs/constitution.md`](docs/constitution.md#agentfile-lifecycle).

## Agent Tool Source Boundaries

Every agent tool has exactly one canonical source repo. Before you create or copy a skill, command, or workflow, find its canonical source in [`docs/repo-map.md`](docs/repo-map.md#agent-tool-source-boundaries) and edit that source.

## Verification Gates

- `make check` is the default gate for code, behavior docs, hooks, doctor modules, and tests.
- `make lint-tasks` is required for `TASKS.md` edits.
- Targeted Bats runs help while iterating; they do not replace `make check` before a commit.
- For `Agentfile.yaml` edits, also run `dotfiles apply`.
- State known pre-existing failures explicitly. No completion claims without fresh command output.

## Ownership Boundary

| Target | Owner | Notes |
|--------|-------|-------|
| `~/.zshrc`, `~/.zshenv`, `~/.gitconfig` | **dotfiles** | Symlinked to `home/*` |
| `~/.config/ghostty/`, `~/.config/starship.toml` | **dotfiles** | Copy-mode via `dot_config/` |
| macOS defaults (Finder, Spotlight, keyboard, etc.) | **dotfiles** | Via `macos*.sh` lifecycle scripts |
| `~/Library/LaunchAgents/com.dotfiles.*` | **dotfiles** | Via `launchagents/` templates |
| `~/.claude/`, `~/.cursor/mcp.json`, agent skills/rules | **agentbrew** | Via `Agentfile.yaml` |
| Orchestrator, personas, pipelines | **minsky** | Separate repo |

**Rule**: Never have both repos write to the same target path.

## Branch policy

- **Canonical repo**: `github.com/fyodoriv/dotfiles` is the canonical home.
- **Canonical branch**: **`feat/chezmoi`** (permanent). It is also the GitHub default branch. All branches and PRs target `feat/chezmoi`. The former `main` branch is retired; do not target it.
- **Normal flow on any machine**: create a short-lived feature branch, run `git push origin <branch>`, open a PR on github.com, and merge it. Run `git pull` on `feat/chezmoi` to get the latest.

## Privacy & security gates

`github.com/fyodoriv/dotfiles` is public. **No @company.example email, no organization identifier outside the configured private-reference gate, and no hardcoded secret may reach github.com.** Nothing rewrites history, so every gate runs before a commit leaves the machine.

- Use a public-safe `user.email` in this repo.
- `git-hooks/pre-commit` blocks private identifiers, secret patterns, and private committer emails.
- `git-hooks/pre-push` blocks private emails and private identifiers in pushed files, lines, and messages. For the owner's public repos it fails closed when the local pattern file is missing or outdated.
- Never set `DOTFILES_ALLOW_GH_PRIVATE_REFS=1` as an agent; only a human who read the text may.
- Base `TASKS.md` stays public-safe: use `PROJ-123`-style tags, never org ticket keys.

Full text: [`docs/privacy-gates.md`](docs/privacy-gates.md). Design: [`SECURITY.md`](SECURITY.md).

## Model Configuration

Each agent keeps its own default model; do not infer a cross-agent change from one agent. Claude Code uses `claude-opus-5-5` with `effortLevel: "xhigh"` in `~/.claude/settings.json`, pinned by dotfiles and agentbrew. Cursor mirrors it as `claude-opus-5-5-xhigh`. Codex and Gemini CLI are carve-outs. Never hand-edit `settings.json`; use `dotfiles-doctor --module claude --fix`. Table, identifier gotchas, per-machine overrides, and debugging: [`docs/model-configuration.md`](docs/model-configuration.md).
