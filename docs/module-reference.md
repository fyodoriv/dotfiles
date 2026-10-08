# Doctor Module Reference

`dotfiles doctor` runs health checks across modules. This document lists every module, what it checks, and what `--fix` can auto-repair.

**Profile and gate legend:**
- Modules under **Critical / Important / Performance / Cosmetic** headings reflect severity, not profile.
- Core modules run in both `core` and `full` profiles.
- Full-only modules run only when `profile: full`.
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
| **important** | Core developer config — should be correct for daily work | `agent-browser`, `agentbrew`, `chezmoi`, `chrome`, `editor`, `git`, `memory`, `shell`, `sync`, `upgrade` |
| **performance** | System performance — nice to have, not blocking | `macos`, `tools` |
| **cosmetic** | Personal preference — ok to skip | `claude`, `cursor`, `enterprise`, `extras`, `jetbrains`, `prompt`, `terminal` |

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
| `spotlight.*` (11 dirs) | Dev directories excluded from Spotlight indexing (`~/apps`, `~/.cache`, `~/.npm`, `~/.yarn`, `~/.docker`, `~/.pyenv`, `~/.local`, `~/.config`, `~/Library/Caches`, etc.) | `touch .metadata_never_index` |

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

### agentbrew (core checks + conditional MCP checks)

Conditional MCP checks only run when the MCP server is present in `~/.config/agentbrew/state.yaml`.

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `agentbrew.cli_available` | agentbrew CLI available | None |
| `agentbrew.agentfile_exists` | `Agentfile.yaml` in dotfiles | None |
| `agentbrew.initialized` | agentbrew state initialized | `agentbrew init` |
| `agentbrew.global_agentfile` | Global Agentfile exists | `agentbrew sync` |
| `agentbrew.env_*` | Required env vars for registered MCP servers | `agentbrew setup` |
| `agentbrew.memory_service_http` | Shared loopback memory MCP passes AgentBrew's stateful `initialize` → `notifications/initialized` → non-empty `tools/list` readiness contract when `use_ai_tools` is on and the memory MCP is registered | `agentbrew memory fix` |
| `agentbrew.memory_launchagent_identity` | Loaded memory LaunchAgent uses the canonical `com.agentbrew.mcp-memory` plist path and operator `HOME` | `agentbrew memory fix` |
| `agentbrew.memory_service_singleton` | No duplicate per-chat `mcp-memory-service` process is running beside the shared daemon | Stop the stale stdio memory server |
| `agentbrew.claude_no_npm_leftover` | No stale npm global `claude-code` install | `npm -g uninstall @anthropic-ai/claude-code` |

### memory

Delegates runtime ownership to AgentBrew. The compatibility module verifies that
the owning CLI is available and that its doctor passes, including MCP discovery,
behavioral bootstrap, schema, and backup health.

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `memory.agentbrew_available` | AgentBrew CLI is available for memory lifecycle | Install AgentBrew and run `agentbrew memory enable` |
| `memory.agentbrew_doctor` | AgentBrew reports daemon, bootstrap, schema, and backups healthy | `agentbrew memory fix` |
| `memory.project_sync_advisory` | Claude project-memory metadata is current; global recall remains available when drifted | `dotfiles-memory-sync-projects` |
| `memory.transport_compatibility` | AgentBrew can produce read-only transport evidence before a security migration | `agentbrew memory fix; then agentbrew memory transport-report --json` |

### agent-browser

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `agent-browser.installed` | agent-browser CLI installed | None |
| `agent-browser.chrome_cdp` | Chrome CDP responsive on port 9223 | `ensure-chrome.sh` |
| `agent-browser.debug_chrome_cdp` | debug Chrome CDP responsive on port 9224 | Load LaunchAgent |
| `agent-browser.tooling_cdp` | tooling Chrome CDP responsive on port 9225 | Load LaunchAgent |
| `agent-browser.singleton_preflight` | singleton preflight helper installed | None |
| `agent-browser.reap_strays_helper` | stray target reap helper installed | None |
| `agent-browser.no_forwarded_launches` | launchd Chrome logs have no forwarded singleton launches | None |
| `agent-browser.no_stray_newtab_targets` | managed Chromes expose no stray blank/newtab targets | None |
| `agent-browser.remote_debugging_process_count` | Chrome remote-debugging process count stays at the managed threshold | None |
| `agent-browser.profile_preflight_guard` | zshrc.ai-tools guards launchd-owned AGENT_BROWSER_PROFILE | None |
| `agent-browser.legacy_launchers_safe` | legacy agent-browser launch scripts do not launch managed profiles | None |
| `agent-browser.profile_dir` | Chrome profile directory exists | `mkdir -p` |
| `agent-browser.dashboard_theme` | dashboard Chrome themed BLUE (port 9223) | `dotfiles-set-persistent-chrome-themes 9223` |
| `agent-browser.debug_chrome_theme` | debug Chrome themed ORANGE (port 9224) | `dotfiles-set-persistent-chrome-themes 9224` |
| `agent-browser.tooling_theme` | tooling Chrome themed PURPLE (port 9225) | `dotfiles-set-persistent-chrome-themes 9225` |
| `agent-browser.spotlight_excluded` | agent-browser dir excluded from Spotlight | `touch .metadata_never_index` |
| `agent-browser.idle_timeout` | Idle timeout env var configured | None |
| `agent-browser.env_timeout` | Default timeout env var configured | None |
| `agent-browser.cdp_wrapper` | shell wrapper auto-uses `--cdp 9223` for default and dotfiles-assigned agent sessions | None |
| `agent-browser.focus_restore_helper` | `dotfiles-restore-focus-after-chrome` helper installed | None |
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
| Dock folders | `dock_applications`, `dock_downloads` | 2 | Applications grid + Downloads stack (requires dockutil) |
| Dock reset | `dock_no_static_only` | 1 | Dock not in static-only mode |

---

## Cosmetic

### jetbrains (conditional)

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `symlink.ideavimrc` | `~/.ideavimrc` symlinked to dotfiles | Create symlink |
| `symlink.ws_vmoptions` | WebStorm vmoptions symlinked (if WebStorm installed) | Create symlink |
| `symlink.ws_properties` | WebStorm idea.properties symlinked | Create symlink |
| `jetbrains.keymap` | WebStorm keymap installed | None |

### terminal

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
Enterprise-only for the Work-profile checks — they need the configured
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

Organization-specific Claude checks (e.g. cloned-MCP-repo verifications) live in the overlay repo's `modules/claude-<org>/doctor.sh` and are auto-discovered via the `EXTRA_DOCTOR_DIR` hook.

### cursor (selected checks)

Gate: skipped entirely when `use_cursor: false` in chezmoi config (default `true`).

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `cursor.installed` | Cursor app installed | None |
| `cursor.native_arch` | Cursor.app binary includes arm64 on Apple Silicon | `brew reinstall --cask cursor` |
| `cursor.symlink.settings` | Generated settings.json symlinked into User/ | Symlink from dotfiles source |
| `cursor.symlink.keybindings` | Keybindings symlinked into User/ | Symlink from dotfiles source |
| `cursor.model_parity` | Agent/CLI model matches Claude Code | `run_after_cursor-agent-parity.sh --check-model` fix path |
| `cursor.agent_settings_parity` | CLI vimMode + Glass editor prefs match editor settings.json | `run_after_cursor-agent-parity.sh` |
| `cursor.vitest_discovery_guard` | Vitest extension excludes mirror/worktree/doc paths from config scan | Regenerate settings via doctor `--fix` |
| `cursor.at_login_launchagent` | `cursor-at-login` LaunchAgent uses `open -g -a Cursor` | `chezmoi apply` |
| `cursor.at_login_loaded` | `com.dotfiles.cursor-at-login` registered (when Cursor installed) | `launchctl bootstrap` / `chezmoi apply` |
| `cursor.no_webstorm_login_item` | WebStorm removed from Login Items | `chezmoi apply` (macos-apps.sh) or osascript delete |

### enterprise

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `enterprise.aws` | AWS CLI installed | `brew install awscli` |
| `enterprise.kubectl` | kubectl installed | `brew install kubernetes-cli` |
| `enterprise.gradle` | Gradle installed | `brew install gradle` |
| `enterprise.java` | Java installed | `brew install openjdk@21` |
| `enterprise.node` | Node.js installed | `brew install fnm` |
| `enterprise.docker` | Docker installed | `brew install docker` |
| `enterprise.gh` | GitHub CLI installed | `brew install gh` |
| `enterprise.jq` | jq installed | `brew install jq` |

### workspace

Host-level visibility across every declared workspace folder (parents of
multiple repo checkouts). Discovery: `~/.config/tasks-md/workspaces.json`
→ `workspaces.yaml` → sentinel/structure scan of `$WORKSPACE_SCAN_ROOTS`
(default `~/apps`). See [docs/workspace.md](workspace.md).

| ID | What it checks | Auto-fix |
|----|---------------|----------|
| `workspace.discovery_lib` | `lib/workspace-discovery.sh` sources and defines `workspace_discover` | — |
| `workspace.declared_roots_exist` | every config-declared workspace path exists (vacuous pass without a config) | edit `~/.config/tasks-md/workspaces.{json,yaml}` |
| `workspace.status_runs` | `dotfiles-workspace status` exits 0 | — |
| `workspace.any_discovered` | advisory — at least one workspace discovered | `touch <root>/.tasks-md-workspace` or set `WORKSPACE_SCAN_ROOTS` |
