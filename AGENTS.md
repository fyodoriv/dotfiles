# AGENTS.md — dotfiles agent guide

This file is always loaded, so it is a router, not a manual. Read it, then open
only the doc the routing table names. Do not read the README end to end.

## Start here

- **What**: macOS developer dotfiles with self-healing doctor checks. chezmoi, shell scripts, bats tests.
- **Who**: the owner's Macs and team forks. Claude Code, Cursor, and Codex are equal first-class agents ([docs/repo-map.md](docs/repo-map.md#main-use-cases--first-class-ai-coding-agents)).
- **Where**: `github.com/fyodoriv/dotfiles`, branch **`feat/chezmoi`** (canonical and default; `main` is retired). Public repo.
- **Docs map**: [docs/README.md](docs/README.md). Rule full text: [docs/constitution.md](docs/constitution.md).

## Commands

| Task | Command (from the repo root) |
|---|---|
| Default gate before a commit | `make check` (shellcheck + TASKS.md lint + affected bats) |
| One test file / one test | `bats tests/<name>.bats` / `bats -f '<test name>' tests/<name>.bats` |
| Tests affected by a committed branch | `bin/bats-affected origin/feat/chezmoi \| xargs bats` |
| Full suite (slow; run in the background) | `make test-all` |
| Lint only / TASKS.md only | `make lint` / `make lint-tasks` |
| Review the task queue (truth, usefulness, priority) | `/review-tasks` (tasks.md command, installed by the Agentfile) |
| Apply to this Mac | `dotfiles apply` (needed after `Agentfile.yaml` edits) |
| Check one module | `dotfiles doctor --module <name>` |

### Verification gates

`make check` covers code, behavior docs, hooks, doctor modules, and tests. Name known pre-existing failures (see Gotchas). No completion claim without fresh command output. Full text: [docs/constitution.md](docs/constitution.md#verification-gates).

## Where to change what

| I want to… | Edit | Then update |
|---|---|---|
| Change the shell | `home/zshrc`, `home/zshrc.ai-tools` | README "How it works" |
| Add a CLI script | `bin/<name>` + `tests/<name>.bats` | README "Standalone scripts" |
| Add a doctor check | `modules/<name>/doctor.sh` (auto-discovered) | [module-reference.md](docs/module-reference.md) |
| Add a LaunchAgent | `launchagents/com.dotfiles.<name>.plist.tmpl` | README "LaunchAgents" |
| Add a Homebrew package | `.chezmoiscripts/run_onchange_brew.sh.tmpl` | [what-gets-changed.md](docs/what-gets-changed.md) |
| Change macOS defaults | `macos.sh`, `macos-visual.sh`, `macos-apps.sh` | [what-gets-changed.md](docs/what-gets-changed.md) |
| Add a chezmoi prompt | `.chezmoi.yaml.tmpl` | README "Configuration" |
| Change git config or hooks | `dot_gitconfig.tmpl`, `git-hooks/` | [privacy-gates.md](docs/privacy-gates.md) |
| Change agent MCPs, skills, rules | `Agentfile.yaml` | [agentbrew-setup.md](docs/agentbrew-setup.md) |
| Turn an opt-in agentbrew hook on for every machine | `dot_config/agentbrew/hooks-overlay/modify_manifest.yaml` (`HOOKS=`) | [agentbrew-setup.md](docs/agentbrew-setup.md) |
| Change the default model | `Agentfile.yaml` + `.chezmoiscripts/run_after_claude-settings-model.sh` | [model-configuration.md](docs/model-configuration.md) |
| Change agent wrappers | `bin/gh`, `lib/strip-agent-attribution.sh`, `agent-hooks/` | [agent-hooks.md](docs/agent-hooks.md) |
| Change a skill or command owned here | `skills/<name>/`, `commands/` | its SKILL.md or command file |
| Add a doc | `docs/<name>.md` | a row in [docs/README.md](docs/README.md) |

### Ownership boundary

dotfiles owns `~/.zshrc`, `~/.zshenv`, `~/.gitconfig`, `dot_config/` files, macOS defaults, and `com.dotfiles.*` LaunchAgents. agentbrew owns `~/.claude/`, `~/.cursor/mcp.json`, and agent skills and rules (through `Agentfile.yaml`). minsky owns the orchestrator. **Never have both repos write to the same target path.** Table: [docs/repo-map.md](docs/repo-map.md#ownership-boundary).

## Rules

### Rules for editing

Keep the rule numbers; other files cite them. Full text: [docs/constitution.md](docs/constitution.md#rules-for-editing).

0. **GET, don't IMPLEMENT**: GET, then WRAP, then CONTRIBUTE, ABSORB only when blocked. Pair a new module with a "Replace? Relocate?" task.
1. **Prefer the modern CLI cohort** (`fd`, `rg`, `sd`, `xh`, …); POSIX only when missing, in strict `/bin/sh`, or in CI.
2. **Quote pip specs** (`pip install 'pkg>=1.2.3'`); keep command output out of the repo root.
3. **Never hardcode `$HOME` paths**; use `~`, env vars, resolvers, or chezmoi templates.
4. **Run `make check` before committing.** GitHub Actions are off; local gates are the gate.
5. **Update docs with every behavior change, in the same PR** (see Docs upkeep).
6. **New modules need `modules/<name>/doctor.sh`.**
7. **The Brewfile is inlined** in `.chezmoiscripts/run_onchange_brew.sh.tmpl`.
8. **Agent config is managed by agentbrew.** Edit sources and run `agentbrew sync`; never hand-edit generated agent config.
9. **Open a PR by default**; never commit straight to `feat/chezmoi`, never `--no-verify`, never `git add -A`/`.`/`-u`. **Approved-family standing approval**: in `~/apps/tooling/**` and own `github.com/<owner>/*` repos, `/ship-it` means verify, commit, push, PR, read CI, and merge when green. Verify the PR author before admin/bypass PR merges. Never plain `--force`, hook bypasses, someone else's PR, or out-of-scope publishing.
10. **Prefer user-dir version managers** (uv, fnm, rustup, mise); no `#!/usr/bin/env` shebangs in dotfiles executables.
11. **P0/P1 tasks need** single-line `Hypothesis`, `Success`, `Pivot`, `Measurement`, `Anchor`.
12. **Proactive healing**: a recurring error becomes a same-session fix or a task with its blocker.
13. **Default by default**: safe, useful behavior is the default; opt-outs are narrow and documented.

**Visual proof for every PR**: a browser screenshot for UI work, a pasted terminal transcript otherwise. Never commit proof images; never drive AppleScript or keystrokes to stage one.

### Agentfile lifecycle

`dotfiles apply` merges `Agentfile.yaml` with any overlay Agentfile into `~/.config/agentbrew/Agentfile.yaml` and runs `agentbrew sync`. Org-gated MCPs go in the overlay, never here. Never edit generated agent config under `~/.claude/` or `~/.cursor/`. Full text: [docs/constitution.md](docs/constitution.md#agentfile-lifecycle).

### Hook-based enforcement

agentbrew PreToolUse hooks enforce first; `bin/gh` and `git-hooks/commit-msg` are the backstop outside Claude Code. [docs/agent-hooks.md](docs/agent-hooks.md).

### Agents, browsers, models, privacy

- **Deprecated agents**: Windsurf and Devin are removed; Augment is frozen (never fix it or file tasks for it). [docs/repo-map.md](docs/repo-map.md#deprecated-agents--frozen).
- **Browsers**: attach to the launchd Chrome on `9223`/`9224`/`9225`; own your tabs; never `osascript activate`. [docs/agent-browser-policy.md](docs/agent-browser-policy.md).
- **Privacy**: public repo; no private email, org identifier, or secret. Never set `DOTFILES_ALLOW_GH_PRIVATE_REFS=1`. [docs/privacy-gates.md](docs/privacy-gates.md).

### Model configuration

Claude Code runs `claude-opus-5-5` at `xhigh`, pinned by dotfiles and agentbrew; never hand-edit `settings.json`. [docs/model-configuration.md](docs/model-configuration.md).

## Gotchas

- **Worktrees**: use `~/apps/tooling/wt/<name>` (`wt` links to `wt.noindex`, so Spotlight skips it). Never edit the live checkout: `dotfiles-sync` auto-commits and pushes its tracked changes every 30 minutes.
- **Global hooks**: `core.hooksPath` points at the live checkout's `git-hooks/`. To commit a hook change, run `git -c core.hooksPath=$PWD/git-hooks commit`.
- **`make test` misses committed changes**: it runs tests for uncommitted files only. On a branch, use `bin/bats-affected origin/feat/chezmoi | xargs bats`.
- **Agent sandbox**: bats `mktemp` fails inside it. Run bats unsandboxed.
- **npm in the sandbox** prints `failed to copy trust settings` (host sets `NODE_USE_SYSTEM_CA=1`). Harmless; run npm unsandboxed or with `env -u NODE_USE_SYSTEM_CA`.
- **Parallel agents**: run at most 3 gate-running agents at once. Eleven froze a 10-core Mac on 2026-10-15. Check `dotfiles-load-sampler --report 1` before adding more.
- **`BASH_ENV` resets `DOTFILES_DIR`** to the live checkout in child `bash`. Tests that spawn `bash` without `load test_helper` must use `env -u BASH_ENV`.
- **Global gitignore lists `TASKS.md`**: fixture git repos in tests need `GIT_CONFIG_GLOBAL=/dev/null`.
- **Known base failures** (fail on unchanged `feat/chezmoi` too): `tests/coverage.bats` "single test file" report.
- **Agent perf `project`** is the repo of the session start directory, not of a `cd` target. Read a cross-repo session with `--all`.
- **Human-only steps**: `sudo` (for example `dotfiles-launchd-maxfiles`) and `bin/land` need a human terminal.

## Delivery

1. Branch `type/description` (`feat`, `fix`, `docs`, `chore`, …) in a worktree; commit `type: description` (≤72 chars).
2. Run `make check`; name any known base failure.
3. Push the branch and open a PR to `feat/chezmoi`. PR body: `## Summary` (why + what), `## Details`, `## Docs`, then validation and `## Visual proof`. Template: [docs/ship-it-reference.md](docs/ship-it-reference.md).
4. Squash-merge when green, remove the worktree and branch, and `git pull` the live checkout.

Tasks: `TASKS.md` (tasks.md shape); delete a task block in the same commit as its fix; non-trivial tasks get `docs/plans/<task-id>.md`. [docs/constitution.md](docs/constitution.md#task-queue).

## Docs upkeep

- A behavior change updates its doc in the same PR. The routing table names the doc.
- A gotcha that cost time goes into Gotchas in the same PR, or becomes a test.
- Every PR body has `## Docs`: the docs changed, or `Docs: none — <reason>`.
- A new top-level `docs/*.md` gets a row in [docs/README.md](docs/README.md).
- `tests/docs-contract.bats` enforces this file's sections and size, the docs map, and the README opening.
