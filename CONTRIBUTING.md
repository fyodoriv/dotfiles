# Contributing

## Getting started

Make your first change in five steps:

```bash
# 1. Clone (if you haven't already)
git clone https://github.com/<your-org>/dotfiles.git ~/apps/dotfiles

# 2. Verify everything passes
cd ~/apps/dotfiles
make check

# 3. Make a change — for example, add a check to a doctor module
echo 'check "mymod.test" "my test check" "true" ""' >> modules/tools/doctor.sh

# 4. Run affected tests
make test

# 5. Apply your change and see it live
dotfiles apply
dotfiles doctor
```

The typical edit cycle: change a file in the repo, run `make test` to verify, run `dotfiles apply` to deploy. If you changed a doctor module, run `dotfiles doctor` to see it in action.

## Development

```bash
make install-deps # install local validation tools
make lint         # shellcheck all scripts
make lint-tasks   # validate TASKS.md queue format
make test         # affected bats tests (cached, git-aware)
make test-all     # full bats suite (cached)
make check        # lint + TASKS.md lint + affected tests
make fmt          # format shell scripts with shfmt
make coverage     # run bats through bin/dotfiles-coverage line coverage
```

`make install-deps` installs the Homebrew tools used by those targets:
required for `make check`/tests (`shellcheck`, `bats-core`, `parallel`,
`chezmoi`, `fd`, `jq`) and the optional `shfmt` helper for
formatting.
`make coverage` is handled by the in-tree `bin/dotfiles-coverage` harness, so
no extra Homebrew formula is required for coverage. `make lint-tasks` also
needs Node/npm for the pinned
`npx -y @tasks-md/lint@<version>` package in `.tasks-lint-version`; use your
normal Node manager for that.

## Architecture

This repo is a chezmoi source directory. The repo root **is** the source dir (`sourceDir: ~/apps/dotfiles`).

### File modes

| Source naming | Mode | Deployed as |
|--------------|------|-------------|
| `symlink_dot_*.tmpl` + `home/*` | Symlink | `~/.<name>` → `home/<name>` (edit in place) |
| `dot_*` | Copy | `~/.<name>` (run `dotfiles apply` after editing) |
| `private_dot_*` | Private copy (0700) | `~/.<name>` |
| `encrypted_*.age` | Encrypted | Decrypted at apply time |
| `*.tmpl` | Template | Rendered with chezmoi data |

### Lifecycle scripts

In `.chezmoiscripts/`, scripts run automatically during `chezmoi apply`. Chezmoi executes them in order: `run_once_*` first, then `run_onchange_*`, then `run_after_*` (alphabetically within each group).

#### `run_once_*` — runs exactly once (keyed to filename hash)

| Script | What it does | Re-runs when |
|--------|-------------|--------------|
| `run_once_bootstrap.sh` | Installs Xcode CLT, Homebrew, chezmoi; creates `~/.gitconfig.local` | Only on first `chezmoi apply` (or if chezmoi state is wiped) |

#### `run_onchange_*` — runs when rendered script content changes

| Script | What it does | Re-runs when |
|--------|-------------|--------------|
| `run_onchange_brew.sh.tmpl` | `brew bundle` with inline Brewfile (core + full + enterprise packages) | Brewfile content changes, or `profile`/`is_enterprise` config changes |
| `run_onchange_macos.sh.tmpl` | Runs `macos.sh` defaults, plus `macos-visual.sh`/`macos-apps.sh` on full profile | Any edit to `macos.sh`, `macos-visual.sh`, or `macos-apps.sh` (SHA256 hashes embedded), or `profile` changes |
| `run_onchange_launchagents.sh.tmpl` | Renders plist templates, loads/reloads LaunchAgents | Any file added/changed/removed in `launchagents/`, or `profile`/`auto_upgrade` changes |

#### `run_after_*` — runs on every `chezmoi apply`

| Script | What it does | Notes |
|--------|-------------|-------|
| `run_after_agentbrew-sync.sh` | Runs `agentbrew sync` if Agentfile.yaml exists | Non-fatal (uses `set -uo pipefail`, not `-euo`) |
| `run_after_cache-inits.sh` | Caches `fzf`, `zoxide`, `starship`, `fnm` init output to `~/.cache/zsh/` | Enables fast shell startup |
| `run_after_devin-caffeinate.sh` | Installs restart-safe title wrapper for Devin CLI at `~/.local/bin/devin` | Idempotent — exits early if wrapper is already correct |

#### Skipping or forcing re-execution

- **Skip all scripts**: `chezmoi apply --exclude=scripts`
- **Force `run_onchange_*` re-run**: edit the source file (e.g., add a comment) to change the rendered hash
- **Force `run_once_*` re-run**: `chezmoi state delete-bucket --bucket=scriptState`
- **Skip a specific script**: no built-in mechanism; comment out the script body temporarily

## Adding a module

Each module is a directory in `modules/` with a `doctor.sh`:

```
modules/mymodule/
  doctor.sh           # health checks
```

### `doctor.sh`

Health checks are `source`d by `dotfiles-doctor`. Available functions:

| Function | What it checks |
|----------|---------------|
| `check <id> <desc> <test_cmd> <fix_cmd>` | Generic check with optional auto-fix |
| `check_symlink <id> <src> <dst>` | Symlink points to the right place |
| `check_managed <id> <src> <dst>` | Chezmoi-managed file (symlink or copy) |
| `check_defaults <id> <desc> <domain> <key> <expected> <type>` | macOS default value |

Example:

```bash
#!/bin/bash
check_symlink "symlink.myconfig" "$DOTFILES_DIR/home/myconfig" "$HOME/.myconfig"
check_managed "managed.myfile" "$DOTFILES_DIR/dot_myfile" "$HOME/.myfile"
check "mymod.tool_installed" "my-tool installed" "command -v my-tool" "brew install my-tool"
check_defaults "mymod.setting" "My setting enabled" "com.apple.finder" "ShowPathbar" "1" "bool"
```

The doctor auto-discovers your `doctor.sh` — no need to edit the doctor script itself.

Or use the scaffolding command:

```bash
dotfiles new-module mymodule --severity cosmetic
```

### Module severity

Each module declares its severity in `modules/<name>/severity` (one word). This controls sort order in `dotfiles doctor` output and filtering with `--severity`.

| Severity | Meaning | When to use |
|----------|---------|-------------|
| **critical** | Security and safety — failures need immediate attention | Checks that protect secrets, credentials, or file permissions. A failure here could expose sensitive data. |
| **important** | Core developer config — should be correct for daily work | Checks for tools and settings most developers use every day (shell, git, editor). A failure causes visible friction. |
| **performance** | System performance — nice to have | Checks that improve speed or reduce resource usage but don't block work. Failures cause slowness, not breakage. |
| **cosmetic** | Personal preference — ok to skip | Checks for optional tools, IDE settings, or appearance. Many users will legitimately skip these. |

**Examples by severity:**

| Severity | Module | Why this severity |
|----------|--------|-------------------|
| critical | `security` | Validates SSH key permissions (600), scans for leaked secrets in tracked files |
| critical | `ssh` | SSH config managed correctly — wrong config blocks git push/pull |
| critical | `workflow` | LaunchAgents loaded — auto-sync and auto-doctor depend on this |
| important | `git` | Gitconfig, hooks path, delta pager, performance settings — daily git workflow |
| important | `chrome` | Work Chrome link routing — Slack/Mail/Cursor links must reach ChromeWork |
| important | `shell` | Zsh symlinks, PATH, tool caches — broken shell config blocks everything |
| important | `editor` | Default editor set — affects git commit, crontab, etc. |
| performance | `macos` | Key repeat speed, Finder settings, animation removal — faster but not essential |
| performance | `tools` | CLI tools (fd, ripgrep, jq) — useful but the system works without them |
| cosmetic | `prompt` | Starship prompt config — purely visual preference |
| cosmetic | `jetbrains` | IDE keymap and settings — only for JetBrains users |
| cosmetic | `enterprise` | AWS, kubectl, Gradle — only needed by backend/DevOps roles |

## Adding a managed file

**Symlink mode** (for frequently-edited files):

```bash
dotfiles add ~/.config/foo/config.toml --module mymodule
```

**Copy mode** (for templated or infrequently-edited files):

```bash
dotfiles add ~/.config/foo/config.toml --copy --module mymodule
```

Both commands copy the file into the repo, create the chezmoi source entry, and add a doctor check to the module.

## Adding a Homebrew package

```bash
dotfiles brew-add my-tool                  # core profile
dotfiles brew-add my-tool --full-only      # full profile only
dotfiles brew-add my-tool --cask           # GUI app
```

Adds the package to the Brewfile section in `.chezmoiscripts/run_onchange_brew.sh.tmpl` and creates a doctor check.

## Adding a macOS default

```bash
dotfiles defaults-add com.apple.finder ShowPathbar 1 bool
```

Adds the `defaults write` command to the appropriate macOS script and creates a doctor check.

## Adding a LaunchAgent

See the step-by-step guide in [docs/architecture.md — Adding a LaunchAgent](docs/architecture.md#adding-a-launchagent). In short: create a plist template in `launchagents/`, gate it behind a profile in `should_skip_agent()` if needed, and run `chezmoi apply`.

## Adding time-tracking to a new script

`lib/stats.sh` is the single integration point for the time-saved feature surfaced by `dotfiles stats` and the shell-prompt widget. Any new bin script or LaunchAgent that does work the user could otherwise have done manually should call `log_run` after the work succeeds.

```bash
#!/bin/bash
set -euo pipefail

# shellcheck source=../lib/stats.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib/stats.sh"

# ... do the work ...

log_run sync                # 1 run × 3s estimate = 3s
log_run cleanup 5           # 5 units × 10s estimate = 50s
```

Two public functions:

- `log_run <task> [units]` — appends a JSONL entry to `$DOTFILES_STATS_FILE` (default `~/.dotfiles-stats.jsonl`). Best-effort: if the directory can't be created, it warns and returns silently — never fails the calling script.
- `get_time_saved_summary` — reads the stats file and prints a one-line summary like `42 runs, ~12m saved`. Used by `dotfiles-stats --oneliner` and shell-prompt widgets.

Per-task estimates live in `_task_estimate` inside `lib/stats.sh`. Adding a new task: add its name + per-unit-second estimate to the `case` block, source the lib in your script, and call `log_run <name>` after the success path. The recalc command (`dotfiles-stats --recalc`) re-applies the current estimates to historical entries so existing users' totals stay correct after estimate changes.

## Removing a managed file

```bash
dotfiles unmanage ~/.config/myapp/config.yaml
```

Removes a file from chezmoi management and cleans up its doctor check, but leaves the actual file on disk untouched. Handles both symlink-mode and copy-mode files automatically.

## Switching profiles

```bash
dotfiles profile              # show current profile
dotfiles profile core         # switch to core (team-friendly; run `make count` for live module totals)
dotfiles profile full         # switch to full (opinionated; run `make count` for live module totals)
```

Changes the chezmoi `profile` data key and runs `chezmoi apply` to add/remove files and packages. Requires `yq`.

## Toggling enterprise mode

```bash
dotfiles enterprise           # show current status
dotfiles enterprise on        # enable enterprise config
dotfiles enterprise off       # disable enterprise config
```

Controls the `is_enterprise` chezmoi data key. When on, enterprise-specific SSH config, Brew packages, and doctor modules are activated. Runs `chezmoi apply` after toggling. Requires `yq`.

## Profiles

Selected at `chezmoi init` time (stored in `~/.config/chezmoi/chezmoi.yaml`):

| Profile | Modules |
|---------|---------|
| `core` | git, macos, ssh, tools, workflow, sync, security |
| `full` | core + shell, editor, jetbrains, terminal, prompt, extras, upgrade, claude, cursor, agentbrew, agent-browser, chrome, devin, enterprise |

Profile controls which files chezmoi deploys (via `.chezmoiignore` conditions) and which Brew packages are installed (via conditions in the Brewfile template).

## Testing

Test files live in `tests/*.bats`:

| File | What it tests |
|------|--------------|
| `chezmoi.bats` | File deployment (symlinks, copies, XDG, permissions, profiles) |
| `doctor.bats` | Check/fix/override framework |
| `cli.bats` | `dotfiles` CLI subcommands |
| `audit.bats` | Security audit (SSH, secrets, sensitive files) |
| `smoke.bats` | Script hygiene (shebang, executable, no hardcoded paths) |
| `stats.bats` | Time-tracking stats |
| `git-maintain.bats` | Git maintenance |
| `git-safe.bats` | Safe git operations |
| `cleanup.bats` | Cache cleanup |
| `morning.bats` | Morning startup |
| `scaffolding.bats` | add, new-module, brew-add, defaults-add |

### Running tests

```bash
make test                     # affected tests only (fast, git-aware)
make test-all                 # full suite (cached)
make test-force               # full suite (no cache)
bats tests/doctor.bats        # run a single test file
bats tests/doctor.bats -f "check passes"   # run tests matching a filter
```

`make test` uses `bats-affected` to detect which test files cover your changed files. If you change shared infrastructure (`test_helper.bash`, `Makefile`, `lib/`), all tests run.

### Writing tests

Tests use [bats-core](https://github.com/bats-core/bats-core). Each `@test` block is an independent test case:

```bash
#!/usr/bin/env bats
load test_helper          # sets up isolated $HOME, $DOTFILES_DIR, helpers

@test "my-script does the right thing" {
  # setup: create test fixtures
  create_file "$TEST_HOME/.config/myapp/config" "key=old"

  # act: run the command under test
  run "$BATS_TEST_DIRNAME/../bin/my-script" --flag

  # assert: check exit code and output
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "expected text"
}
```

#### Test helper functions (`test_helper.bash`)

| Function | What it does |
|----------|-------------|
| `create_file <path> [content]` | Create a file with optional content |
| `assert_symlink <path> <target>` | Assert file is a symlink to expected target |
| `assert_file <path>` | Assert regular file exists |
| `assert_no_file <path>` | Assert file does not exist |

The helper sets `HOME=$TEST_HOME` and `DOTFILES_DIR=$TEST_DOTFILES` so tests never touch your real home directory.

#### Common patterns

**Structural tests** — verify a script has expected properties without running it:

```bash
@test "my-script uses strict mode" {
  grep -q 'set -euo pipefail' "$BATS_TEST_DIRNAME/../bin/my-script"
}
```

**Functional tests** — run the script in an isolated environment:

```bash
setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "my-script creates config file" {
  run "$BATS_TEST_DIRNAME/../bin/my-script" init
  [ "$status" -eq 0 ]
  [ -f "$HOME/.myconfig" ]
}
```

`smoke.bats` validates script hygiene for all `bin/` scripts automatically (shebang, executable, strict mode, no hardcoded paths).

## Forking

1. Fork the repo
2. `chezmoi init --source <your-fork-path>` to set up
3. Delete modules you don't want from `modules/`
4. Your `~/.gitconfig.local` and `~/.zshrc.local` stay private (gitignored, never overwritten)

**CI on forks**: if your fork inherits jobs that reference internal-only GitHub Enterprise actions (e.g. an `actions-<org>/<workflow>` reference), those jobs will show as "failed" on public forks — this is expected and harmless. All other CI jobs (lint, test, doctor) run independently via `if: !cancelled()` and will pass normally. To clean this up, drop the org-specific job from `.github/workflows/ci.yml` in your fork.

## Removing modules

The pre-commit hook blocks deletion of files in `modules/`. To delete a module:

```bash
git rm -r modules/mymodule
git commit --no-verify   # bypass the pre-commit protection
```

### Cross-module dependencies

Some modules depend on others. Verify before removing:

| Module | Depended on by | Notes |
|--------|---------------|-------|
| `tools` | shell (fzf/zoxide cache), git (delta pager) | Core utilities; most other modules are fine without it |
| `shell` | git (PATH for bin/), sync (stats) | Sets up `_dotfiles_bin` PATH |
| `extras` | macos (dockutil for Dock config) | macos gracefully skips if dockutil is missing |
| `agentbrew` | claude, cursor (MCP server registration) | Only matters if you use AI coding agents |

### Safe removal steps

1. Check the table above for anything that depends on the module
2. `git rm -r modules/<name>`
3. Run `dotfiles doctor` to verify no checks fail
4. Commit with `--no-verify` to bypass the pre-commit hook

## Conventions

- **Commit on `main`** — no feature branches for small changes
- **Conventional commits** — `feat:`, `fix:`, `docs:`, `chore:`, `test:`, `refactor:`
- **Header ≤72 characters**
- **Run `make check` before every commit**
- **Use `fd` instead of `find`** everywhere
- **Never hardcode `$HOME` paths**
- **No company-internal URLs** in tracked files — use `~/.zshenv.secrets` (gitignored)

## For contributors at an enterprise / employer

This repo is public. If you're contributing while working at a company, follow
these rules to prevent accidental exposure of internal information:

**Do commit:**
- Generic patterns that work for any company (e.g., `example.com` placeholders)
- Enterprise features gated behind `is_enterprise` chezmoi data
- Doctor checks using `$IS_ENTERPRISE` guards

**Do NOT commit:**
- Internal URLs, intranet hostnames, or internal IP ranges
- Credentials, API tokens, or passwords — use `~/.zshenv.secrets`
- Proprietary tool names or internal project codenames
- Internal Slack channel names or JIRA project keys
- Employee names or email addresses

**Where to put sensitive config:**
- `~/.zshenv.secrets` — environment variables, API tokens, service URLs
- `~/.zshrc.local` — internal aliases, PATH additions, tool configurations
- `~/.gitconfig.local` — enterprise credential helpers, internal git hosts

**Before committing, run:**
```bash
dotfiles audit    # checks for secrets in tracked files
make check        # lint + tests
```
