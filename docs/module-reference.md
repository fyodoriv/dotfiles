# Doctor Module Reference

`dotfiles doctor` runs health checks across modules. This document lists every module, what it checks, and what `--fix` can auto-repair.

**Profile and gate legend:**
- Modules under **Critical / Important / Performance / Cosmetic** headings reflect severity, not profile.
- Core modules run in both `core` and `full` profiles.
- Full-only modules run only when `profile: full`.
- On `profile: core`, checks for tools that only `full` installs are skipped unless the tool is installed: tmux and Ghostty (`terminal`), JetBrains IDEs and `~/.ideavimrc`, VS Code, agent-browser, Dock folders (`macos`), and the `extras` configs. A fresh core Mac then shows no failure for a tool it never installed.
- `enterprise` — requires `dotfiles enterprise on` (`is_enterprise: true`).
- `ai-tools` — requires `use_ai_tools: true` in chezmoi config.

## Quick start — most impactful checks

New to this repo? These checks deliver the highest value for team onboarding:

| Check ID | Module | Why it matters |
|----------|--------|---------------|
| `git.pull_rebase` | git | Sets `pull.rebase = true` — avoids merge commits on `git pull` |
| `macos.key_repeat` | macos | Fastest key repeat speed — essential for vim-style navigation |
| `ssh.agent_keychain` | ssh | macOS Keychain stores SSH passphrases — no re-typing after restart |
| `tools.fd` | tools | `fd` replaces `find` — faster, respects `.gitignore` |
| `tools.ripgrep` | tools | `rg` replaces `grep` — fast code search across large repos |
| `workflow.launchagent_sync` | workflow | Auto-commits dotfiles changes every 30 min — no manual syncing |
| `git.delta_pager` | git | `delta` as git pager — syntax-highlighted, side-by-side diffs |
| `macos.spotlight_exclusions` | macos | Stops Spotlight from indexing `node_modules`, `.git`, caches |

Run just these: `dotfiles doctor --module git --module macos --module ssh --module tools --module workflow`

## How checks work

| Function | What it does | Auto-fix |
|----------|-------------|----------|
| `check id desc test_cmd fix_cmd` | Runs `test_cmd`; if it fails, runs `fix_cmd` in fix mode | Only if `fix_cmd` is non-empty |
| `check_advisory id desc test_cmd` | Runs `test_cmd`; if it fails, reports a warning | None |
| `check_symlink id src dst` | Verifies symlink `dst → src` | Creates symlink, backs up conflicting file |
| `check_managed id src dst` | Verifies chezmoi manages the file | `chezmoi apply` on the target |
| `check_defaults id desc domain key expected type` | Verifies macOS `defaults` value | `defaults write` with the expected value |

Modules are sorted by severity: **critical** → **important** → **performance** → **cosmetic**.

**Dynamic checks**: some modules generate checks at runtime based on what's installed. For example, the git module creates one check per discovered repo in `$DOTFILES_REPOS_DIR`, and the workflow module creates one check per expected LaunchAgent. Modules marked "dynamic" add checks based on your environment.

## Severity tiers

Every module declares one of four severity tiers in `modules/<name>/severity`. Tiers control sort order in `dotfiles doctor` output and the cascading `--severity LEVEL` filter.

| Tier | One-liner | Modules |
|------|-----------|---------|
| **critical** | Security & safety — failures need immediate attention | `security`, `ssh`, `workflow` |
| **important** | Core developer config — should be correct for daily work | `agent-browser`, `agentbrew`, `chezmoi`, `chrome`, `editor`, `git`, `local-bin`, `memory`, `personal-machine`, `resilience`, `shell`, `sync`, `upgrade` |
| **performance** | System performance — nice to have, not blocking | `macos`, `tools` |
| **cosmetic** | Personal preference — ok to skip | `claude`, `enterprise`, `extras`, `jetbrains`, `local-llm`, `prompt`, `terminal`; no `severity` file (defaults to cosmetic): `local-ai`, `minsky`, `obsidian`, `vscode`, `workspace` |

Filter usage:

```bash
dotfiles doctor --severity critical    # only critical (CI gating, fast)
dotfiles doctor --severity important   # critical + important
dotfiles doctor --severity performance # critical + important + performance
dotfiles doctor --severity cosmetic    # everything (the default when --severity is omitted)
```

Tiers cascade: `--severity LEVEL` runs LEVEL plus everything more severe. So `--severity critical` is the smallest, gating set; `--severity cosmetic` is the full audit.

For the per-tier rationale, decision rules, and the "what severity should my new module be?" guide, see [CONTRIBUTING.md § Module severity](../CONTRIBUTING.md#module-severity).

---

## Critical

### security (no auto-fix)

Runs as `dotfiles audit`. Uses direct pass/fail/warn calls (no `check()` wrapper).

| What it checks | Result |
|---------------|--------|
| `~/.ssh/` directory permissions = 700 | Fail if wrong |
| Private SSH key file permissions = 600 (per key) | Fail if wrong |
| `fd` available for SSH private-key enumeration | Warn if missing |
| `~/.ssh/config` permissions (600 or 644) | Warn if wrong |
| No global `ForwardAgent yes` in SSH config | Warn if present |
| No secrets (API_KEY, TOKEN, etc.) in tracked git files; fixtures require explicit paths or `# dotfiles-secret-allowlist: reason` | Fail if found |
| No `.env` files tracked in git | Fail if found |
| Sensitive files not world-readable (`.netrc`, `.npmrc`, `.aws/credentials`, etc.) | Warn if readable |
| Git credential helper is not `store` (plaintext) | Warn if set |
| Git commit GPG signing enabled | Warn if not |
| Homebrew Mach-O bottles have an ad-hoc signature | Warn if unsigned or unverifiable |
| `security.agent_node_jobs_enabled`: with an approved agent Node (`DOTFILES_AGENT_NODE_BIN`), no `com.agentbrew.*` job that runs only that Node is disabled in launchd. A failure reads `com.agentbrew.check disabled while an approved agent Node exists`. Fix: `dotfiles-disable-blocked-node-automation`. | Fail if disabled |
| `security.deployed_la_locale`: deployed LaunchAgents of other owners (not `com.dotfiles.*`) that set `PATH` also set `LANG` or `LC_ALL`. One warning names them all. Fix each in its owning repo; dotfiles never edits them. | Warn if missing |

The Homebrew signature scan caches only successful results for 24 hours.
Cellar inventory changes, `DOTFILES_DOCTOR_REFRESH=1`, and
`dotfiles-adhoc-sign-bottles` invalidate or bypass the cache. Unsigned and
unverifiable scans are always repeated.

### ssh

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `managed.ssh` | SSH config managed by chezmoi | `chezmoi apply` |
| `security.ssh_permissions` | `~/.ssh/config` permissions = 600 | `chmod 600` |

### workflow (dynamic)

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `agent.*` | All deployed `com.dotfiles.*` LaunchAgents loaded | `launchctl load` |
| `spotlight.*` (11 dirs) | Dev directories (`~/apps`, `~/.cache`, `~/.npm`, `~/.yarn`, `~/.docker`, `~/.pyenv`, `~/.local`, `~/.config`, `~/Library/Caches`, etc.) have a `.metadata_never_index` marker **and** are out of the Spotlight index. The marker alone is not proof: on macOS 27, `~/apps` has it and is still indexed. The probe (`lib/spotlight-probe.sh`) runs `mdls -name _kMDItemFileName` on up to 3 direct children; `(null)` means not indexed. | `touch .metadata_never_index`. If the probe still finds an indexed item, the fix fails: add the dir in System Settings → Spotlight → Search Privacy. |
| `spotlight.agent_worktrees` | `~/apps/tooling/wt` is a symlink to `wt.noindex`. Spotlight skips a `.noindex` folder; it ignores the `.metadata_never_index` marker there. Runs only when `~/apps/tooling` exists. | Rename `wt` to `wt.noindex` and link `wt` to it. Existing worktree paths keep working. |

Spotlight check count varies based on which directories exist on your machine.

---

## Important

### git (dynamic)

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `symlink.gitconfig` | `~/.gitconfig` symlinked to dotfiles | Create symlink |
| `symlink.gitignore` | `~/.gitignore_global` symlinked | Create symlink |
| `symlink.gitcommit` | `~/.gitcommit_template` symlinked | Create symlink |
| `symlink.git_editor` | `~/.git-editor` symlinked | Create symlink |
| `git.local_config` | `~/.gitconfig.local` exists (user name/email) | None (user must create) |
| `git.xcode_license` | Xcode CLT license accepted (an unaccepted one breaks git, python3, clang, make) | None (run `sudo xcodebuild -license accept` yourself) |
| `git.pull_rebase` | `pull.rebase = true` | `git config --global` |
| `git.push_autosetup` | `push.autoSetupRemote = true` | `git config --global` |
| `git.pager_delta` | `core.pager = delta` | `git config --global` |
| `git.rerere` | `rerere.enabled = true` | `git config --global` |
| `git.diff_algorithm` | `diff.algorithm = histogram` | `git config --global` |
| `git.fetch_prune` | `fetch.prune = true` | `git config --global` |
| `git.rebase_autostash` | `rebase.autoStash = true` | `git config --global` |
| `git.fsmonitor_off` | `core.fsmonitor = false` | `git config --global` |
| `git.splitindex_off` | `core.splitIndex` not set | `git config --global --unset` |
| `git.maintenance_auto` | `maintenance.auto = true` | `git config --global` |
| `git.safe_aliases` | Git aliases avoid `git add -A` / `git add .` all-path staging | None |
| `git.safe_guard` | `git-safe` script is executable | `chmod +x` |
| `git.hooks_path` | `core.hooksPath` points to dotfiles | `git config --global` |
| `git.worktree_fsmon.*` | Per-repo fsmonitor off (repos with worktrees) | `git config` per repo |
| `git.gh_protocol` | `gh` uses SSH protocol (if `gh` installed) | `gh config set` |

### shell — full-only

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `symlink.zshenv` | `~/.zshenv` symlinked to dotfiles | Create symlink |
| `symlink.zshrc` | `~/.zshrc` symlinked to dotfiles | Create symlink |
| `managed.hushlogin` | `.hushlogin` managed by chezmoi | `chezmoi apply` |
| `shell.fzf_cached` | fzf init cached at `~/.cache/zsh/fzf.zsh` | Regenerate cache |
| `shell.zoxide_cached` | zoxide init cached at `~/.cache/zsh/zoxide.zsh` | Regenerate cache |
| `shell.dotfiles_on_path` | dotfiles `bin/` on PATH | None |
| `shell.node_options` | `NODE_OPTIONS` max-old-space-size configured (auto-detects RAM) | None |
| `shell.ulimit` | `ulimit -n 65535` in `.zshrc` | None |
| `shell.homebrew_no_autoupdate` | `HOMEBREW_NO_AUTO_UPDATE=1` set | None |
| `shell.zshrc_no_appends` | No installer lines appended to the tracked `home/zshrc` (`~/.zshrc` links to it) | Move the appended lines to `~/.zshrc.local` |

### editor

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `managed.editorconfig` | `.editorconfig` managed by chezmoi | `chezmoi apply` |
| `managed.npmrc` | `.npmrc` managed by chezmoi | `chezmoi apply` |

### tools

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `tool.fzf` | fzf installed | `brew install fzf` |
| `tool.eza` | eza installed | `brew install eza` |
| `tool.bat` | bat installed | `brew install bat` |
| `tool.fd` | fd installed | `brew install fd` |
| `tool.rg` | ripgrep installed | `brew install ripgrep` |
| `tool.zoxide` | zoxide installed | `brew install zoxide` |
| `tool.tree` | tree installed | `brew install tree` |
| `tool.htop` | htop installed | `brew install htop` |
| `tool.jq` | jq installed | `brew install jq` |
| `tool.gum` | gum installed | `brew install gum` |
| `tool.delta` | delta installed | `brew install git-delta` |
| `tool.fastfetch` | fastfetch installed | `brew install fastfetch` |
| `tool.gtimeout` | gtimeout installed (bounds doctor and hook timeouts) | `brew install coreutils` |

### plugins

One check per company plugin in `plugins.lock` (issue #145). A plugin that no
longer matches its lock (commit, tree hash, changed files, or capabilities) is
disabled, and this check prints the difference. Dev links print a warning.

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `plugins.<name>.verified` | Checkout matches its `plugins.lock` entry | None (`dotfiles plugin update <name> <ref>` reinstalls the locked tag; a `--dev` link: remove it, then add it again) |
| `plugins.<name>.lint` | No exported secrets in shell fragments; no `@latest` or unpinned `npx -y` | None (`dotfiles plugin lint <name>` lists lines) |
| `plugins.<name>.blocked_software` | No software the plugin blocks is installed | None (uninstall the listed items) |
| `plugins.staging_clean` | No `.staging.*` folder (with an `owner.pid` of a run that is gone) is left by an add or update that died without its exit handler (SIGKILL, power cut); the description names the folder | None (`dotfiles plugin list` finishes or rolls it back, or says what to move by hand) |

### sync

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `sync.launchagent` | Sync LaunchAgent loaded and running | None |
| `sync.recent` | Last sync within 2 hours | None |
| `sync.clean` | No uncommitted dotfiles changes | None |

### upgrade — full-only

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `upgrade.launchagent` | Upgrade LaunchAgent loaded | None |
| `upgrade.recent` | Last upgrade within 14 days | None |
| `upgrade.brew` | Homebrew installed | None |
| `upgrade.poetry_runs` | A non-uv `poetry` (official installer) still runs `--version`; only checked when one is on PATH | Moves the binary and `~/Library/Application Support/pypoetry/venv` aside to `*.bak` (no delete), then runs `uv tool install poetry` (`lib/poetry-repair.sh`). Only for a binary under `$HOME`; no fix when `uv` is missing. A second run is a no-op. |

### agentbrew (core checks + conditional MCP checks)

Conditional MCP checks only run when the MCP server is present in `~/.config/agentbrew/state.yaml`.

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `agentbrew.cli_available` | agentbrew CLI available | None |
| `agentbrew.agentfile_exists` | `Agentfile.yaml` in dotfiles | None |
| `agentbrew.initialized` | agentbrew state initialized | `agentbrew init` |
| `agentbrew.global_agentfile` | Global Agentfile exists | `agentbrew sync` |
| `agentbrew.global_agentfile_in_sync` | `~/.config/agentbrew/Agentfile.yaml` equals the merge that apply writes (base, kept plugin layers, owner rules, local layer, model layer) | `dotfiles-agentfile-resync`: writes that merge, then runs `agentbrew sync` in the background (log `~/.local/share/dotfiles/logs/agentbrew-sync-fix.log`) |
| `agentbrew.local_agentfile_valid` | `~/.config/dotfiles/Agentfile.local.yaml`, when present, is one document agentbrew can read, has no `hooks:` (also none through a YAML merge key), and uses lists for list keys; the description names the first problem ([agentbrew-setup.md](agentbrew-setup.md#add-an-mcp-server-on-one-mac)) | None (edit the file) |
| `agentbrew.plugin_agentfile_shared` | No company plugin Agentfile takes from the shared layer: no hook that would drop, replace, or weaken a shared agent hook, no `excludeAgents:`, no MCP server re-defined under a shared name, no `recommended: true`, no command or agent file named like a shared one in any letter case, no local skill that a `skills:` entry asks for (checked with the real `agentbrew agentfile merge`); apply skips such an Agentfile, and the description names the plugin and what it would take ([plugins.md](plugins.md#extension-points)) | None (fix the plugin, release a new tag) |
| `agentbrew.installed_agents_synced` | Every agent whose config folder exists (the parent of its skills folder, as agentbrew detects it) is synced, or the merged Agentfile lists it under `excludeAgents` on purpose. An old `excludeAgents:` entry leaves `detected: false` in `~/.config/agentbrew/state.yaml` until `agentbrew init` runs, so the agent silently misses the shared hooks and rules. The description names each such agent. | None: run `agentbrew init` to sync it, or ignore it on purpose by listing it under `excludeAgents:` in `~/.config/dotfiles/Agentfile.local.yaml` (the owner did this for `openhands`) |
| `agentbrew.env_*` | Required env vars for registered MCP servers | `agentbrew setup` |
| `agentbrew.memory_service_http` | Shared loopback memory MCP passes AgentBrew's stateful `initialize` → `notifications/initialized` → non-empty `tools/list` readiness contract when `use_ai_tools` is on and the memory MCP is registered | `agentbrew memory fix` |
| `agentbrew.memory_launchagent_identity` | Loaded memory LaunchAgent uses the canonical `com.agentbrew.mcp-memory` plist path and operator `HOME` | `agentbrew memory fix` |
| `agentbrew.memory_service_singleton` | No duplicate per-chat `mcp-memory-service` process is running beside the shared daemon | Stop the stale stdio memory server |
| `agentbrew.launchagent_node_pinned` | Every `com.agentbrew.*` plist and `~/.local/bin/node` use the Node that `~/.node-version` names (advisory; check in `lib/node-pin.sh`) | `dotfiles-node-upgrade $(cat ~/.node-version)` |
| `agentbrew.claude_no_npm_leftover` | No stale npm global `claude-code` install | `npm -g uninstall @anthropic-ai/claude-code` |

### memory

Delegates runtime ownership to AgentBrew. The compatibility module verifies that
the owning CLI is available and that its doctor passes, including MCP discovery,
behavioral bootstrap, schema, and backup health.

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `memory.agentbrew_available` | AgentBrew CLI is available for memory lifecycle | Install AgentBrew and run `agentbrew memory enable` |
| `memory.agentbrew_doctor` | AgentBrew reports daemon, bootstrap, schema, and backups healthy | `agentbrew memory fix` |
| `memory.project_sync_advisory` | Claude project-memory metadata is current; global recall remains available when drifted | `agentbrew memory sync-projects` (AgentBrew's own metadata check, without the dotfiles stamp) |
| `memory.transport_compatibility` | AgentBrew can produce read-only transport evidence before a security migration | `agentbrew memory fix; then agentbrew memory transport-report --json` |

### agent-browser

On `profile: core`, the module runs only when the `agent-browser` CLI is installed.

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `agent-browser.installed` | agent-browser CLI installed | None |
| `agent-browser.chrome_cdp` | Chrome CDP responsive on port 9223 | `ensure-chrome.sh` |
| `agent-browser.no_retired_chromes` | retired agent Chromes (9222/9224/9225) not installed | Unload and delete their plists |
| `agent-browser.config_cdp` | `~/.agent-browser/config.json` sets `"cdp": "9223"` | `dotfiles apply` |
| `agent-browser.temp_browser` | `bin/temp-browser` installed (one locked disposable browser) | None |
| `agent-browser.singleton_preflight` | singleton preflight helper installed | None |
| `agent-browser.reap_strays_helper` | stray target reap helper installed | None |
| `agent-browser.no_forwarded_launches` | launchd Chrome logs have no forwarded singleton launches | None |
| `agent-browser.no_stray_newtab_targets` | managed Chromes expose no stray blank/newtab targets | None |
| `agent-browser.remote_debugging_process_count` | Chrome remote-debugging process count stays at the managed threshold | None |
| `agent-browser.profile_preflight_guard` | zshrc.ai-tools guards launchd-owned AGENT_BROWSER_PROFILE | None |
| `agent-browser.legacy_launchers_safe` | legacy agent-browser launch scripts do not launch managed profiles | None |
| `agent-browser.profile_dir` | Chrome profile directory exists | `mkdir -p` |
| `agent-browser.dashboard_theme` | agents Chrome themed ORANGE (port 9223) | `dotfiles-set-persistent-chrome-themes 9223` |
| `agent-browser.spotlight_excluded` | `~/.agent-browser` has the marker and the index probe finds no indexed child | `touch .metadata_never_index` |
| `agent-browser.idle_timeout` | Idle timeout env var configured | None |
| `agent-browser.env_timeout` | Default timeout env var configured | None |
| `agent-browser.cdp_wrapper` | shell wrapper auto-uses `--cdp 9223` for default and dotfiles-assigned agent sessions | None |
| `agent-browser.focus_restore_helper` | `dotfiles-restore-focus-after-chrome` helper installed | None |
| `agent-browser.chrome_dock_guard` | `com.dotfiles.chrome-dock-guard` LaunchAgent installed (skipped when `chrome.dock_guard` is off) | None |
| `agent-browser.focus_restore_wired` | zshrc.ai-tools logs focus steals after agent-browser (never hides Chrome) | None |
| `agent-browser.restore_no_activate` | focus-restore helper never osascript-activates or hides Chrome | None |
| `focus.no_steal_open_flags` | `open -a` in bin/lib/launchagents uses `-g`, `--gj`, or `--background` | Fix offending script |
| `focus.no_osascript_activate` | no `to activate` in bin/lib/launchagents/macos-apps.sh | Fix offending script |
| `agent-browser.launchagent_headless` | managed Chromes use `--headless=new` at login | Reload LaunchAgents |
| `agent-browser.launchagent_no_startup_window` | managed Chromes use `--no-startup-window` at login | Reload LaunchAgents |
| `agent-browser.launchagent_no_offscreen_position` | managed Chromes omit `--window-position` (prevents flash-quit loop) | Reload LaunchAgents after removing off-screen flags from plist templates |
| `agent-browser.launchagent_runatload` | agent-browser-chrome LaunchAgent has `RunAtLoad=true` | None |
| `agent-browser.agent_session_isolation` | agent contexts use a named agent-browser session | None |
| `agent-browser.agent_session_wired` | zshrc.ai-tools assigns AGENT_BROWSER_SESSION in agent contexts | None |

### chezmoi

Sweeps every chezmoi-managed symlink. Catches links left behind when the repo moves.

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `chezmoi.installed` | advisory — `chezmoi` on PATH | — (hint: `brew bundle`) |
| `chezmoi.managed_symlinks_valid` | No chezmoi-managed symlink points at a missing target | `chezmoi apply --exclude=scripts` |
| `chezmoi.managed_symlinks_inventory` | advisory — lists the broken managed symlinks, when any | — |
| `chezmoi.managed_symlinks_current` | Managed symlinks point into chezmoi's current source checkout | `chezmoi apply --exclude=scripts` |

### local-bin

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `local_bin.dir_exists` | `~/.local/bin` exists | `mkdir -p ~/.local/bin` |
| `local_bin.on_path` | `~/.local/bin` is on `$PATH` | None (hint: `chezmoi apply`, then open a new shell) |

### personal-machine

Guards the one-time setup of a personal Mac.

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `personal-machine.global_email` | Global git `user.email` is the owner's personal address (not blank, not a company address) | Writes it to `~/.gitconfig.local` |
| `personal-machine.dotfiles_clone` | `~/apps/tooling/dotfiles` is a checkout of the dotfiles repo on `feat/chezmoi` | `git clone` |
| `personal-machine.agentbrew_clone` | `~/apps/tooling/agentbrew` is a checkout of the agentbrew repo on `main` | `git clone` |

### resilience

Keeps agents alive through lid close, network drops, and terminal close: tmux, sleepwatcher, network-watchdog, Amphetamine, and the agent keepawake manager. Setup wizard: `dotfiles-resilience-setup` (`--lid-close` only reports whether closing the lid sleeps the Mac).

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `resilience.tmux_installed` | tmux installed | None (hint: `brew install tmux`) |
| `resilience.agent_tmux_executable` | `agent-tmux` wrapper is executable | `chmod +x` |
| `resilience.sleepwatcher_binary` | sleepwatcher binary present | None (hint: `brew install sleepwatcher`) |
| `resilience.sleepwatcher_loaded` | sleepwatcher LaunchAgent loaded | None (hint: `launchctl bootstrap`) |
| `resilience.wakeup_hook_exists` | `~/.wakeup` hook fires network-watchdog | None (hint: `dotfiles apply`) |
| `resilience.network_watchdog_exec` | network-watchdog is executable | `chmod +x` |
| `resilience.network_watchdog_clean` | network-resilience LaunchAgent last exit is not 127 | None (hint: reload the LaunchAgent) |
| `resilience.network_watchdog_loaded` | network-resilience LaunchAgent loaded | None (hint: `launchctl bootstrap`) |
| `resilience.mas_installed` | `mas` (App Store CLI) installed | None (hint: `brew install mas`) |
| `resilience.amphetamine_installed` | Amphetamine.app installed | None (hint: `dotfiles-resilience-setup`) |
| `resilience.amphetamine_stale_single_use` | advisory — no stale Amphetamine Single-Use assertion | — (hint: end the Amphetamine session) |
| `resilience.amphetamine_managed_session_policy` | Amphetamine has no generic trigger or automatic session | Applies the managed session policy |
| `resilience.amphetamine_sync_tool` | `dotfiles-amphetamine-sync` executable | `chmod +x` |
| `resilience.amphetamine_sync_in_sync` | Amphetamine preferences match `data/amphetamine-prefs.json` | None (hint: `dotfiles-amphetamine-sync`) |
| `resilience.agent_keepawake_script` | `dotfiles-agent-keepawake` executable | `chmod +x` |
| `resilience.agent_wake_recover_script` | `dotfiles-agent-wake-recover` executable | `chmod +x` |
| `resilience.agent_keepawake_loaded` | agent-keepawake LaunchAgent loaded (full profile with the Claude Code CLI or desktop app) | `launchctl bootstrap` or `dotfiles apply` |
| `resilience.agent_keepawake_battery_policy` | Keepawake covers AC and battery at or above 20% | `dotfiles apply` + kickstart |
| `resilience.agent_keepawake_lid_closed_automation` | advisory — Amphetamine Automation ready for lid-closed agent work | — (hint: approve Automation once) |
| `resilience.agent_keepawake_owned_amphetamine_state` | advisory — manager-owned Amphetamine session matches live agents | — (hint: `dotfiles-agent-keepawake`) |
| `resilience.agent_keepawake_idle_release` | advisory — manager releases sleep protection when no agent runs | — (hint: `dotfiles-agent-keepawake`) |
| `resilience.wakeup_agent_recover` | `~/.wakeup` runs `dotfiles-agent-wake-recover` | `dotfiles apply` |
| `resilience.no_legacy_cascade_caffeinate` | Legacy cascade-caffeinate LaunchAgent unloaded | `launchctl bootout` + remove plist |
| `resilience.stale_caffeinate` | advisory — no stale manager-owned caffeinate child | — (hint: `dotfiles-agent-keepawake`) |
| `resilience.ac_idle_timers_normal` | AC idle timers are normal outside agent work | `sudo pmset -c ...` |
| `resilience.pmset_tcpkeepalive` | advisory — TCP keepalive enabled | — (hint: `sudo pmset -a tcpkeepalive 1`) |
| `resilience.ulimit_sufficient` | `ulimit -n` is at least 4096 | None (hint: raise `ulimit -n` in `~/.zshrc`) |
| `resilience.launchd_maxfiles` | advisory — launchd maxfiles soft limit is at least 4096 | — (hint: `dotfiles-launchd-maxfiles` in a human terminal; needs sudo once) |
| `resilience.native_arm64_shell` | advisory — shell runs natively, not under Rosetta, on Apple Silicon | — |
| `resilience.node_native_arch` | advisory — active node is arm64-native on Apple Silicon | — |

---

## Performance

### macos

46 `check_defaults` checks (all auto-fix via `defaults write`) plus 4-6 special checks.

| Category | Check IDs | Count | What it verifies |
|----------|-----------|-------|-----------------|
| Animations | `macos.window_animations`, `scroll_animations`, `resize_time` | 3 | Window/scroll animations disabled |
| Keyboard | `key_repeat`, `initial_key_repeat`, `press_and_hold`, `autocorrect`, `autocapitalize`, `smartquotes`, `smartdashes`, `period_substitution`, `text_completion` | 9 | Fastest key repeat, no auto-correct/smart-quotes |
| Dock | `dock_autohide`, `dock_autohide_delay`, `dock_launch_anim`, `dock_minimize`, `dock_mru`, `dock_recents`, `dock_expose_speed` | 7 | Instant autohide, no animations |
| Finder | `finder_hidden_files`, `finder_pathbar`, `finder_statusbar`, `finder_folders_first`, `finder_extensions`, `finder_no_anim`, `finder_ext_warning`, `finder_search_scope`, `finder_column_view`, `finder_no_desktop` | 10 | Show hidden files, path bar, all extensions |
| DS_Store | `no_ds_store_network`, `no_ds_store_usb` | 2 | No .DS_Store on external volumes |
| Screenshots | `screenshot_type`, `screenshot_shadow` | 2 | PNG format, no shadow |
| Input | `mouse_speed`, `trackpad_speed`, `tap_to_click`, `three_finger_drag` | 4 | Speed settings, tap-to-click |
| System | `app_nap`, `crash_reporter`, `save_to_disk`, `expand_save`, `no_quarantine`, `password_after_sleep`, `password_after_sleep_delay`, `screensaver_idle_time`, `pmset_display_sleep_15`, `pmset_battery_sleep_15`, `pmset_battery_disk_sleep_15`, `tiling_edge` | 12 | App Nap off, save to disk, 15-minute idle lock, Gatekeeper quarantine off |
| Dock folders | `dock_applications`, `dock_downloads` | 2 | Applications grid + Downloads stack (requires dockutil; full profile only) |
| Dock reset | `dock_no_static_only` | 1 | Dock not in static-only mode |

---

## Cosmetic

### jetbrains (conditional)

On `profile: core`, an IDE settings folder counts only when its app is in `/Applications` or `~/Applications` (`JETBRAINS_APP_DIRS` overrides the list), and `symlink.ideavimrc` is skipped.

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `symlink.ideavimrc` | `~/.ideavimrc` symlinked to dotfiles | Create symlink |
| `symlink.ws_vmoptions` | WebStorm vmoptions symlinked (if WebStorm installed) | Create symlink |
| `symlink.ws_properties` | WebStorm idea.properties symlinked | Create symlink |
| `jetbrains.keymap` | WebStorm keymap installed | None |

### terminal

On `profile: core`, the tmux and Ghostty checks are skipped (core installs neither).

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `tool.tmux` | tmux installed | `brew install tmux` |
| `symlink.tmux` | `~/.tmux.conf` symlinked to dotfiles | Create symlink |
| `apps.no_rosetta_override` | Managed work apps lack `LSArchitecturePriority=x86_64` | Clear overrides via `chezmoi apply` / doctor `--fix` |
| `tool.ghostty.arch` | Ghostty not forced to x86_64 Rosetta | Clear Ghostty `LSArchitecturePriority` |
| `managed.ghostty` | Ghostty config managed by chezmoi | `chezmoi apply` |

### prompt

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `tool.starship` | Starship installed | `brew install starship` |
| `managed.starship` | `starship.toml` managed by chezmoi | `chezmoi apply` |

### extras — full-only

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `tool.dockutil` | dockutil installed | `brew install dockutil` |
| `managed.gradle` | `gradle.properties` managed by chezmoi | `chezmoi apply` |
| `managed.lazygit` | lazygit config managed by chezmoi | `chezmoi apply` |
| `managed.tigrc` | `.tigrc` managed by chezmoi | `chezmoi apply` |

### chrome

The chrome module enforces Work-profile routing on **two complementary axes**:
`chrome.default_profile` handles **cold launches** by patching `Local State`
(`bin/chrome-enforce-profile`), while `chrome.chromework_router` +
`chrome.default_browser` handle **already-running Chrome** and system
LaunchServices by routing every http(s) URL through
`~/Applications/ChromeWork.app` (`bin/chromework-install`). Both axes are
reasserted hourly by `com.dotfiles.chrome-profile` via `bin/chrome-heal`
(and on every `/ship-it` Step 12 `dotfiles doctor --module chrome --fix`).
`dotfiles apply` installs that LaunchAgent only on an enterprise Mac
(`is_enterprise`). Enterprise-only for the Work-profile checks — they need the configured
`work_email_domain` to detect which profile dir is Work. The three `defaults`
checks apply to any user with Chrome.

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `chrome.default_profile` | Chrome opens with Work profile on cold launch (enterprise only) | `chrome-enforce-profile` |
| `chrome.chromework_router` | ChromeWork URL router routes links to Work profile, runs open-url synchronously and survive-handoff activation (enterprise only) | `chromework-install --force` |
| `chrome.default_browser` | ChromeWork is system default browser for http(s) — auto-reasserted on apply/heal (enterprise only) | `chromework-install` |
| `chrome.devtools` | Chrome DevTools always available | `defaults write` |
| `chrome.full_urls` | Full URLs shown in address bar | `defaults write` |
| `chrome.swipe_nav` | Swipe navigation disabled | `defaults write` |

### claude — full-only · `ai-tools`

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `claude.settings_mcp_allowed` | MCP server allowed in settings | `agentbrew sync` |

Organization-specific Claude checks (e.g. cloned-MCP-repo verifications) live in a company plugin's `contributes.doctor_modules` (see [plugins.md](plugins.md)).

### local-ai (conditional)

Engine-agnostic local inference stack: LM Studio (`:1234`) or Ollama (`:11434`), plus `opencode serve` on `:4096`. Model checks run only for the engine that is installed or up. The module runs only when `local_ai_agents` is on (default: `use_local_ai` or `owner_machine`).

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `local-ai.engine_installed` | LM Studio or Ollama installed | `brew install --cask lm-studio` or `brew install ollama` |
| `local-ai.opencode_installed` | `opencode` binary present | opencode install script |
| `local-ai.opencode_signature_valid` | `opencode` code signature is valid | `codesign --force --sign -` |
| `local-ai.warmup_agent_loaded` | `com.dotfiles.local-ai-warmup` LaunchAgent registered | `launchctl bootstrap` |
| `local-ai.opencode_serve_agent_loaded` | `com.dotfiles.opencode-serve` LaunchAgent registered | `launchctl bootstrap` |
| `local-ai.ollama_agent_loaded` | Collision-safe `com.dotfiles.ollama` LaunchAgent registered (Ollama only) | `launchctl bootstrap` |
| `local-ai.inference_api_responding` | At least one inference API responds | Runs `local-ai-warmup` |
| `local-ai.opencode_serve_api` | `opencode serve` responds on `:4096` | `launchctl kickstart -k` |
| `local-ai.lmstudio_primary` / `local-ai.lmstudio_small` | LM Studio primary and small models on disk | `lms get` |
| `local-ai.ollama_primary` / `local-ai.ollama_small` | Ollama primary and small models on disk | `ollama pull` |
| `local-ai.oc_alias` | `oc` alias defined for fast attach to `opencode serve` | None (hint: `dotfiles apply`) |
| `local-ai.opencode_tools_enabled` | `opencode.json` has an Ollama model with `tools: true` | None (hint: edit `~/.config/opencode/opencode.json`) |
| `local-ai.opencode_mcp_format` | `opencode.json` MCP entries use the type + command-array schema | None (agentbrew owns `~/.config/opencode/`) |

### local-llm

Optional local LLM via `mlx-lm` on Apple Silicon. Tool checks are advisory when `use_local_ai` is `false`. See [docs/local-llm.md](local-llm.md).

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `local-llm.arch.arm64_native` | advisory — shell runs native arm64 (Apple Silicon only) | — |
| `local-llm.pipx` | pipx installed | `brew install pipx` |
| `local-llm.aider` | aider installed (pipx `aider-chat`) | `dotfiles apply` |
| `local-llm.huggingface_cli` | Hugging Face CLI installed (`hf` or `huggingface-cli`) | `dotfiles apply` |
| `local-llm.mlx_lm` | `mlx_lm.server` on PATH (Apple Silicon only) | `brew install mlx-lm` |
| `local-llm.server.reachable` | advisory — `mlx_lm.server` reachable | — (hint: start `mlx_lm.server`) |
| `local-llm.bootstrap.sentinel` | advisory — operator opted into the model download (sentinel file) | — |
| `local-llm.model.weights_cached` | advisory — model weights cached under `~/.cache/huggingface/hub` | — |

### minsky

The minsky orchestrator checkout, its PATH shim, and its CLI. `MINSKY_REPO` overrides the repo path.

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `minsky.repo_exists` | minsky repo present | `git clone` |
| `minsky.repo_is_git_checkout` | Repo is a valid git checkout (HEAD resolves) | None (hint: re-clone) |
| `minsky.shim_symlinked` | `~/.local/bin/minsky` links to `<repo>/bin/minsky` | `ln -sf` |
| `minsky.help_runs` | `minsky --help` exits 0 | None (hint: `pnpm install` in the repo) |
| `minsky.observer_log_present` | advisory — `<repo>/.minsky/observer.log` present | — (hint: `minsky --once`) |
| `minsky.iter_log_recent` | advisory — `iter-once.log` present | — (hint: `minsky --once`) |

### obsidian — full-only, opt-in

Runs only when chezmoi data has `obsidian: true`. Skipped when `brew_skip` or the `brew.skip` core option lists `obsidian`. Any `tool.<name>` check is skipped when `brew_skip` lists `<name>`.

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `tool.obsidian` | Obsidian installed | None (hint: `brew install --cask obsidian`) |
| `obsidian.vault_exists` | Vault has a `.obsidian/` dir | `mkdir -p` |
| `obsidian.vim_mode` | Vim mode enabled in the vault | None |
| `obsidian.daily_folder` | `daily/` folder exists | `mkdir -p` |
| `obsidian.templates_folder` | `templates/` folder exists | `mkdir -p` |

### vscode (dynamic)

VS Code settings, keybindings, and extensions from `vscode/`. On `profile: core`, the module runs only when the app is installed (`VSCODE_APP` overrides its path). Adds one check per extension in `vscode/extensions.txt` (plus an overlay list when present).

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `vscode.installed` | VS Code installed | None |
| `vscode.cli` | `code` CLI available | None |
| `vscode.symlink.settings` | `settings.json` symlinked into `User/` | Symlink from dotfiles source |
| `vscode.symlink.keybindings` | `keybindings.json` symlinked into `User/` | Symlink from dotfiles source |
| `vscode.font.jetbrains_mono_nerd` | advisory — JetBrainsMono Nerd Font available | — (hint: Brewfile cask) |
| `vscode.extension.<slug>` | Each listed extension installed | `code --install-extension` |

### enterprise

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `enterprise.aws` | AWS CLI installed | `dotfiles-install-aws-gcloud --aws` |
| `enterprise.kubectl` | kubectl installed | `brew install kubernetes-cli` |
| `enterprise.gradle` | Gradle installed | `brew install gradle` |
| `enterprise.java` | Java installed | `brew install openjdk@21` |
| `enterprise.node` | Node.js installed | `brew install fnm` |
| `enterprise.docker` | Docker installed | `brew install docker` |
| `enterprise.gh` | GitHub CLI installed | `brew install gh` |
| `enterprise.jq` | jq installed | `brew install jq` |
| `enterprise.aws_user_dir` | `aws` resolves to `~/.local/bin/aws` (user-dir AWS CLI v2, not brew Python) | `dotfiles-install-aws-gcloud --aws` |
| `enterprise.gcloud_user_dir` | `gcloud` resolves to `~/.local/bin/gcloud` (user-dir Google Cloud SDK) | `dotfiles-install-aws-gcloud --gcloud` |

### workspace

Host-level visibility across every declared workspace folder (parents of
multiple repo checkouts). Discovery: `$XDG_CONFIG_HOME/tasks-md/workspaces.json` (default `~/.config/...`, written by `tasks workspaces add`)
→ `workspaces.yaml` → sentinel/structure scan of `$WORKSPACE_SCAN_ROOTS`
(default `~/apps`). See [docs/workspace.md](workspace.md).

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `workspace.discovery_lib` | `lib/workspace-discovery.sh` sources and defines `workspace_discover` | — |
| `workspace.declared_roots_exist` | every config-declared workspace path exists (vacuous pass without a config) | edit `~/.config/tasks-md/workspaces.{json,yaml}` |
| `workspace.declared_repos_are_git` | advisory — every repo (child dir with a `TASKS.md`) of a config-declared workspace is a git checkout (vacuous pass without a config) | — |
| `workspace.status_runs` | `dotfiles-workspace status` exits 0 | — |
| `workspace.any_discovered` | advisory — at least one workspace discovered | `touch <root>/.tasks-md-workspace` or set `WORKSPACE_SCAN_ROOTS` |
