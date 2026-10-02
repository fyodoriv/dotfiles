# AGENTS.md — Dotfiles Codebase Guide

## What This Repo Is

macOS developer dotfiles with self-healing health checks. Chezmoi-based, shell scripts, bats tests. Source dir: `~/apps/dotfiles`.

## Main use cases — first-class AI coding agents

This dotfiles repo + agentbrew + minsky together support five **primary AI coding agents** as equal first-class citizens: **Claude Code, Cursor, Windsurf, Devin, Codex**. Every agent-config surface (skills, MCP, rules, commands, agents, hooks, instructions) syncs to all five automatically every 30 minutes via the auto-repair launchagent. Cursor is **not** an afterthought — it gets the same `~/.cursor/rules/`, `~/.cursor/skills/`, `~/.cursor/commands/`, `~/.cursor/agents/`, `~/.cursor/mcp.json`, `~/.cursor/hooks.json`, and `~/.cursor/CLAUDE.md` treatment as Claude Code does. Long-tail agents (OpenCode, Kiro, Amp, Goose, Cline, Roo Code, Gemini CLI, GitHub Copilot, …) are best-effort: they get every category their underlying API supports, but new first-party features ship for the five primary agents first.

Concrete invariants enforced by tests:
- `~/.cursor/rules/*.mdc` ↔ canonical shared rules — see `agentbrew/src/sync/rules-sync.ts` and the per-agent matrix.
- Cursor's `mcp.json` carries the same MCP servers Claude Code's `~/.claude.json` does.
- The same skill catalog mounts under both `~/.claude/skills/` and `~/.cursor/skills/`.
- A new dotfiles feature that touches agent config but only works for Claude Code is a P0 regression. File a follow-up before merge.

## agent-browser attach-first policy

Agent sessions should attach to the launchd-owned Chrome that matches the task instead of spawning a new Chrome instance by default:

| Port | LaunchAgent | Purpose |
|------|-------------|---------|
| `9223` | `com.dotfiles.agent-browser-chrome` | dashboard / general SSO |
| `9224` | `com.dotfiles.debug-chrome` | debug work |
| `9225` | `com.dotfiles.tooling-chrome` | tooling repo work |

The `home/zshrc.ai-tools` wrapper routes normal operator calls and dotfiles-assigned agent sessions to `agent-browser --cdp 9223` when the dashboard Chrome is reachable. Launchd Chromes run `--headless=new` so CDP tab create never opens a GUI window. After agent-browser, the wrapper logs suspected focus steals to `~/.local/share/dotfiles/logs/focus-steal.log` only — it never hides Chrome or `osascript activate`s another app (both can switch Spaces). Use `--headed` or `AGENT_BROWSER_ALLOW_FOCUS=1` when you want Chrome to stay frontmost for SSO. Preserve tab safety with per-agent daemons plus own-tab discipline: open your own tab, act only on tabs you opened, and close extra tabs at task end.

These three managed Chromes are `RunAtLoad` only, not `KeepAlive`: if the operator quits Chrome for logout/shutdown, launchd and `dotfiles doctor --fix` must not reopen it. Agents attach when a purpose Chrome is available; otherwise use the documented isolated/task-local browser modes.

Do not set `AGENT_BROWSER_PROFILE` to launchd-owned profiles under `~/.agent-browser/{chrome-profile,debug-profile,tooling-profile}`. Chrome ProcessSingleton forwards those launches into the existing browser and creates stray `chrome://newtab` windows; the wrapper delegates such profiles to `agent-browser-singleton-preflight` or refuses.

Use a separate browser only for true isolation, conflicting credentials, or visible human authentication in a separate window. In that case, choose a stable purpose-named session (`agent-browser --headed --session-name sso-<purpose> ...`), not a timestamp-unique session, and close it when done. For non-SSO task-local checks, use a throwaway browser with a random debugging port, never ports `9222`-`9225`.

## Hook-based enforcement (post-2026-05-27)

`bin/gh` and `git-hooks/commit-msg` are **backstop** enforcement now. The
primary enforcement happens via agentbrew Claude Code hooks deployed to
`~/.claude/codeassist/hooks-scripts/` and wired into `~/.claude/settings.json`.

The Claude Code hooks fire ahead of the dotfiles wrappers — they catch
violations at the `PreToolUse` protocol layer, before the wrapper ever
runs. The wrappers stay because:

- Non-Claude shells (interactive zsh, scripts, manual `gh pr create`) bypass
  Claude Code's hook layer entirely. The dotfiles wrappers catch them.
- The wrapper's MUTATE logic (strip foreign attribution + append canonical
  Fyodor footer) is harder to express as a Claude Code hook (PreToolUse
  can't cleanly rewrite tool_input). The hook WARNS; the wrapper MUTATES.

`dotfiles/lib/strip-agent-attribution.sh` is the **single source of truth**
for the agent-attribution regex set. Both the dotfiles wrappers and the
agentbrew hooks source the same logic — `agentbrew/hooks/lib/strip-agent-attribution.sh`
is a copy maintained in sync via a CI lint (or manual update on drift).

The 8 deterministic hooks deployed today:
1. `code-no-timestamps` — blocks Write/Edit with `// YYYY-MM-DD` in source
2. `gh-pr-body-attribution` — warns on foreign attribution in PR body
3. `gh-pr-body-requires-rationale` — blocks PR body without Why/ticket
4. `git-commit-conventional` — enforces conventional commits on `-m`
5. `git-strip-agent-attribution` — warns on foreign attribution in `-m`
6. `no-git-add-all` — blocks `git add -A` / `.` / `-u` (multi-agent safety)
7. `no-force-push-protected` — blocks `git push --force` to main/master/develop
8. `no-commit-no-verify` — blocks `git commit --no-verify` (no bypass — iron rule)

See `agentbrew/hooks/manifest.yaml` for the canonical hook source and
`agentbrew/docs/research/deterministic-rules-via-hooks.md` for the
migration architecture.

## Repo Layout

```
dotfiles/
├── home/                        Actual config content (symlinked to ~/)
│   ├── zshrc                    Shell config (aliases, PATH, tool inits)
│   ├── zshrc.ai-tools           AI agent tooling (opt-in via use_ai_tools)
│   ├── zshenv                   Non-interactive env (fnm, secrets)
│   ├── gitconfig                Git config (aliases, diff, merge, performance)
│   └── ...                      tmux.conf, ideavimrc, git-editor, etc.
├── bin/                         Scripts (38+ — added to PATH)
│   ├── dotfiles                 Unified CLI (delegates to chezmoi + subcommands)
│   ├── dotfiles-doctor          Self-healing audit (auto-discovers module checks; macOS banners opt-in via DOTFILES_DOCTOR_NOTIFY=1)
│   ├── dotfiles-sync            Auto git commit + push
│   ├── dotfiles-stats           Time-saved tracking
│   └── ...                      morning, cleanup, git-maintain, cheat, etc.
├── modules/                     Health check modules
│   └── */doctor.sh              Per-module checks using check(), check_symlink(), check_managed()
├── lib/                         Shared libraries
│   ├── colors.sh                ANSI codes + logging (info/ok/warn/fail/section)
│   ├── stats.sh                 Time-saved tracking (log_run, get_time_saved_summary)
│   └── output.sh                Pass/fail/warn output for doctor modules
├── macos.sh                     Core macOS defaults
├── macos-visual.sh              Visual prefs, full only
├── macos-apps.sh                App-specific prefs, full only
├── launchagents/                macOS scheduled task templates
├── .chezmoiscripts/             Lifecycle scripts (brew, macos, launchagents, agentbrew)
├── dot_*                        Copy-mode config files (→ ~/.<name>)
├── private_dot_ssh/             SSH config (restricted permissions)
├── symlink_dot_*.tmpl           Symlink templates (→ ~/.<name>)
├── tests/                       bats test suite
├── docs/                        Documentation (onboarding, troubleshooting, architecture, security, migration, FAQ)
├── Agentfile.yaml               AI agent config manifest (synced by agentbrew)
├── TASKS.md                     Task queue
└── README.md
```

## Development

```bash
make lint       # shellcheck all scripts
make lint-tasks # validate TASKS.md queue format
make test       # affected tests only (cached, git-aware)
make test-all   # full bats suite (cached)
make test-force # full suite, no cache
make check      # lint + TASKS.md lint + test (run before committing)
```

## Rules for Editing

These are the dotfiles constitutional rules: the repo-local projection of
Minsky's `vision.md` constitution and agentbrew's global agent rules. They do
not redefine Minsky or agentbrew; they map those rules onto dotfiles-owned
surfaces (`home/*`, `bin/*`, `modules/*/doctor.sh`, `.chezmoiscripts/*`,
`Agentfile.yaml`, docs, tests, and git hooks). Numbering starts at 0 to
preserve the long-standing GET rule. Rules 11-13 are the explicit Minsky imports
added by `adopt-minsky-constitutional-rules-link`.

0. **GET, don't IMPLEMENT.** Before writing any new script, lint, doctor module, or workflow, ask "how do I GET this outcome?" — not "how do I implement this in dotfiles?" Decision order: (1) GET it (install / call existing tool); (2) WRAP it (small adapter); (3) CONTRIBUTE upstream; (4) ABSORB only when 1-3 are blocked. Pair every new module with a "Replace? Relocate?" research task in `TASKS.md`. Concrete examples: `lefthook` is wrapped (don't reinvent git-hook runners); `chezmoi` is wrapped (don't reinvent dotfile templating); the `bats` test framework is delegated (don't reinvent bash testing). When you must IMPLEMENT, the new code is small, lives under a clear path, and is designed to be extractable to OSS from day one. **Agentbrew counterpart**: `templates/AGENTS.md` § "Reuse before implementation" and `VISION.md` § "Strategy: delegate, contribute, absorb". **Minsky anchor**: `vision.md` rule #1 "Don't reinvent the wheel". **Gate/status**: advisory-only decision discipline today; `make lint-tasks` validates the follow-up task shape when one is filed, but no deterministic GET-evidence lint exists in dotfiles yet.

1. **Prefer the modern CLI cohort over POSIX defaults** in all scripts and ad-hoc commands — `fd` over `find`, `rg` over `grep`, `sd` over `sed`, `xh` over `httpie`/`curl` (for JSON APIs), `bottom`/`btm` over `top`/`htop`, `dust` over `du`, `procs` over `ps aux`, `bandwhich` over `nettop`, `hexyl` over `xxd`, `tealdeer` over `man`-snippets, `glow` over `cat README.md`, `git-absorb` over `git commit --fixup`+`rebase --autosquash`, `git-cliff` over hand-curated CHANGELOGs. Every entry is installed via this repo's inline Brewfile in `.chezmoiscripts/run_onchange_brew.sh.tmpl`. Fall back to POSIX tools only when (a) `command -v <modern-tool>` returns nothing, (b) you're editing a strictly-POSIX `/bin/sh` script for portability, or (c) you're scripting against a CI / customer environment where the modern tool isn't guaranteed. **Agentbrew counterpart**: none; this is dotfiles-local tool policy. **Anchor**: "tools shape workflow" ergonomics; `.gitignore`-aware search keeps agent loops smaller and safer. **Gate/status**: advisory only; `make check` catches syntax and missing managed-tool drift but does not lint `find`/`grep` usage by itself.

2. **Quote pip specs and keep command-output debris out of repo root.** Use `pip install 'pkg>=1.2.3'`, not an unquoted shell token that redirects `>=` output into files like `=5.5.0`. Never redirect exploratory command output to the repo root. **Agentbrew counterpart**: global "Scope discipline" / "smallest change" rules. **Minsky anchor**: rule #10 deterministic enforcement — recurring debris becomes a scanner. **Gate/status**: partially gated by `dotfiles audit` / `tests/audit.bats` for known root-level pip redirect artifacts; pip-quote discipline is otherwise advisory.

3. **Never hardcode `$HOME` paths** — use `~`, environment variables, helper resolvers, or chezmoi templates. Absolute operator paths make the repo non-forkable and can leak private layout. **Agentbrew counterpart**: global source-routing and generated-output boundary rules. **Minsky anchor**: rule #2 "Every dependency behind an interface" applied to filesystem locations. **CS anchor**: Twelve-Factor config separation and portability-by-configuration. **Gate/status**: `make check` runs `tests/smoke.bats` and `tests/chezmoiscripts.bats`, which catch hardcoded operator paths in scripts and chezmoi lifecycle files.

4. **Run `make check` before committing.** `make check` is the default verification gate: shellcheck + TASKS.md lint + affected Bats tests. Targeted Bats runs are useful while iterating, but do not replace `make check` before a commit unless a failure is explicitly documented as pre-existing/unrelated with evidence. **Agentbrew counterpart**: global "Verification" rule. **Minsky anchor**: rule #3 "Test-first, metric-first, doc-first" and rule #10 deterministic enforcement. **CS anchor**: red/green/refactor and continuous integration. **Gate/status**: `make check` is the only gate that runs Bats today. The `.github/workflows/` jobs do not run, because GitHub Actions is turned off on `fyodoriv/dotfiles` (see README "Where tests run").

5. **Update README alongside behavior changes.** README drift is a bug because it is the front door for setup, troubleshooting, and adoption. Behavior changes that affect user-facing commands, modules, LaunchAgents, safety gates, or agent config must update README/docs in the same commit. **Agentbrew counterpart**: global "Output quality is UX" belief. **Minsky anchor**: rule #3 doc-first. **CS anchor**: executable documentation / living documentation discipline. **Gate/status**: partially gated by `tests/user-stories.bats` for claim drift; docs carry no counts to keep in sync; semantic README drift is reviewer/advisory until a deterministic assertion exists.

6. **New modules need `modules/<name>/doctor.sh`.** A documented recurring issue that can be detected belongs in a doctor module, not only in prose. Doctor modules are auto-discovered; adding one should require no central registry edit. **Agentbrew counterpart**: `agentbrew sync` auto-repair philosophy, but this implementation is dotfiles-owned. **Minsky anchor**: rule #6 "Stay alive" and rule #17 "Proactive healing". **CS anchor**: IBM autonomic-computing MAPE-K loop (monitor/analyze/plan/execute over shared knowledge) and convention-over-configuration. **Gate/status**: `make check` runs module Bats coverage; `dotfiles doctor` proves discovery at runtime.

7. **Brewfile is inlined** in `.chezmoiscripts/run_onchange_brew.sh.tmpl`, not a standalone root `Brewfile`. This keeps package selection tied to chezmoi profile / enterprise / overlay data and lets one `chezmoi apply` converge the machine. **Agentbrew counterpart**: agentbrew's "Auto-fix by default" sync convergence belief. **Minsky anchor**: rule #16 "Default by default" for sane setup behavior. **CS anchor**: idempotent configuration convergence. **Gate/status**: `make check` runs `tests/chezmoiscripts.bats`; `.github/workflows/brew-audit.yml` and `.github/scripts/brew-audit-manifest.sh` audit the inline manifest.

8. **Agent config is managed by agentbrew, not dotfiles.** Dotfiles owns `Agentfile.yaml`, shell environment, git wrappers/hooks, and doctor checks around agent tooling. agentbrew owns generated files under `~/.claude/`, `~/.cursor/`, `~/.codeium/`, `~/.config/devin/`, `~/.codex/`, and similar agent dirs. Edit sources, then run `agentbrew sync`; never hand-edit generated mirrors to make a dotfiles change. **Agentbrew counterpart**: `templates/AGENTS.md` opening rule and `VISION.md` § "Curator, not host". **Dotfiles vision anchor**: `VISION.md` G2. **Minsky anchor**: rule #2 dependency boundaries. **Gate/status**: `tests/agent-artifact-coverage.bats`, `Agentfile.yaml` comments, `make check`, and `dotfiles doctor --module agentbrew` catch source/generated drift.

9. **Always open a PR by default — never commit straight to a long-running branch.** For any non-trivial change, cut a short-lived feature branch (`feat/`, `fix/`, `chore/`, `docs/…`), push it, open a PR to the canonical branch, let CI go green, then squash-merge. The auto-sync launchagent (`bin/dotfiles-sync`) is branch-gated: it commits/pushes only on the canonical branch and skips feature branches, so a concurrent agent's checked-out branch is never polluted. `sync: auto-update` is a trunk safety net, not a substitute for a reviewed PR. Never push `main`/`master` directly, never bypass hooks (`--no-verify`), and never `git add -A`/`.`/`-u` in multi-agent worktrees. Minsky's autonomous loop is the only carve-out: it may fast-forward local `main` or its orchestrator-designated local branch after verification when it needs direct local progress and carries the expected orchestrator context. **Approved-family standing approval**: in tooling repos under `~/apps/tooling/**`, in own repos on `github.com/<owner>/*`, and in any extra repo family the org overlay declares, `/ship-it` means verified, committed, feature-branch pushed, PR opened/updated, CI watched/read, and merged once substantive checks are green. In any other repo explicitly named by the active request, `/ship-it` pre-approves normal feature-branch push/PR/CI delivery plus rebasing a verified user-owned/current-session PR branch onto its actual base; preserve the old remote OID and publish rewrites only with explicit `--force-with-lease=<ref>:<old-oid>`. This does not extend approved-family admin-bypass or release permission to product repos. Prefer the reviewed PR when duplicate branches/PRs contain the same intended change; when required checks are green, the PR is otherwise mergeable, and normal merge is blocked only by review/base-branch policy, admin/bypass merge is required for the user's/current-session PR rather than leaving it open or starting a fresh branch; verify PR author/head owner before admin/bypass PR merges; never cover plain `--force`, hook bypasses, protected-branch direct pushes, unrelated branch deletion, secrets, production/deployment state, someone else's PR, or cross-workspace publication outside the current-task/approved scope. After delivery, reconcile/rebuild the canonical checkout and apply the latest recommended tooling config (`agentbrew sync --pull` or `dotfiles apply` from a directory without a project Agentfile), then confirm `agentbrew status` is clean. **Agentbrew counterpart**: global "Git Safety (Multi-Agent)" and "Public Impersonation Ban". **Minsky anchor**: rule #10 deterministic enforcement plus orchestrator discipline. **CS anchor**: GitHub Flow / trunk-based delivery with multi-agent isolation. **Gate/status**: `agentbrew/hooks/manifest.yaml` hooks (`no-git-add-all`, `no-commit-no-verify`, `no-force-push-protected`, `git-commit-conventional`), dotfiles `git-hooks/{pre-commit,commit-msg,pre-push}`, `bin/gh`, and Bats coverage (`tests/git-safe.bats`, `tests/commit-msg.bats`, `tests/pre-push.bats`, `tests/gh-wrapper.bats`) mechanically cover the dangerous sub-cases; the "open a PR by default" delivery norm remains reviewer/advisory outside `/ship-it` standing approval.

**Visual proof for every PR.** Before handoff or merge, attach visual proof to
the PR description. For UI work, show the changed state in a live browser. For
non-UI work, prefer a **pasted terminal transcript** — the command and its real
output in a fenced code block. A transcript is copyable, diffable, and
searchable, so it beats a picture of the same text; a terminal image is an equal
alternative, never a requirement. **Never drive AppleScript, keystrokes, or
window activation to stage a terminal image** — that steals focus from the
user's apps and can type into whatever is frontmost. Cover every changed
behavior. Drag and drop any image. Keep images outside the repository. Never
commit them. Name the case, action, expected result, and observed result. If safe
proof is blocked, record the exact blocker and do not claim the PR is ready.

10. **Prefer user-dir version managers over admin-path installs for dev tools.** Some managed Macs run an endpoint-security agent that flags binaries in admin paths (`/Library/Frameworks/`, `/usr/local/Cellar/`, `/opt/`) by publisher signature. Binaries in `~/.local/` are usually treated differently. Use user-dir managers:

    | Tool    | DON'T (admin path)                                | DO (user dir, or special case)                                 |
    |---------|---------------------------------------------------|----------------------------------------------------------------|
    | python  | `brew install python@*` / python.org `.pkg`       | `uv venv --python 3.13 .venv` / `pipx install --python $(uv python find 3.13)`; uv has no publisher authority, so keep recurring automation off it and file a machine-scoped exception for explicit use |
    | node    | `brew install node`                               | `fnm install --lts` (binary lands in `~/.local/share/fnm/`); if policy blocks upstream Team ID `HX7739G8FX`, disable recurring execution and file a machine-scoped exception |
    | go      | `brew install go`                                 | `g install latest` or `asdf install golang latest`             |
    | rust    | `brew install rust`                               | `rustup` (installs to `~/.cargo/`, `~/.rustup/`)               |
    | java    | `brew install openjdk@*`                          | `sdkman install java <version>`                                |
    | ruby    | `brew install ruby`                               | `mise use ruby@<version>` or `rbenv`                           |
    | **curl**| `/usr/bin/curl` (old system version); bash `bin/curl` shim | `brew install curl` + `bin/dotfiles-link-curl-shim` → symlink `bin/curl` to adhoc-signed keg-only Homebrew curl + `HOMEBREW_CURL_PATH` |
    | **jq**  | unsigned Homebrew bottle, unsigned dotfiles shim, or wrong PATH order | `brew install jq` + `bin/jq` shim + ad-hoc sign via `dotfiles-adhoc-sign-bottles` and `dotfiles-adhoc-sign-endpoint-shims` |
    | **grep**| `/usr/bin/grep`; bare `ggrep` / bash shim | `brew install grep` + `bin/dotfiles-link-grep-shim` → symlinks `bin/grep` + `bin/ggrep` to adhoc-signed Homebrew `ggrep` |
    | **perl**| `/usr/bin/perl` (system binary) | `brew install perl` + `bin/dotfiles-link-perl-shim` → symlink `bin/perl` to adhoc-signed Homebrew perl |
    | **otool**| `/usr/bin/otool` (system binary) | `bin/dotfiles-link-otool-shim` → symlink `bin/otool` to Xcode/CLT `llvm-otool` (`Identifier=com.apple.llvm-otool`) |

    Python can trigger `Python.framework/` path matches and publisher checks. `uv` avoids the framework path, but python-build-standalone has no `Authority=` identity, so a strict policy can still flag it after ad-hoc signing. Node can trigger publisher matches too. User-dir installation reduces path-based blocks. It does not change publisher policy. When the org overlay marks the Node publisher as blocked, `bin/dotfiles-disable-blocked-node-automation` unloads `com.agentbrew.*` plus weekly Topgrade, apply-time agentbrew sync and Node-dependent doctors stay off, and npx-only commit lint is left to CI. The Ollama supervisor likewise refuses a blocked publisher until `DOTFILES_ALLOW_BLOCKED_OLLAMA_PUBLISHER=1` is set. `DOTFILES_ALLOW_BLOCKED_NODE_PUBLISHER=1` is the matching Node opt-in.

    **Apple Silicon (arm64):** use native Homebrew at `/opt/homebrew` (not Intel brew at `/usr/local`). Do not force work apps to Rosetta — legacy dotfiles set Ghostty `LSArchitecturePriority=x86_64`; `macos-apps.sh` now clears that override (and the same key for Cursor, Chrome, Slack, Windsurf, Outlook, Terminal) on apply. uv python symlinks land in `~/.local/bin` on native arm64 shells. Doctor gates: `security.homebrew_native_prefix`, `apps.no_rosetta_override`, `cursor.native_arch`, `tool.ghostty.arch`, `resilience.native_arm64_shell`. See `docs/troubleshooting.md#shell-running-under-rosetta`.

    `uv` Python binaries **and** their Mach-O companions (`libpython*.dylib`, `lib-dynload/*.so`) are ad-hoc signed by `.chezmoiscripts/run_after_uv-python-setup.sh` / `bin/dotfiles-adhoc-sign-uv-pythons`. Apply-time and agent-hook JSON mutation uses Apple-signed `/usr/bin/plutil`. The pipx-based mcpm bridge, Python installers, and Python-dependent base/overlay/local-LLM doctor modules stay disabled in endpoint-policy safe mode unless `DOTFILES_ALLOW_PUBLISHER_NA_PYTHON=1` is set. Homebrew bottles and endpoint shims stay ad-hoc signed so that none is completely unsigned. Set `DOTFILES_MANAGED_ENDPOINT=1` (or list agent app paths in `DOTFILES_ENDPOINT_AGENT_APPS`) to turn on the managed-endpoint behavior; the org overlay sets these.

    **No `#!/usr/bin/env` shebangs in dotfiles executables on a managed endpoint.** Some endpoint-security agents flag `/usr/bin/env` when high-churn `bin/*`, `git-hooks/*`, `lib/*.sh`, or `.chezmoiscripts/*` scripts run. Minsky `bin/*` and LaunchAgent `ProgramArguments` must also avoid `/usr/bin/env` — use `/bin/bash` + `distribution/systemd/run-*.sh` wrappers for node/python invocations under launchd. Use `#!/bin/bash` directly. Scripts that need Bash 4+ (e.g. `declare -A` in `bin/dotfiles-stats`) must re-exec Homebrew bash (`/opt/homebrew/bin/bash` or `/usr/local/bin/bash`) — never `#!/usr/bin/env bash`. Python wrappers must call `"$SCRIPT_DIR/python3"`, not hardcoded `/usr/local/bin/python3`. **Agentbrew counterpart**: none; this is dotfiles endpoint policy. **Minsky anchor**: rule #6 "Stay alive" because endpoint-security prompts are recurring liveness failures. **CS anchor**: least privilege and blast-radius reduction. **Gate/status**: `modules/security/doctor.sh` (`security.endpoint_shims_adhoc_signed`, `security.uv_python_adhoc_signed.*`, `security.brew_bottles_signed`, `security.curl_shim`, `security.jq_shim`, `security.grep_shim`, `security.otool_shim`, `security.otool_not_system`, `security.no_env_shebangs`, `security.no_env_shebangs_git_hooks`, `security.no_env_shebangs_minsky_bin`, `security.launchagent_no_env`, pipx framework checks) plus `tests/remove-framework-python.bats`, `tests/chezmoiscripts.bats`, and `tests/tool-shims.bats` cover the reproducible pieces; per-machine endpoint exceptions are human-blocked.

11. **Hypothesis-driven metadata for P0/P1 tasks.** P0/P1 tasks need single-line `Hypothesis`, `Success`, `Pivot`, `Measurement`, and `Anchor` fields before implementation starts. Do not fake metrics for tiny fixes; if a task cannot honestly state them, demote it or split out a preparation task. **Agentbrew counterpart**: `templates/AGENTS.md` § "Task backend" for `.minsky/repo.yaml` P0/P1 metadata. **Minsky anchor**: rule #9 "Pre-registered hypothesis-driven development". **CS anchor**: Basili/Caldiera/Rombach Goal-Question-Metric and pre-registration. **Gate/status**: `make lint-tasks` and `make lint-tasks-rule9` hard-fail through `.github/scripts/check-tasks-rule9-fields.sh`.

12. **Proactive healing: observed recurring errors become same-session fixes or tasks.** If you see a recurring drift, flaky test, auth-path failure, command-not-found, endpoint-security block, red CI, or broken generated config, do not merely report it. Fix the class in the same session when local and safe; otherwise file a task with the blocker and unblock path. **Agentbrew counterpart**: global "Verification" and scope-discipline rules; agentbrew can distribute the resulting rule/hook when it is cross-agent. **Dotfiles vision anchor**: G1 "Self-healing > documented manual steps". **Minsky anchor**: rule #17 "Proactive healing". **CS anchor**: MAPE-K feedback control and Erlang/OTP supervision mindset. **Gate/status**: advisory-only as a constitutional rule; concrete instances become deterministic gates by adding `modules/<name>/doctor.sh`, Bats tests, git hooks, or `TASKS.md` entries.

13. **Default by default.** If new behavior is safe and useful for the documented user story, make it the default rather than hiding it behind an opt-in flag. Keep opt-outs narrow, documented, and for debugging or resource-heavy carve-outs only. **Agentbrew counterpart**: `VISION.md` belief "Simple beats clever" and "Auto-fix by default". **Minsky anchor**: rule #16 "Default by default". **CS anchor**: convention-over-configuration and paved-road platform design. **Gate/status**: advisory-only at the constitutional level; when behavior changes, `make check`, README/user-story updates, and doctor checks must make the default visible and reversible.

## Task Queue

All pending work lives in `TASKS.md` and must follow the
[tasks.md](https://github.com/tasksmd/tasks.md) shape used by the shared
agent-tool repos:

- First line is `# Tasks`, followed by `## P0`, `## P1`, `## P2`, `## P3`.
- Tasks are checkbox lines (`- [ ] ...`) with indented bold metadata labels
  such as `**ID**:`, `**Tags**:`, `**Details**:`, `**Files**:`,
  `**Acceptance**:`, and `**Blocked by**:`.
- P0/P1 tasks must also include single-line `**Hypothesis**:`,
  `**Success**:`, `**Pivot**:`, `**Measurement**:`, and `**Anchor**:`
  fields. Claimed or blocked tasks are not exempt. For example,
  `bin/add-task --priority P1` requires `--hypothesis`, `--success`,
  `--pivot`, `--measurement`, and `--anchor`.
- Completed tasks are removed entirely in the same commit as the fix; do not
  mark them `[x]`.
- Read `<!-- policy: ... -->` comments before editing; file-level policies
  apply across the queue.
- Validate queue edits with `make lint-tasks` (wraps
  `npx -y @tasks-md/lint@<version> TASKS.md`, with `<version>` pinned in
  `.tasks-lint-version`, then runs `.github/scripts/check-tasks-rule9-fields.sh`).
- Non-trivial tasks (`/next-task` queue mode) need a plan at
  `docs/plans/<task-id>.md` copied from
  [`docs/templates/plan-template.md`](docs/templates/plan-template.md) and
  reviewer approval before implementation.

## Agentfile Lifecycle

`Agentfile.yaml` is the declarative source for dotfiles' AI-agent setup. The
chezmoi lifecycle script `.chezmoiscripts/run_after_agentbrew-sync.sh` merges
this file plus any overlay Agentfile into
`~/.config/agentbrew/Agentfile.yaml`, then runs `agentbrew sync --agentfile`
against that canonical global file after `dotfiles apply` when the installed
agentbrew supports `agentfile merge`. Older agentbrew releases fall back to the
legacy safe sequence: base Agentfile sync, then overlay sync with `--no-prune`.
It falls back to
`~/apps/agentbrew/node_modules/.bin/tsx ~/apps/agentbrew/src/cli.ts ...` when
`agentbrew` is not on `PATH`. The `agentbrew` doctor module verifies the CLI,
this Agentfile, `~/.config/agentbrew/state.yaml`, and the generated global
Agentfile copy; the canonical drift check skips when the installed CLI cannot
compute the merge.

Whole-machine update boundary: `dotfiles update` may invoke
`agentbrew sync --pull --agentfile ~/apps/dotfiles/Agentfile.yaml` as a
delegation to the owner CLI, but dotfiles must not edit generated agent config
directly.

- Edit `Agentfile.yaml` when dotfiles should request MCP servers, skills,
  sources, or shared rules for all agents on this machine.
- **Org-gated MCPs DO NOT belong here.** Any MCP whose runtime depends on
  org-internal infrastructure (corporate identity provider, internal API
  gateway, behind-VPN endpoint, marketplace entitlement) goes into the
  org's overlay Agentfile (e.g. `~/apps/dotfiles-<org>/Agentfile.yaml`)
  loaded via the `EXTRA_AGENTFILE` hook. The litmus test: if a fresh
  contributor outside the org runs `dotfiles apply`, does the MCP work?
  If no, it goes in the overlay. The `tests/no-internal-refs.bats` guard
  catches configured private identifiers when a private overlay supplies
  `oss-readiness.env`; keep this base Agentfile generic so a fresh fork can
  layer its own private identifiers without editing the base.
  **The full cross-agent rule (routing table, detection regex, per-class
  disposition, before-I-edit checklist) is codified in
  `agentbrew/templates/AGENTS.md` under "Org-overlay routing (agentbrew +
  dotfiles family) — IRON LAW" and synced to every agent's instruction
  file via `agentbrew sync`. That's the canonical reference; this rule
  is the dotfiles-repo-specific elaboration.**
- Keep entries explicit; hidden recommended sets can introduce required env vars
  and make unattended `dotfiles apply` fail noisily.
- After Agentfile changes, run `dotfiles apply` (or the lifecycle script above),
  then `make check`.
- Never edit generated agent config under `~/.claude/`, `~/.cursor/`,
  `~/.config/devin/`, or other agent directories to make a dotfiles change.

## Agent Tool Source Boundaries

Every agent tool has exactly one canonical source repo. Dotfiles owns only this
repo's `Agentfile.yaml`, shell environment, git wrappers/hooks, and doctor
checks around agent tooling. Agentbrew owns deployment and installed mirrors.

| Tool/content | Canonical source |
|--------------|------------------|
| Shared dev skills (`agentbrew-*`, `sync-agent-config`, etc.) | `~/apps/agentbrew/skill-plugins/dev/` |
| Personal cross-tooling commands (`research-url`) | `~/apps/tooling/dotfiles/commands/` |
| Task queue commands (`next-task`, `lint-tasks`) | `~/apps/tasks.md/commands/` |
| Minsky orchestrator personas and pipeline commands | `~/apps/minsky/skill-plugins/orchestrator/`, `~/apps/minsky/commands/` |
| Dotfiles AI env, `gh`/`git` public-write guards, doctor checks | `~/apps/dotfiles/` |
| Installed agent mirrors | Generated by agentbrew; do not edit directly |

Before creating or copying a skill/command/workflow, check the table above and
edit the canonical source. If a tool is duplicated, keep the most-shared source
and delete the local copy.

## Verification Gates

- `make check` is the default gate for code, docs that affect behavior, hooks,
  doctor modules, and tests.
- `make lint-tasks` is required for `TASKS.md` edits; it runs the pinned
  `npx -y @tasks-md/lint@<version> TASKS.md` command from
  `.tasks-lint-version` and the rule-9 P0/P1 metadata gate.
- Targeted bats runs are useful while iterating, but do not replace `make check`
  before committing.
- For `Agentfile.yaml` edits, also run `dotfiles apply` or the lifecycle fallback
  so generated config drift is caught locally.
- State any known pre-existing failure explicitly; do not claim completion
  without fresh command output.

## Data Flow

```
source                          chezmoi                          target
──────                          ───────                          ──────
symlink_dot_*.tmpl + home/*  →  symlink mode                  →  ~/.<name> → home/<name>
dot_*                        →  copy mode                     →  ~/.<name>
private_dot_*                →  private copy (0700)           →  ~/.<name>
encrypted_*.age              →  age decryption                →  ~/.<name>
dot_config/*                 →  copy mode                     →  ~/.config/<name>
.chezmoiscripts/*            →  lifecycle scripts             →  brew install, defaults write, launchctl load
Agentfile.yaml + overlay     →  run_after_agentbrew-sync.sh   →  canonical global Agentfile → agentbrew sync
```

## Ownership Boundary

| Target | Owner | Notes |
|--------|-------|-------|
| `~/.zshrc`, `~/.zshenv`, `~/.gitconfig` | **dotfiles** | Symlinked to `home/*` |
| `~/.config/ghostty/`, `~/.config/starship.toml` | **dotfiles** | Copy-mode via `dot_config/` |
| macOS defaults (Finder, Spotlight, keyboard, etc.) | **dotfiles** | Via `macos*.sh` lifecycle scripts |
| `~/Library/LaunchAgents/com.dotfiles.*` | **dotfiles** | Via `launchagents/` templates |
| `DEVIN_MODEL` env var | **dotfiles** | In `home/zshrc.ai-tools` — opt-in via `use_ai_tools` |
| `~/.claude/`, `~/.cursor/mcp.json`, agent skills/rules | **agentbrew** | Via `Agentfile.yaml` |
| Orchestrator, personas, pipelines | **minsky** | Separate repo |

**Rule**: Never have both repos write to the same target path.

## Branch policy

- **Canonical repo**: `github.com/fyodoriv/dotfiles` is the canonical home.
- **Canonical branch**: **`feat/chezmoi`** (permanent). It is also the GitHub default branch. All branches and PRs target `feat/chezmoi`. The former `main` branch is retired; do not target it.
- **Normal flow on any machine**: create a short-lived feature branch, run `git push origin <branch>`, open a PR on github.com, and merge it. Run `git pull` on `feat/chezmoi` to get the latest.

## Privacy & security gates

This repo enforces a strict no-leak contract on its public history at
`github.com/fyodoriv/dotfiles`. **No @company.example email, no organization
identifier outside the configured private-reference gate, no hardcoded secret ever reaches
github.com.** Nothing rewrites history, so every gate runs before a commit
leaves the machine. The full design lives in [`SECURITY.md`](SECURITY.md). The
short version every contributor needs:

1. **Set a public-safe `user.email` in this repo:**
   ```
   git -C ~/apps/tooling/dotfiles config user.email <your-public@email>
   ```
   The `git` doctor check verifies this. Never commit under an
   @company.example identity. `ALLOW_PRIVATE_EMAIL=1` skips the pre-commit
   email check for one commit, but the pre-push gate still blocks that
   commit. No mapping can make a private email safe, because nothing
   rewrites history.

2. **The pre-commit hook (`git-hooks/pre-commit`) blocks** any staged
   file mentioning configured private identifiers (`lib/oss-readiness.sh` regex),
   any hardcoded secret pattern (GitHub PAT, AWS key, PEM, …), and any
   @company.example committer email. Bypass with `--no-verify` only as a
   last-resort emergency fix; later gates still fire.

3. **The pre-push hook (`git-hooks/pre-push`) applies a privacy gate** to
   pushes of dotfiles, agentbrew, and every repo in
   `config/public-push-remotes.txt` to github.com. It blocks any commit
   whose author or committer email matches the private-email pattern. It
   also blocks the push when a file changed in the pushed range (read at
   the pushed commit) matches the private-identifier pattern; the message
   lists file paths only. It also blocks a pushed commit whose added lines,
   file names, or message match; that message lists commit ids only. Both patterns come from the org overlay's `oss-readiness.env`,
   which `lib/oss-readiness.sh` loads. With no overlay, those two checks
   have nothing to match. The hook then delegates to the repo-local
   `hooks/pre-push`.

4. **`bats tests/no-internal-refs.bats`** + **`bats tests/oss-readiness-lib.bats`**
   lock the private-reference scanner and secret patterns in place.
   Adding a configured private identifier to the base repo fails the
   build.

5. **Adding tasks from any machine.** Two valid paths:
   (a) edit TASKS.md via the github.com web UI on a feature branch and
   open a PR — zero setup, works from a phone; (b) use `bin/add-task`
   from a local clone — it generates a properly-formatted entry, runs
   `make lint-tasks`, and prints the git commands for you.

The regex source of truth is `lib/oss-readiness.sh::OSS_READINESS_INTERNAL_PATTERN`.
Adding a new identifier to scrub requires updating that file, running
`bats tests/no-internal-refs.bats`, and either moving matches to the
overlay or generalizing the base repo text.

**Public-safe TASKS.md:** Base-repo task entries must pass
`tests/no-internal-refs.bats` before you push.
Use generic project tags like `PROJ-123` — not org ticket prefixes — in
base `TASKS.md`. Org-specific vendor names, ticket keys, and
hostnames belong in the org overlay or in operator-only docs, not in
tracked base-repo queue text. A failure of that gate after merge means
ship-it is incomplete until the gate passes.

## Model Configuration

Default-model policy (2026-06-02 operator directive). **Devin** defaults
to **GPT-5.5 XHigh Thinking Fast** via both the shell-level `DEVIN_MODEL`
env var and Devin's user config `agent.model`. Other agents keep their
separate defaults until explicitly changed; do not infer a cross-agent
model change from this Devin-only pin.

| Agent | Default tier | Identifier string | Config location | Owner |
|-------|--------------|-------------------|-----------------|-------|
| **Devin** | GPT-5.5 XHigh Thinking Fast | `gpt-5-5-xhigh-priority` | `DEVIN_MODEL` env var in `home/zshrc.ai-tools` AND `agent.model` in `~/.config/devin/config.json` | **dotfiles** (`modules/devin/doctor.sh` → `devin.model_default`) |
| **Windsurf** | Max + 1M | `claude-opus-4-8-max` + 1M Context toggle ON | Cascade UI (model picker) — persisted in `~/.codeium/windsurf/user_settings.pb` | **dotfiles advisory** (`modules/windsurf/doctor.sh` → `windsurf.cascade.model_tier` — UI-fixable, no auto-write of the binary protobuf) |
| **Claude Code** | Medium | `claude-opus-5-5` + `effortLevel: "medium"` | `~/.claude/settings.json` | **dotfiles** (`.chezmoiscripts/run_after_claude-settings-model.sh` + `modules/claude/doctor.sh` → `claude.model_default`; `Agentfile.yaml` `defaultModel`/`defaultEffort` for agentbrew model sync) |
| **Cursor** | Claude Code parity | `claude-opus-5-5-medium` (derived from `~/.claude/settings.json` `model=claude-opus-5-5`, `effortLevel=medium`) | `~/.cursor/cli-config.json`, Cursor IDE reactive storage (`~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` → `aiSettings.modelConfig`), and `cursor/subagentModelOverrides` | **dotfiles** (`.chezmoiscripts/run_after_cursor-agent-parity.sh` + `modules/cursor/doctor.sh` → `cursor.model_parity`) |
| **Cursor agents** | Editor settings parity | vim keybindings, font size/family, line numbers, word wrap from `~/Library/Application Support/Cursor/User/settings.json` | `~/.cursor/cli-config.json` (`editor.vimMode`), `state.vscdb` → `cursor/glass.editorPreferences`, `glass.display.settings` | **dotfiles** (same script + `modules/cursor/doctor.sh` → `cursor.agent_settings_parity`) |
| **Codex** | _carve-out_ | n/a — Codex is OpenAI-first (default `o3` / `gpt-5.X`); Anthropic isn't a first-class provider in `~/.codex/config.toml` | `~/.codex/config.toml` `model = "..."` (TOML top-level) | **operator** (carve-out — Codex defaults to OpenAI models; routing Codex through an Anthropic provider is out of scope for the tier-1 default) |
| **Gemini CLI** | _carve-out_ | n/a — Gemini CLI uses Gemini-family models only, not Anthropic | `~/.gemini/settings.json` | **operator** (carve-out — different model family entirely; "Opus 5.5 Medium" doesn't translate) |
| Per-persona `ANTHROPIC_MODEL` | — | varies | minsky `personaRunner.ts` | **minsky** (pipeline override) |

**Identifier-string gotchas (these have bitten us before — verify before changing):**

- **Devin** is pinned to `gpt-5-5-xhigh-priority`, matching the live `~/.config/devin/config.json` selector for GPT-5.5 XHigh Thinking Fast. The public base-model list prints `gpt-5.5`; the richer thinking/speed selector is the config value we enforce.
- **Claude Code** rejects effort suffixes such as `-max` outright — `claude-opus-5-5-max` errors at startup. Claude Code's CLI separates the base model id from the thinking level: model = `claude-opus-5-5` (with optional `[1m]` suffix for 1M context), thinking level = `effortLevel` in `~/.claude/settings.json` (persistable values are `low`, `medium`, `high`, `xhigh`; `max` is only available in-session via `/effort max`). The `~/bin/claude` wrapper installed by `.chezmoiscripts/run_after_claude-wrapper.sh` strips any leaked `ANTHROPIC_MODEL` env var so Claude Code uses its own configured selection — don't try to pin Claude Code's model via env var, it won't take. The settings.json pin is installed by `.chezmoiscripts/run_after_claude-settings-model.sh` (idempotent `jq` merge that preserves every other key Claude Code writes — hooks, MCPs, plugins, etc.). agentbrew writes the same two keys from `Agentfile.yaml` `defaultModel`/`defaultEffort`; `tests/claude-model-agentfile-consistency.bats` keeps both sources equal.
- **Cursor** does not use Claude Code's split `model` + `effortLevel` shape. The equivalent Cursor model id is the joined slug (`claude-opus-5-5-medium`); any `claude-opus-N-M` model maps the same way. Newer Cursor IDE catalogs list the base model (`claude-opus-5-5`) and take effort as a model parameter; for those, the script writes the base id with `effort` set and the catalog's first value for every other parameter, while the CLI and subagents keep the joined slug. The parity script seeds the IDE's SQLite-backed `aiSettings.modelConfig` for Agent/Composer surfaces from Claude Code, then mirrors that editor Agent config into Cursor CLI agents (`~/.cursor/cli-config.json`) and subagent overrides (`cursor/subagentModelOverrides` in the same SQLite DB). It intentionally leaves Cmd-K at Cursor's default because current Opus catalog entries do not advertise Cmd-K support.
- **Cursor agents** inherit editor UX from the same `settings.json` dotfiles symlinks into `~/Library/Application Support/Cursor/User/`. The agent parity script mirrors vim mode into `~/.cursor/cli-config.json` (`editor.vimMode`), Glass agent editor prefs into `cursor/glass.editorPreferences` (`keybindings`: `vim` when vscodevim settings are present), and font sizing into `glass.display.settings`. Color theme for in-IDE Glass editors follows `workbench.colorTheme` from that same settings file; the headless `cursor-agent` CLI has no theme field in `cli-config.json` and instead inherits terminal colors (see Cursor CLI docs — use `TERM_THEME=light` on light terminals if auto-detection fails).
- **Vitest extension discovery** is guarded in `cursor/settings.json` via `vitest.configSearchPatternExclude` (skips doc mirrors, worktrees, scrub dirs) plus `vitest.logLevel: info`. Doctor check: `cursor.vitest_discovery_guard`. See `docs/troubleshooting.md#vitest-extension-floods-output--spawns-hundreds-of-processes`.
- **Windsurf** model selection lives in a binary protobuf (`~/.codeium/windsurf/user_settings.pb`). Strings inside it show the catalog format: `claude-opus-4-X-{low,medium,high,xhigh,max}` plus a separate `1M Context` toggle. dotfiles does **not** write this file (agentbrew owns `~/.codeium/`, the windsurf module README explicitly carves this out); the operator picks the model in the Cascade UI. The `windsurf.cascade.model_tier` advisory check in `modules/windsurf/doctor.sh` scans the protobuf strings for both `claude-opus-4-8-max` and `1M Context` — present ⇒ pass; missing ⇒ advisory warning that points the operator at the UI fix path. The check is best-effort (it confirms the catalog includes the right entries but can't decode which one the operator actually selected without parsing the protobuf wire format).
- **Codex** is a Cognition / OpenAI CLI — its `-c model="..."` example uses `o3` and the `--oss` flag routes through local providers (Ollama / LMStudio). Routing Codex through an Anthropic provider would require a custom `model_providers` config + an Anthropic API key + a translation layer; it's not in scope for the tier-1 "Opus 5.5 Medium" default (`Agentfile.yaml` sets `modelOverrides.codex: null`). Codex stays at its built-in OpenAI default; the user picks the model per-invocation with `-m gpt-5.5` / `-m o3` / etc.
- **Gemini CLI** isn't installed on the M3 Max box (`command -v gemini` returns nothing). It would use Google's Gemini family natively; the Anthropic-shaped Opus tier doesn't apply. Carve-out documented; revisit if the user starts using Gemini regularly.

**Debugging:** wrong model? Check, in order:
1. `echo $DEVIN_MODEL` in a fresh shell → should print `gpt-5-5-xhigh-priority`.
2. `grep model ~/.config/devin/config.json` → `agent.model` should be `gpt-5-5-xhigh-priority`.
3. `grep DEVIN_MODEL ~/apps/tooling/dotfiles/home/zshrc.ai-tools` → confirms the dotfiles source of truth.
4. For Claude Code: `cat ~/.claude/settings.json | jq '.model, .effortLevel'` → `"claude-opus-5-5"` and `"medium"`. The fix path is `dotfiles-doctor --module claude --fix` (which sources `.chezmoiscripts/run_after_claude-settings-model.sh`) — never hand-edit settings.json, Claude Code rewrites it on shutdown.
5. For Cursor: `dotfiles-doctor --module cursor --fix` runs `.chezmoiscripts/run_after_cursor-agent-parity.sh`, which maps Claude Code's `claude-opus-5-5` + `medium` to Cursor's `claude-opus-5-5-medium`, mirrors the editor Agent model into Cursor CLI agents and `cursor/subagentModelOverrides`, and syncs agent vim/fonts/glass keybindings from editor `settings.json`.
6. For Windsurf: `dotfiles-doctor --module windsurf` reports `windsurf.cascade.model_tier` as ✓ (matched) or ⚠ (advisory drift). The check scans `~/.codeium/windsurf/user_settings.pb` strings for both `claude-opus-4-8-max` and `1M Context`; the actual selection is in the protobuf wire format and not directly grep-able. Fix path: open the Cascade UI → model picker → select "Claude Opus 4.8 Max" + enable the "1M Context" toggle. If the options aren't there, launch Windsurf once to let Cascade refresh the catalog from the server.

The teammate-facing recovery path lives in `docs/troubleshooting.md#devin-uses-the-wrong-model`.
