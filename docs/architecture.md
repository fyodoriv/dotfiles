# Architecture Overview

This document explains how the dotfiles repo works end-to-end. For file-level conventions, see [CONTRIBUTING.md](../CONTRIBUTING.md). For security boundaries, see [security-model.md](security-model.md).

## How chezmoi maps source to target

The repo root is the chezmoi source directory (`sourceDir: ~/apps/dotfiles`). chezmoi reads source files and writes target files to `~/`.

```
Source (repo)                     chezmoi transform          Target (~/)
─────────────                     ────────────────           ──────────
symlink_dot_zshrc.tmpl         →  render + symlink        →  ~/.zshrc → home/zshrc
dot_config/ghostty/config      →  copy                    →  ~/.config/ghostty/config
private_dot_ssh/config.tmpl    →  render + copy (0700)    →  ~/.ssh/config
encrypted_<name>.age         →  decrypt + copy           →  ~/.<name>
home/zshrc                        (not deployed directly — symlink target lives here)
```

**Symlink mode** (`symlink_dot_*.tmpl`): chezmoi creates a symlink from `~/.<name>` to `home/<name>` in the repo. Edits are live — no `chezmoi apply` needed.

**Copy mode** (`dot_*`): chezmoi copies the file to `~/.<name>`. Edits require `chezmoi apply` to propagate.

**Templates** (`*.tmpl`): rendered with chezmoi data (profile, enterprise, age_recipient, etc.) before deployment.

## Lifecycle script execution

On `chezmoi apply`, scripts in `.chezmoiscripts/` run automatically in this order:

```
1. run_once_bootstrap.sh          ← First-time setup (Xcode CLT, Homebrew)
2. run_onchange_brew.sh.tmpl      ← Homebrew packages (re-runs when Brewfile changes)
3. run_onchange_macos.sh.tmpl     ← macOS defaults (re-runs when macos*.sh changes)
4. run_onchange_launchagents.sh.tmpl ← LaunchAgents (re-runs when templates change)
5. run_after_agentbrew-sync.sh    ← AI agent config sync (every apply)
6. run_after_cache-inits.sh       ← Shell init caching (every apply)
7. run_after_devin-caffeinate.sh  ← Devin CLI title wrapper (every apply)
8. run_after_endpoint-security.sh ← Re-sign Homebrew bottles + uv pythons + endpoint shims (every apply)
9. run_after_install_local_llm.sh.tmpl ← Local-LLM pipx/model bootstrap when opted in
```

Within each group, scripts run alphabetically. `run_once_*` keys to filename hash (runs once ever). `run_onchange_*` keys to rendered content hash (re-runs when output changes). `run_after_*` runs on every apply.

## Module auto-discovery

The doctor system (`dotfiles-doctor`) auto-discovers modules by scanning `modules/*/doctor.sh`:

```
modules/
├── git/doctor.sh          ← Discovered automatically
├── macos/doctor.sh        ← No registration needed
├── ssh/doctor.sh          ← Just create the directory + doctor.sh
└── ...                    ← one directory per module
```

**Discovery flow:**
1. `dotfiles-doctor` reads chezmoi data (`profile`, `is_enterprise`)
2. Iterates over `modules/*/doctor.sh` (sorted alphabetically)
3. For each module, checks if it should run (profile gating, enterprise gating)
4. Sources the `doctor.sh` file (it runs in the doctor's shell context)
5. Each `check()` / `check_symlink()` / `check_managed()` call registers a result

**Gating**: modules gate themselves. Core-only modules (git, macos, ssh, etc.) run on all profiles. Full-only modules check `$DOTFILES_PROFILE`. Enterprise-only modules check `$IS_ENTERPRISE`.

## Shared agent memory

The full profile declares one local memory service, but AgentBrew owns its
runtime, MCP registration, and maintenance:

```
Agentfile.yaml
      │
      ▼
AgentBrew memory enable/fix
      │
      ├── ~/Library/LaunchAgents/com.agentbrew.mcp-memory.plist
      │     └── canonical HOME + pinned upstream server + SQLite-vector store
      ├── http://127.0.0.1:18765/mcp
      │     └── initialize → initialized → non-empty tools/list
      └── dotfiles memory
            └── compatibility shim to agentbrew memory
```

The daemon stays loopback-only. AgentBrew's memory LaunchAgent and maintenance
job use the same operator HOME and canonical plist path; AgentBrew also owns
`~/.cursor/mcp.json`. Dotfiles only declares `memory.enabled`, removes retired
`com.dotfiles.mcp-memory*` jobs during apply, and checks the identity through
`agentbrew memory status --json`. AgentBrew's readiness contract accepts JSON
or SSE responses, preserves `MCP-Session-Id`, and requires at least one
advertised tool before doctor, sync, login, or URL probes report success.
The memory doctor module delegates project-memory freshness and the read-only
transport compatibility report back to AgentBrew. It does not inspect
`~/.claude/projects` or issue its own HTTP requests. Global recall is still the
default; provenance tags only enable explicit project filtering.
Cursor's existing in-process host remains a separate boundary: after a daemon
restart, use **Developer: Reload Window** or fully reopen Cursor.

`/learn-repos` stores source-backed dossiers and procedures in this same
backend. Repository answers require exact repo, revision, and source-fingerprint
tags with `tag_match: all`; stale or superseded candidates cannot win on quality
score alone. Detailed mechanics live in
[`learn-repos-reference.md`](learn-repos-reference.md).

## Doctor check framework

Each `doctor.sh` uses functions from `lib/output.sh`:

```
check <id> <description> <test_cmd> <fix_cmd>
  │      │        │           │          │
  │      │        │           │          └── Command to run in --fix mode
  │      │        │           └── Eval'd; exit 0 = pass, non-zero = fail
  │      │        └── Human-readable description
  │      └── Unique kebab-case ID (e.g., "git.pull_rebase")
  │
  └── Skipped if ID is in ~/.dotfiles-overrides

check_symlink <id> <source> <target>     ← Verifies symlink exists and points correctly
check_managed <id> <source> <target>     ← Verifies chezmoi-managed file (copy or symlink)
check_defaults <id> <desc> <domain> <key> <expected> <type>  ← Verifies macOS default
```

**Severity**: each module has a `severity` file (`critical`, `important`, `performance`, `cosmetic`). This affects display order and exit codes but not execution.

## Constitutional rules map

`AGENTS.md` / `CLAUDE.md` carry the repo-local constitutional rules for
contributors and agents. The rules are a projection of three upstream/peer
surfaces:

| Source | What dotfiles inherits | Dotfiles-owned enforcement surface |
|--------|------------------------|------------------------------------|
| `VISION.md` | G1 self-healing, G2 agentbrew ownership, G3 no-leak public repo, G4 overlay forkability | doctor modules, `Agentfile.yaml`, privacy hooks, `tests/no-internal-refs.bats` |
| agentbrew `templates/AGENTS.md` + `VISION.md` | reuse before implementation, generated-agent-config ownership, task backend shape, git/public-write safety | `Agentfile.yaml`, `bin/gh`, `git-hooks/*`, `agentbrew/hooks/manifest.yaml` backstops |
| Minsky `vision.md` constitution | rule #1 reuse, #3 doc/test-first, #6 stay alive, #9 HDD metadata, #10 deterministic gates, #16 default-by-default, #17 proactive healing | `make check`, `make lint-tasks`, `make lint-tasks-rule9`, doctor modules, Bats tests |

Each numbered rule in [`AGENTS.md`](../AGENTS.md#rules-for-editing) names either
a deterministic gate (`make check`, Bats, doctor checks, git hooks, CI scripts)
or an explicit advisory-only status when dotfiles has not mechanized the rule
yet. This avoids overclaiming CI coverage while keeping reviewer discussion tied
to stable rule numbers.

## Profile system

Two profiles control what gets deployed:

```
                    core                    full
                    ────                    ────
Modules:            7 baseline              35 discovered (feature-gated)
Brew packages:      `make count` (core)     `make count` (full)
macOS defaults:     90 (macos.sh)           90 + 30 + 29 = 149 (visual + apps)
LaunchAgents:       7                       13+
```

Profile is stored in `~/.config/chezmoi/chezmoi.yaml` as `data.profile`. Changed via:
- `chezmoi init` (first setup prompt)
- `dotfiles profile core|full` (runtime switch)

**How profiles gate content:**

1. **Files**: `.chezmoiignore` uses Go template conditions to exclude files:
   ```
   {{ if ne .profile "full" }}
   symlink_dot_ideavimrc.tmpl
   {{ end }}
   ```

2. **Brew packages**: `run_onchange_brew.sh.tmpl` wraps full-only packages in conditions:
   ```
   {{ if eq .profile "full" }}
   brew "dockutil"
   {{ end }}
   ```

3. **Modules**: doctor modules check `$DOTFILES_PROFILE` and `return 0` if not applicable.

4. **LaunchAgents**: `run_onchange_launchagents.sh.tmpl` conditionally renders agents.

## Data flow diagram

```
User runs: chezmoi apply
    │
    ├── 1. Read chezmoi.yaml (profile, is_enterprise, use_encryption, ...)
    │
    ├── 2. Process source files
    │   ├── Render *.tmpl templates with chezmoi data
    │   ├── Filter via .chezmoiignore (profile-gated)
    │   ├── Decrypt encrypted_*.age (if use_encryption: true)
    │   └── Deploy: symlinks, copies, private copies
    │
    ├── 3. Run lifecycle scripts (in order)
    │   ├── run_once_bootstrap.sh (first time only)
    │   ├── run_onchange_brew.sh.tmpl → brew bundle
    │   ├── run_onchange_macos.sh.tmpl → defaults write
    │   ├── run_onchange_launchagents.sh.tmpl → launchctl load
    │   ├── run_after_agentbrew-sync.sh → agentbrew sync
    │   ├── run_after_cache-inits.sh → cache shell inits
    │   ├── run_after_devin-caffeinate.sh → install title wrapper
    │   └── run_after_install_local_llm.sh.tmpl → local-LLM bootstrap when opted in
    │
    └── Done. Shell restart picks up new config.

User runs: dotfiles doctor [--fix]
    │
    ├── 1. Read chezmoi data (profile, is_enterprise)
    ├── 2. Scan modules/*/doctor.sh
    ├── 3. For each module:
    │   ├── Check profile/enterprise gates
    │   ├── Source doctor.sh
    │   └── Each check() → pass/fail/skip/fix
    └── 4. Print summary (pass/fail/warn counts)
```

## Adding a LaunchAgent

LaunchAgents are macOS scheduled tasks that run in the background. The dotfiles repo manages LaunchAgents for automation (sync, doctor, cleanup, git-maintain, etc.).

### Step-by-step

1. **Create the plist template** in `launchagents/`:

   ```bash
   # Name format: com.dotfiles.<short-name>.plist.tmpl
   touch launchagents/com.dotfiles.my-task.plist.tmpl
   ```

2. **Write the plist** using standard macOS plist XML with chezmoi template variables:

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
     "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>Label</key>
       <string>com.dotfiles.my-task</string>
       <key>ProgramArguments</key>
       <array>
           <string>/bin/bash</string>
           <string>{{ .chezmoi.homeDir }}/{{ .dotfiles_dir }}/bin/my-task</string>
       </array>
       <key>StartCalendarInterval</key>
       <dict>
           <key>Hour</key>
           <integer>9</integer>
           <key>Minute</key>
           <integer>0</integer>
       </dict>
       <key>StandardOutPath</key>
       <string>{{ .chezmoi.homeDir }}/.local/share/dotfiles/logs/my-task.log</string>
       <key>StandardErrorPath</key>
       <string>{{ .chezmoi.homeDir }}/.local/share/dotfiles/logs/my-task.log</string>
       <key>EnvironmentVariables</key>
       <dict>
           <key>LANG</key>
           <string>C.UTF-8</string>
           <key>PATH</key>
           <string>{{ if eq .chezmoi.arch "arm64" }}/opt/homebrew/bin:{{ end }}/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:{{ .chezmoi.homeDir }}/bin</string>
           <key>HOME</key>
           <string>{{ .chezmoi.homeDir }}</string>
       </dict>
   </dict>
   </plist>
   ```

   Available chezmoi variables: `{{ .chezmoi.homeDir }}`, `{{ .dotfiles_dir }}`, `{{ .chezmoi.arch }}`, `{{ .profile }}`.

3. **Gate behind profile** (if full-only): add a case to `should_skip_agent()` in `.chezmoiscripts/run_onchange_launchagents.sh.tmpl`:

   ```bash
   my-task)
     [ "$PROFILE" != "full" ] && return 0 ;;
   ```

   Core-profile agents (sync, doctor, cleanup, git-maintain, capslock-control, gui-path, network-resilience) do not need gating.

4. **Deploy**: `chezmoi apply` — the `run_onchange_launchagents.sh.tmpl` script auto-detects new plist files, renders templates, and loads them via `launchctl`.

5. **Test manually**:

   ```bash
   # Verify it loaded
   launchctl list | grep com.dotfiles.my-task

   # Force an immediate run
   launchctl start com.dotfiles.my-task

   # Check logs
   tail -f ~/.local/share/dotfiles/logs/my-task.log

   # Unload if needed
   launchctl unload ~/Library/LaunchAgents/com.dotfiles.my-task.plist
   ```

### Schedule options

| Key | Example | Meaning |
|-----|---------|---------|
| `StartCalendarInterval` | `Hour: 9, Minute: 0` | Run daily at 9:00 AM |
| `StartCalendarInterval` | `Weekday: 1, Hour: 9` | Run Monday at 9:00 AM |
| `StartInterval` | `300` | Run every 300 seconds |
| `RunAtLoad` | `true` | Run immediately when loaded (at login) |

### Conventions

- Label must match filename: `com.dotfiles.<name>` in both the plist `<Label>` and the filename
- Always set `PATH` and `HOME` in `EnvironmentVariables` (LaunchAgents run with minimal env)
- Always set `LANG=C.UTF-8` in `EnvironmentVariables`. launchd sets no locale, and without one the `bin/awk` shim (Homebrew gawk) fails every regex match that is not anchored at the start of the line. `tests/launchagents.bats` enforces this for every plist.
- Log to `~/.local/share/dotfiles/logs/<name>.log` (stdout + stderr)
- Use `.plist.tmpl` extension if the agent needs chezmoi variables; plain `.plist` if it doesn't
- Agents that depend on external tools should check tool presence in `should_skip_agent()`

## Key environment variables

| Variable | Set by | Used by | Purpose |
|----------|--------|---------|---------|
| `DOTFILES_DIR` | `bin/dotfiles`, doctor | All scripts | Repo root path |
| `DOTFILES_PROFILE` | Doctor reads from chezmoi | Module gating | `core` or `full` |
| `IS_ENTERPRISE` | Doctor reads from chezmoi | Module gating | `true` or `false` |
| `DOTFILES_REPOS_DIR` | User's shell config | Scripts that scan repos | Override `$HOME/apps` |
| `FIX_MODE` | `dotfiles-doctor --fix` | Check functions | Enable auto-repair |

## Chezmoi template variables

All variables are defined in `.chezmoi.yaml.tmpl` and stored in `~/.config/chezmoi/chezmoi.yaml` under the `data:` key.

| Variable | Type | Default | Used by |
|----------|------|---------|---------|
| `profile` | string | `"full"` | `.chezmoiignore`, brew template, launchagents template |
| `is_enterprise` | bool | `false` | `.chezmoiignore`, enterprise module gate, chrome/claude modules |
| `work_email_domain` | string | `"example.com"` (enterprise: `"company.example"`) | Chrome module (work profile detection) |
| `github_enterprise_host` | string | `"github.example.com"` (enterprise: `"github.company.example"`) | Claude module (GHE repo checks) |
| `dotfiles_dir` | string | `"apps/dotfiles"` | All LaunchAgent plist templates |
| `auto_upgrade` | bool | `false` | Launchagents template (upgrade agent) |
| `use_ai_tools` | bool | `false` | `.chezmoiignore` (zshrc.ai-tools) |
| `use_encryption` | bool | `false` | `.chezmoiignore` (encrypted files) |
| `git_work_name` | string | `""` | `~/.gitconfig.local` (user name for work/default identity) |
| `git_work_email` | string | `""` (enterprise: `your.username@<work_email_domain>`) | `~/.gitconfig.local` (user email for work/default identity) |
| `git_personal_enabled` | bool | `false` | `.chezmoiignore`; git doctor; run_onchange hook for `~/.gitconfig.local` |
| `git_personal_name` | string | `""` | `~/.gitconfig.personal` (prompted only when `git_personal_enabled` is true) |
| `git_personal_email` | string | `""` | `~/.gitconfig.personal` (prompted only when `git_personal_enabled` is true) |

Enterprise-only variables (`work_email_domain`, `github_enterprise_host`) are only prompted when `is_enterprise: true`. Non-enterprise installs use the generic defaults shown above.

### Split git identity

When `git_personal_enabled: true`, chezmoi writes `~/.gitconfig.personal` from `git_personal_name` + `git_personal_email` and runs `.chezmoiscripts/run_onchange_after_git-personal-includeif.sh.tmpl` to inject a `# BEGIN/END git-personal-includeif` block into `~/.gitconfig.local`. The block uses `[includeIf "hasconfig:remote.*.url:..."]` to load the personal identity whenever the current repo has any `github.com` remote. Enterprise remotes (`github.company.example` or custom `github_enterprise_host`) keep the default `git_work_*` identity. Flip the prompt to `false` and re-apply to remove the block cleanly.

## Canonical branch: `feat/chezmoi`

`github.com/fyodoriv/dotfiles` is the only canonical home. It uses
`feat/chezmoi` as the permanent canonical development branch, which is also
the GitHub default branch. The former `main` branch is retired; all origin
branches and PRs target `feat/chezmoi`.

The flow is the same on every machine: create a short-lived feature branch,
run `git push origin <branch>`, open a PR on github.com, and merge it. Run
`git pull` on `feat/chezmoi` to get the latest.

## Development and applied checkouts

A machine can hold two checkouts of this repo:

- **Development checkout** (for example `~/apps/tooling/dotfiles`): on the canonical branch. You edit, commit, and push feature branches here.
- **Applied checkout** (for example `~/apps/tooling/dotfiles-applied`): a linked worktree on `applied/<canonical branch>` that tracks `origin/<canonical branch>`. It is chezmoi's `sourceDir`, `~/.config/dotfiles/env.sh` sets `DOTFILES_DIR` to it, and its `bin/` is on `PATH`. Every home link, git `core.hooksPath`, and LaunchAgent points into it. `dotfiles-sync` only fast-forwards it and re-applies chezmoi; it never commits there.

Keep `$HOME` pointed at the applied checkout only:

- `.chezmoiscripts/run_before_00-refuse-foreign-source.sh` stops any `chezmoi apply` whose source is not the configured `sourceDir`. To switch on purpose, run `chezmoi init --source <dir>`, or set `DOTFILES_ALLOW_SOURCE_SWITCH=1` for one apply.
- `dotfiles doctor` checks and heals home links and `core.hooksPath` against `chezmoi source-path`, even when it runs from the development checkout.
- The doctor check `chezmoi.managed_symlinks_current` fails when any chezmoi-managed symlink points somewhere other than its target state.
