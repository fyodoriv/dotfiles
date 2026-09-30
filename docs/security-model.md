# Security Model

This document describes the trust boundaries, privilege escalation, secrets handling, and audit capabilities of this dotfiles repo. It is intended for teams evaluating adoption in an enterprise environment.

## Overview

All configuration runs as the current user. The repo makes no system-level changes outside the user's home directory, with two exceptions: power management (`sudo pmset`) and DNS cache flush (`sudo dscacheutil`). Both are opt-in via profile selection and fail silently if sudo is unavailable.

## Privilege Escalation

### Commands that use `sudo`

| Command | Script | When | Purpose |
|---------|--------|------|---------|
| `sudo pmset -c powermode 2` | `macos.sh` | `chezmoi apply` (onchange) | High-performance mode on AC power |
| `sudo pmset -c sleep 1` | `macos.sh` | `chezmoi apply` (onchange) | Normal AC idle sleep timer outside tracked agent work |
| `sudo pmset -c disksleep 10` | `macos.sh` | `chezmoi apply` (onchange) | Normal AC disk-sleep timer outside tracked agent work |
| `sudo pmset -c womp 0` | `macos.sh` | `chezmoi apply` (onchange) | Disable Wake-on-LAN |
| `sudo pmset -a tcpkeepalive 1` | `macos.sh` | `chezmoi apply` (onchange) | Keep network alive during sleep |
| `sudo pmset -a displaysleep 15` | `macos.sh` | `chezmoi apply` (onchange) | Display sleep after 15 min on AC and battery |
| `sudo pmset -b sleep 15` | `macos.sh` | `chezmoi apply` (onchange) | Battery system sleep after 15 min |
| `sudo pmset -b disksleep 15` | `macos.sh` | `chezmoi apply` (onchange) | Battery disk sleep after 15 min |
| `sudo dscacheutil -flushcache` | `bin/network-watchdog` | After 15s of DNS failure | Flush DNS resolver cache |
| `sudo killall -HUP mDNSResponder` | `bin/network-watchdog` | After 15s of DNS failure | Restart mDNS daemon |

All `sudo` calls are wrapped in `2>/dev/null || true` and fail silently. No `sudo` calls exist in `.chezmoiscripts/` lifecycle scripts.

### Homebrew bootstrap

`run_once_bootstrap.sh` fetches the official Homebrew installer via `curl | bash`. The Homebrew installer itself uses `sudo` internally (standard macOS behavior). This runs exactly once on first setup.

## Secrets Handling

### Two-layer strategy

| Layer | File | Tracked? | Encryption | Purpose |
|-------|------|----------|------------|---------|
| Runtime env | `~/.zshenv.secrets` | Never (gitignored) | None (plaintext) | API tokens, passwords, enterprise URLs |
| File encryption | `encrypted_*.age` | Yes (encrypted) | age (asymmetric) | Org-overlay secrets (for example enterprise SSH host config) |

### Runtime secrets (`~/.zshenv.secrets`)

- Sourced by `~/.zshenv` on every shell startup
- Template provided: `home/zshenv.secrets.example`
- Expected variables: `GITHUB_TOKEN`, `JENKINS_TOKEN`, `SPLUNK_*` credentials
- Preserved through uninstall (never deleted by `dotfiles uninstall`)
- **Trust boundary**: any process running as the current user can read this file

### Age encryption

- **Opt-in**: requires `use_encryption: true` in chezmoi config
- **Identity key**: `~/.config/chezmoi/key.txt` (never tracked in git)
- **Recipient**: public key stored in chezmoi config data
- **Currently encrypts**: nothing in the base repo. The org overlay carries the encrypted enterprise SSH config.
- **Gating**: requires `use_encryption: true`

> **Enterprise users**: enterprise SSH config may contain sensitive host information (internal hostnames, jump hosts, bastion IPs). We recommend enabling age encryption if you use enterprise mode. Without it, this config is stored as plaintext in git. Your organization's overlay should document the recommended encryption setup.

### Age key rotation

Rotate your age key periodically or when you suspect compromise.

**When to rotate:**
- Key file (`~/.config/chezmoi/key.txt`) was exposed or copied to an insecure location
- Team member with access to the key leaves the organization
- Annual rotation as a security hygiene practice

**How to rotate:**

```bash
# 1. Generate a new key
age-keygen -o ~/.config/chezmoi/key-new.txt
# Note the public key from the output (starts with age1...)

# 2. Decrypt all encrypted files with the OLD key
chezmoi decrypt <path/to/encrypted_file>.age > /tmp/plain-file

# 3. Update chezmoi config with the new recipient (public key)
# Edit ~/.config/chezmoi/chezmoi.yaml: replace age_recipient with the new public key

# 4. Replace the old key with the new one
mv ~/.config/chezmoi/key-new.txt ~/.config/chezmoi/key.txt
chmod 600 ~/.config/chezmoi/key.txt

# 5. Re-encrypt with the new key
chezmoi encrypt /tmp/plain-file > <path/to/encrypted_file>.age
rm /tmp/plain-file

# 6. Verify decryption works
chezmoi cat <path/to/encrypted_file>.age

# 7. Commit the re-encrypted file
git add <path/to/encrypted_file>.age
git commit -m "chore: rotate age encryption key"
```

**Verify:** after rotation, run `chezmoi apply` and confirm `~/.ssh/config.enterprise` is correctly deployed.

## macOS Defaults

`chezmoi apply` runs `macos.sh` on all profiles, plus `macos-visual.sh` and `macos-apps.sh` on `full` profile only. All `defaults write` calls are user-scoped (no `sudo`).

### Security-relevant defaults

| Setting | Domain | Effect | Risk |
|---------|--------|--------|------|
| `LSQuarantine = false` | `com.apple.LaunchServices` | Disables Gatekeeper download quarantine | Downloaded apps skip "from the internet" warning |
| `DialogType = none` | `com.apple.CrashReporter` | Silent crash reports | No crash dialogs shown |
| `AutoSubmit = false` | `com.apple.DiagnosticReporting` | Opt out of analytics | Reduces telemetry |
| `AirplayRecieverEnabled = false` | `com.apple.controlcenter` | Disables AirPlay Receiver | Removes mDNS broadcast |
| `askForPasswordDelay = 0` | `com.apple.screensaver` | Immediate password on screensaver | Improves physical security |
| `idleTime = 900` | `com.apple.screensaver` | Start screen saver after 15 minutes idle | Improves physical security |

**LSQuarantine note**: disabling Gatekeeper quarantine is a deliberate developer convenience trade-off. Downloaded `.app`, `.pkg`, and `.dmg` files will not show the "downloaded from the internet" confirmation. This setting is full-profile only (tagged `"script": "apps"` in `data/macos-defaults.json`). If your team requires Gatekeeper quarantine, remove the `LSQuarantine` entry from `data/macos-defaults.json`.

### TCC-protected defaults (macOS 16+)

Starting with macOS 16 (Tahoe), some `defaults write` domains are protected by Transparency, Consent, and Control (TCC). The system will silently ignore these writes unless the calling process has explicit approval in **System Settings > Privacy & Security**.

| Setting | Domain | Key | TCC Permission Required |
|---------|--------|-----|------------------------|
| Reduce transparency | `com.apple.universalaccess` | `reduceTransparency` | Accessibility |

**What this means for users**: after running `chezmoi apply`, these settings may not take effect until you grant Terminal (or your shell app) the required TCC permission. Go to **System Settings > Privacy & Security > Accessibility** and add your terminal application.

**What this means for CI**: CI runners on macOS 16+ may not be able to apply these defaults. The doctor check will report a warning but will not fail.

### Enterprise network considerations

Enterprise environments with VPN or web proxy may affect:

- **Homebrew**: `brew install` may fail behind proxies that intercept TLS. Set `HOMEBREW_NO_AUTO_UPDATE=1` and configure proxy env vars (`http_proxy`, `https_proxy`) in `~/.zshenv.secrets`.
- **Git over SSH**: corporate firewalls may block port 22. Use `~/.ssh/config.local` to configure `ProxyCommand` for `github.com` access through the proxy.
- **age encryption**: requires internet access to fetch public keys from key servers (only if using `age-plugin-yubikey` or similar). Standard age with local keys works offline.
- **LaunchAgents**: the `dotfiles-sync` agent pushes to git remotes every 30 minutes. Ensure your VPN allows outbound SSH/HTTPS to your git host.

### Categories of changes

- **Performance**: animations disabled, Dock autohide instant, App Nap off
- **Keyboard**: fastest key repeat, no auto-correct/smart-quotes/dashes
- **Finder**: show hidden files, path bar, status bar, all extensions, column view
- **Spotlight**: result categories limited to files/contacts/calendar, plus `.metadata_never_index` in dev directories (`~/apps`, `~/.cache`, `node_modules`, etc.)
- **Power**: AC high-performance mode, 15-minute display sleep/lock on AC and battery (via `sudo pmset`)
- **Screenshots**: Desktop location, PNG format, no shadow
- **Privacy**: Siri disabled, analytics opt-out, AirPlay off

## LaunchAgents

All agents install to `~/Library/LaunchAgents/com.dotfiles.*`. All run as the current user (no root). Logs go to `~/.local/share/dotfiles/logs/`.

### Core profile agents (always loaded)

| Agent | Schedule | What it does |
|-------|----------|--------------|
| `capslock-control` | At login | Maps CapsLock to Control via `hidutil` |
| `cleanup` | Sunday 03:00 | Cleans npm/yarn/brew/Gradle caches from safelisted dirs |
| `dotfiles-doctor` | Monday 09:00 | Runs `dotfiles doctor --fix` (auto-repairs symlinks) |
| `dotfiles-sync` | Every 30 min | Auto git commit+push of dotfiles changes |
| `git-maintain` | Daily 04:00 | Git maintenance on repos in `~/apps` |
| `gui-path` | At login | Sets PATH for GUI apps via `launchctl setenv` |
| `network-resilience` | Every 5 min | Network watchdog (may `sudo` for DNS flush) |

### Full profile agents (additional)

| Agent | Schedule | What it does | Notable |
|-------|----------|--------------|---------|
| `agent-browser-chrome` | At login, not kept alive | Dashboard / SSO Chrome with CDP on port 9223 | Localhost CDP is an attack surface; agents attach instead of launching its profile; manual close for logout/shutdown is respected |
| `debug-chrome` | At login, not kept alive | Debug-work Chrome with CDP on port 9224 | Localhost CDP is an attack surface; agents attach instead of launching its profile; manual close for logout/shutdown is respected |
| `tooling-chrome` | At login, not kept alive | Tooling-repo Chrome with CDP on port 9225 | Localhost CDP is an attack surface; agents attach instead of launching its profile; manual close for logout/shutdown is respected |
| `chrome-debug` | On-demand | Chrome with CDP on port 9222 | Localhost CDP is an attack surface; started manually to minimize exposure window |
| `cursor-priority` | Every 60s | Boosts IDE process scheduling via `taskpolicy` | |
| `cursor-at-login` | At login | Launches Cursor in background via `open -g -a Cursor` | No focus steal at login |
| `morning` | Daily 08:30 | Morning briefing (read-only) | |
| `sleepwatcher` | Persistent | Runs `~/.sleep`/`~/.wakeup` on system events | |

### Opt-in agents

| Agent | Condition | What it does | Notable |
|-------|-----------|--------------|---------|
| `dotfiles-upgrade` | `auto_upgrade: true` | Weekly Topgrade: brew, Node, uv | Installs/upgrades software |
| `atuin-daemon` | `atuin` installed | Shell history sync daemon | |
| `rancher-desktop` | App installed | Starts Rancher Desktop VM | |

### Security considerations

- **CDP ports (9222-9225)**: Chrome DevTools Protocol ports bind to localhost on `full` profile. Port 9222 is the separate on-demand `chrome-debug` profile; 9223/9224/9225 are login-started managed Chromes for agent attach-first workflows. They are deliberately not `KeepAlive`, so quitting Chrome for logout/shutdown stays closed. Any local process can attach and exfiltrate browser state. Disabled on `core` profile.
- **gui-path**: `launchctl setenv PATH` affects all GUI apps. Injects Homebrew and `fnm` Node paths into the system-wide per-user environment.
- **upgrade agent**: silently upgrades Homebrew packages, Node versions, and CLI tools. Requires explicit opt-in (`auto_upgrade: true` in chezmoi config).

## SSH Configuration

- `~/.ssh/` directory: `0700` (enforced by chezmoi `private_dot_ssh`)
- `~/.ssh/config`: rendered from template, includes:
  - `AddKeysToAgent yes` + `UseKeychain yes` (macOS Keychain integration)
  - `ControlMaster auto` with 10-minute socket persistence
  - No global `ForwardAgent yes` (the security module warns if present)
- `~/.ssh/config.local`: user overrides (untracked, always included)
- `~/.ssh/config.enterprise`: supplied by the org overlay (age-encrypted there), not by the base repo

## Git Hooks

Global git hooks are installed to `~/apps/dotfiles/git-hooks/` and activated via `core.hooksPath`. The doctor auto-configures this: `dotfiles doctor --fix` sets `git config --global core.hooksPath ~/apps/dotfiles/git-hooks`.

### What each hook does

#### `commit-msg`

Runs after you write a commit message, before the commit is created.

| Check | Behavior | Enterprise-only? |
|-------|----------|-----------------|
| Conventional commits format | **Blocks** if message doesn't match `type(scope): description` | No |
| 72-character header limit | **Blocks** if header exceeds 72 chars | No |
| JIRA ticket reference | **Warns** if no `PROJ-123` pattern in header | Yes |

Merge commits, fixup commits, and `sync:`/`wip:` messages are always skipped.

#### `pre-commit`

Runs before the commit is created, after staging.

| Check | Behavior | Enterprise-only? |
|-------|----------|-----------------|
| Secret scanning | **Blocks** if known token patterns (GitHub PAT, AWS key, SSH private key, etc.) found in staged diff | No |
| Forbidden file types | **Blocks** if `.pem`, `.key`, `.env.local`, `id_rsa`, etc. are staged | No |
| Shellcheck (dotfiles repo only) | **Blocks** if `make lint` fails | No |
| Excessive deletions (>50 files) | **Blocks** as multi-agent safety guard | No |
| Protected path deletions | **Blocks** if `bin/`, `tests/`, `lib/`, `modules/`, or `skills/` files are deleted, except the verified retirement of `lib/dotfiles-memory.sh` while the AgentBrew shim remains staged | No |
| Branch naming convention | **Warns** if branch doesn't match `type/description` | Yes |

### Advisory vs blocking

- **Blocks** (`exit 1`): commit is rejected. Fix the issue or bypass with `--no-verify`.
- **Warns** (prints warning, exits 0): commit proceeds but the developer sees the warning. Enterprise JIRA ticket and branch naming checks are advisory by default.

To make enterprise checks blocking, edit `git-hooks/commit-msg` and change the ticket check's implicit `exit 0` to `exit 1`.

### Opt-out mechanisms

| Scope | How | Effect |
|-------|-----|--------|
| Once | `git commit --no-verify` | Skips all hooks for this commit |
| Per-repo: ticket check | `git config hooks.skipTicketCheck true` | Skips JIRA ticket enforcement |
| Per-repo: branch naming | `git config hooks.skipBranchCheck true` | Skips branch naming enforcement |
| Global | `git config --global core.hooksPath ""` | Disables all dotfiles hooks |

### Agent publication wrappers

When AI tooling is enabled, dotfiles also puts wrappers for `gh` and `git` on `PATH`:

- `gh pr create` in an agent-shaped session requires a PR body with a clear rationale section and the canonical `_🤖 Written by an agent, not Fyodor..._` footer. A `## Summary` heading counts as the rationale, because `/ship-it` requires the summary to say why the PR is needed.
- Cross-repo `gh pr create` requires `AGENT_PUBLIC_WRITE_APPROVAL` to include the target repo, base branch, title, and SHA-256 of the final body file. A `--repo` in gh's `HOST/OWNER/REPO` form is the same repo when the host and slug match the checkout's `origin`; the same slug on another host is cross-repo. A host-less `owner/repo` entry in `~/.config/agent-gh-allowlist.txt` covers only the checkout's host, never another host such as public `github.com`.
- Body-bearing `gh pr/issue/release` comment and edit commands strip vendor-specific footers and append the canonical footer in agent-shaped sessions.
- `git push --no-verify` in an agent-shaped session is blocked unless `AGENT_PUBLIC_WRITE_APPROVAL` includes `command=git push --no-verify`, the remote, and the ref.
- Human interactive usage and read-only `gh`/`git` commands pass through unchanged.

### How `core.hooksPath` works

Git's `core.hooksPath` config sets a global hooks directory that applies to every repo. When set to `~/apps/dotfiles/git-hooks`, these hooks run on every `git commit` across all repos. Per-repo `.git/hooks/` are ignored when `core.hooksPath` is set.

The doctor check `git.hooks_path` verifies the path is correct. If the path is wrong or unset, `dotfiles doctor --fix` repairs it automatically.

## Audit Capability

Run `dotfiles audit` to check security posture:

```bash
dotfiles audit            # colored terminal output, exit 1 on failures
dotfiles audit --report   # markdown report for sharing
```

### What the audit checks

| Check | Severity |
|-------|----------|
| `~/.ssh/` directory permissions = 700 | Fail |
| Private SSH key permissions = 600 | Fail |
| No `ForwardAgent yes` in global SSH config | Warn |
| No secrets (API keys, tokens) in tracked git files | Fail |
| No `.env` files tracked in git | Fail |
| Sensitive files not world-readable (`.netrc`, `.npmrc`, `.aws/credentials`, etc.) | Warn |
| Git credential helper is not `store` (plaintext) | Warn |
| Git commit GPG signing enabled | Warn |
| No root-level stray agent artifacts (`=5.5.0`, absolute Homebrew symlinks) | Fail |

The security module runs at `critical` severity in `dotfiles doctor` and is checked automatically by the weekly LaunchAgent.

## Uninstall Safety

`dotfiles uninstall` safely removes dotfiles without affecting personal config:

- **Removes**: symlinks pointing to the dotfiles repo, LaunchAgent plists
- **Preserves**: `~/.zshrc.local`, `~/.gitconfig.local`, `~/.zshenv.secrets`
- **Does not delete**: the dotfiles repo itself, any regular (non-symlink) files
- **Dry-run mode**: `dotfiles uninstall --dry-run` shows what would be removed

## What This Repo Does NOT Do

- Does not install kernel extensions or system extensions
- Does not modify `/etc/` or `/Library/` (system-wide) directories
- Does not run any daemons as root
- Does not modify other users' files or configuration
- Does not phone home or send telemetry
- Does not store passwords or tokens in tracked files
