# What Gets Changed

## TL;DR

Running `chezmoi apply` (or `dotfiles apply`) will:

- Symlink shell config files (`~/.zshrc`, `~/.zshenv`, `~/.gitconfig`, etc.) to the repo's `home/` directory
- Deploy config files to `~/.config/` (ghostty, starship, lazygit, atuin, fastfetch)
- Deploy `~/.gitconfig` via chezmoi template (with machine-specific hooksPath)
- Deploy `~/.ssh/config` with restricted permissions (0600)
- Apply macOS `defaults write` settings (keyboard, Finder, Dock, animations, etc.)
- Install 34-54 Homebrew packages (depending on profile)
- Load LaunchAgents into `~/Library/LaunchAgents/com.dotfiles.*`
- Cache shell tool init scripts to `~/.cache/zsh/`
- Create directories: `~/.cache/zsh`, `~/.cache/node-compile`, `~/.notes`

> **Preview before applying:** Run `dotfiles diff` to see exactly what chezmoi will write, modify, or create -- without making any changes.
>
> **Remove everything:** Run `dotfiles uninstall` to unload LaunchAgents and remove symlinks. Personal files (`~/.zshrc.local`, `~/.gitconfig.local`, `~/.zshenv.secrets`) are never touched.

---

## 1. Shell Config (Symlinked Files)

These files in the repo's `home/` directory are symlinked into `~/`:

| Source (in repo) | Target | Purpose |
|---|---|---|
| `home/zshrc` | `~/.zshrc` | Shell config: aliases, PATH, completions, fzf, plugins |
| `home/zshenv` | `~/.zshenv` | Pre-shell env: fnm (Node), dotfiles env, secrets loading |
| `home/gitconfig` | `~/.gitconfig` | Git config: delta pager, aliases, performance, LFS, credential helpers |
| `home/gitignore_global` | `~/.gitignore_global` | Global gitignore: macOS, Node, Python, IDE artifacts |
| `home/git-editor` | `~/.git-editor` | Smart git editor: detects Cursor/VS Code/nano, skips in non-interactive |
| `home/gitcommit_template` | `~/.gitcommit_template` | Conventional commit template |
| `home/tmux.conf` | `~/.tmux.conf` | tmux config: Ctrl-A prefix, vim keys, Dracula theme (full only) |
| `home/ideavimrc` | `~/.ideavimrc` | IdeaVim config: 275 keybindings for JetBrains IDEs (full only) |
| `home/sleep` | `~/.sleep` | Sleepwatcher hook: logs sleep events (full only) |
| `home/wakeup` | `~/.wakeup` | Sleepwatcher hook: runs network watchdog on wake (full only) |
| `home/zshrc.ai-tools` | `~/.zshrc.ai-tools` | AI agent tooling: Devin CLI, model defaults (opt-in) |

**Note:** `~/.gitconfig` is also deployed via chezmoi template (`dot_gitconfig.tmpl`) which adds a machine-specific `core.hooksPath` pointing to the repo's `git-hooks/` directory. The symlinked version in `home/gitconfig` does not include this path.

---

## 2. macOS Defaults

Applied via `defaults write` in chezmoi lifecycle scripts. All settings are defined in `data/macos-defaults.json` and split into three tiers:

### Core defaults (all profiles)

| Category | Count | Key changes |
|---|---|---|
| Keyboard | 8 | Fast key repeat (1/15), disable autocorrect, auto-capitalization, smart quotes |
| Finder | 12 | Show hidden files, path bar, status bar, all extensions; column view; folders first |
| Dock performance | 9 | Zero autohide delay, fast animations, scale minimize, disable launch bounce |
| Dialogs & app behavior | 7 | Save to disk (not iCloud), expanded Save/Print dialogs, quit closes windows |
| Activity Monitor | 6 | Show all processes, sort by CPU, 1s refresh, CPU history icon |
| Screenshots | 4 | Save to Desktop as PNG, no shadow, no thumbnail |
| Window management | 4 | Sequoia native tiling (edge drag, top drag, Option accelerator) |
| Safari dev tools | 4 | Enable Develop menu, WebKit developer extras |
| Siri | 3 | Hide from menu bar, decline enable, disable assistant |
| Analytics & diagnostics | 3 | Disable auto-submit, crash reports, Siri data sharing |
| Menu bar | 3 | Show seconds on clock, date format, battery percentage |
| TextEdit | 3 | Plain text by default, UTF-8 encoding |
| Prevent .DS_Store | 2 | Disable on network and USB volumes |
| Terminal.app | 2 | Hide line marks, focus follows mouse |
| App Store | 2 | Show debug menu, developer extras |
| Disk Utility | 2 | Show all devices, debug menu |
| Mission Control | 2 | Group apps in Expose, independent spaces per display |
| Security | 3 | Require password immediately after screensaver/display sleep; start screen saver at 15 min |
| Crash reporter | 1 | Suppress dialog |
| App Nap | 1 | Globally disabled |
| Time Machine | 1 | Don't prompt for new backup disks |
| AirPlay Receiver | 1 | Disabled |
| Transparency | 1 | Reduce transparency |
| Notifications | 1 | Content visibility set to minimal |

### Visual defaults (full profile only)

| Category | Count | Key changes |
|---|---|---|
| Hot corners | 8 | Top-right: Mission Control, bottom-left: Start Screen Saver, bottom-right: Desktop |
| Dock appearance | 6 | Auto-hide, 44px tiles, magnification to 56px, hide recents, hide indicators |
| Trackpad | 5 | Speed 3.0, tap to click, three-finger drag |
| Finder sidebar | 3 | 180px sidebar, show desktop icons |
| Font rendering | 3 | No subpixel AA (Retina), reduce desktop tinting, scrollbars when scrolling |
| Accessibility | 2 | Reduce transparency, reduce motion |
| Accent & highlight | 2 | Orange accent and highlight color |
| Sidebar icon size | 1 | Medium |
| Mouse | 1 | Speed 3.0 |

### App-specific defaults (full profile only)

| Category | Count | Key changes |
|---|---|---|
| Zoom | 16 | Disable auto-update, start muted + no video, show elapsed time, hide non-video participants, disable spell check |
| Chrome | 10 | Disable background mode, freeze tabs, no swipe navigation, show full URLs, always-open checkbox for protocols |
| Maccy | 2 | 200-item history, paste by default |
| Gatekeeper | 1 | Disable download quarantine (`LSQuarantine = false`) |

---

## 3. Homebrew Packages

Installed via `run_onchange_brew.sh.tmpl`. Re-runs automatically when the Brewfile content changes.

### Core packages (all profiles)

| Category | Packages |
|---|---|
| Git | `git-delta`, `gh` |
| Shell | `atuin`, `direnv`, `fnm`, `fzf`, `poetry`, `pyenv`, `uv`, `yarn`, `zoxide`, `zsh-autosuggestions`, `zsh-fast-syntax-highlighting`, `zsh-history-substring-search`, `zsh-syntax-highlighting` |
| Tools | `bat`, `bats-core`, `btop`, `eza`, `fastfetch`, `fd`, `fswatch`, `gum`, `htop`, `httpie`, `jq`, `ripgrep`, `shellcheck`, `sleepwatcher`, `terminal-notifier`, `tealdeer`, `tree`, `yq` |
| Prompt | `starship` |

### Full profile additions

| Category | Packages |
|---|---|
| Terminal | `tmux`, `ghostty` (cask), `font-jetbrains-mono-nerd-font` (cask) |
| Extras | `difftastic`, `dockutil`, `duf`, `dust`, `duti`, `git-trim`, `hyperfine`, `jrnl`, `lazygit`, `poppler`, `procs`, `tig`, `watchexec`, `yazi`, `hiddenbar` (cask), `maccy` (cask) |

### Enterprise additions (when `is_enterprise: true`)

| Category | Packages |
|---|---|
| Cloud & infra | `awscli`, `cloudflared`, `kubernetes-cli`, `tailscale` |
| JVM | `gradle`, `openjdk@21`, `temurin@21` (cask) |
| Tap | `cloudflare/cloudflare` |

Packages can be excluded via the `brew_skip` config in `~/.config/chezmoi/chezmoi.yaml`.

---

## 4. LaunchAgents

Deployed to `~/Library/LaunchAgents/com.dotfiles.*` via `run_onchange_launchagents.sh.tmpl`. Each agent is conditionally loaded based on profile and tool availability.

| Agent | Schedule | Profile | Purpose |
|---|---|---|---|
| `dotfiles-sync` | Every 30 min + at load | all | Auto-commit local changes and pull remote (skipped when `auto_sync: false`) |
| `tooling-sync` | Every 60 min + at load | all | Fast-forward the tooling repos (skipped when `auto_sync: false`) |
| `dotfiles-doctor` | Monday 9:00 AM | all | Weekly health check with `--fix` |
| `cleanup` | Periodic | all | Clean caches, logs, and temp files |
| `git-maintain` | Periodic | all | Git gc, prune, and maintenance across repos |
| `capslock-control` | At load | all | Remap Caps Lock to Control |
| `gui-path` | At load | all | Ensure GUI apps inherit shell PATH |
| `network-resilience` | Periodic | all | Monitor and recover network connectivity |
| `atuin-daemon` | At load | all | Background shell history daemon (if atuin installed) |
| `rancher-desktop` | At load | all | Rancher Desktop integration (if app installed) |
| `morning` | Configurable (default 8:30 AM) | full | Morning briefing |
| `sleepwatcher` | At load | full | Run scripts on sleep/wake events |
| `cursor-priority` | At load | full | Set process priority for Cursor/Windsurf IDE |
| `agent-browser-chrome` | At load, not kept alive | full | Dashboard / SSO Chrome with remote debugging on port 9223; manual close for logout/shutdown is respected |
| `debug-chrome` | At load, not kept alive | full | Debug-work Chrome with remote debugging on port 9224; manual close for logout/shutdown is respected |
| `tooling-chrome` | At load, not kept alive | full | Tooling-repo Chrome with remote debugging on port 9225; manual close for logout/shutdown is respected |
| `chrome-debug` | On-demand | full | Chrome debugging port 9222 (CDP) (`launchctl start com.dotfiles.chrome-debug`) |
| `dotfiles-upgrade` | Sunday 9:00 AM | opt-in | Topgrade upgrade of Homebrew, casks and tools (requires `auto_upgrade: true`) |

Logs are written to `~/.local/share/dotfiles/logs/<agent-name>.log`.

---

## 5. XDG Config Files

Deployed to `~/.config/` via chezmoi's `dot_config/` source directory:

| Source | Target | Purpose |
|---|---|---|
| `dot_config/ghostty/config` | `~/.config/ghostty/config` | Ghostty terminal: Dracula theme, JetBrains Mono, splits, keybindings (full only) |
| `dot_config/starship.toml` | `~/.config/starship.toml` | Starship prompt: git, node, python, java, docker, k8s modules |
| `dot_config/lazygit/config.yml` | `~/.config/lazygit/config.yml` | Lazygit: Dracula theme, delta pager, custom commands (full only) |
| `dot_config/atuin/config.toml` | `~/.config/atuin/config.toml` | Atuin shell history: fuzzy search, secrets filter, daemon mode |
| `dot_config/fastfetch/config.jsonc` | `~/.config/fastfetch/config.jsonc` | Fastfetch system info display (full only) |
| `dot_config/dotfiles/env.sh.tmpl` | `~/.config/dotfiles/env.sh` | Chezmoi-generated env vars (DOTFILES_REPOS_DIR) |

---

## 6. Other Home Directory Files

Deployed directly to `~/` via chezmoi:

| Source | Target | Purpose |
|---|---|---|
| `dot_editorconfig` | `~/.editorconfig` | EditorConfig: indent style, trailing whitespace, final newline |
| `modify_private_dot_npmrc` | `~/.npmrc` | npm config: exact versions, prefer offline, no fund/audit. Rendered at 0600; registry credentials npm wrote locally are preserved on every apply. |
| `dot_biome.json` | `~/.biome.json` | Biome linter/formatter config |
| `dot_hushlogin` | `~/.hushlogin` | Suppress "Last login" message in terminal |
| `dot_gradle/gradle.properties` | `~/.gradle/gradle.properties` | Gradle build config |

---

## 7. SSH Config

Deployed from `private_dot_ssh/` with restricted permissions (chezmoi's `private_` prefix ensures 0700 on the directory, 0600 on files):

| Source | Target | Purpose |
|---|---|---|
| `private_dot_ssh/private_config.tmpl` | `~/.ssh/config` | SSH config: GitHub, keychain agent, connection multiplexing, keepalive |

The SSH config includes:
- `AddKeysToAgent yes` and `UseKeychain yes` for macOS keychain integration
- `ControlMaster auto` with `ControlPath ~/.ssh/sockets/` for connection multiplexing
- `ServerAliveInterval 60` to prevent dropped connections
- GitHub-specific host entry with ed25519/RSA identity files
- `Include ~/.ssh/config.local` for user overrides

---

## 8. Lifecycle Scripts

These chezmoi scripts run automatically during `chezmoi apply`:

| Script | Trigger | Purpose |
|---|---|---|
| `run_once_bootstrap.sh` | First run only | Install Xcode CLT, Homebrew, chezmoi; prompt for git identity |
| `run_onchange_brew.sh.tmpl` | When Brewfile changes | Install/update Homebrew packages |
| `run_onchange_macos.sh.tmpl` | When defaults change | Apply macOS `defaults write` settings |
| `run_onchange_launchagents.sh.tmpl` | When plist files change | Deploy and load LaunchAgents |
| `run_after_cache-inits.sh` | Every apply | Cache fzf, zoxide, starship, fnm init scripts to `~/.cache/zsh/` |
| `run_after_endpoint-security.sh` | Every apply | Re-sign Homebrew bottles, uv pythons, and dotfiles endpoint shims (managed-endpoint drift) |
| `run_after_agentbrew-sync.sh` | Every apply | Sync agent config from `Agentfile.yaml` (non-fatal) |
| `run_after_devin-caffeinate.sh` | Every apply | Install Devin title wrapper at `~/.local/bin/devin` (if Devin installed) |

---

## 9. What is NEVER Touched

The following files and data are explicitly preserved and never created, modified, or deleted by dotfiles:

| Path | Purpose |
|---|---|
| `~/.zshrc.local` | Personal shell overrides (sourced at end of `.zshrc`) |
| `~/.gitconfig.local` | Personal git identity: name, email, signing key (included by `.gitconfig`) |
| `~/.zshenv.secrets` | API keys, tokens, enterprise credentials |
| `~/.ssh/id_ed25519`, `~/.ssh/id_rsa` | SSH private/public keys |
| `~/.ssh/config.local` | Personal SSH host overrides (included by managed SSH config) |
| `~/.config/chezmoi/key.txt` | age encryption key |
| Existing browser profiles | Chrome/Safari profiles, bookmarks, extensions |
| macOS iCloud settings | iCloud Drive, Photos, Keychain sync |
| macOS user account settings | Login items (Ghostty via macos-apps.sh; Cursor via `com.dotfiles.cursor-at-login`; other non-dotfiles items untouched), wallpaper, screen resolution |
| `~/Library/` (except LaunchAgents) | Application data, preferences not in `defaults write` scope |

`dotfiles uninstall` only removes symlinks pointing into the dotfiles repo and unloads `com.dotfiles.*` LaunchAgents. It does not revert macOS defaults -- those persist until manually changed in System Settings.
