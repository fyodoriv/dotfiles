# Verify Your Setup

Post-install checklist. Run through these steps after completing the [onboarding guide](onboarding.md) to confirm everything is working. Enterprise users should also follow their organization's overlay verification steps.

## Quick Check

One command to verify everything:

```bash
dotfiles doctor --quiet
```

Expected output: `✓ N passed  ⊘ M skipped` with exit code 0. If it shows failures, run `dotfiles doctor --fix` first, then re-check.

## Step-by-Step Verification

### 1. Shell Configuration

```bash
# Verify symlinks
ls -la ~/.zshrc    # → ~/apps/dotfiles/home/zshrc
ls -la ~/.zshenv   # → ~/apps/dotfiles/home/zshenv

# Verify shell startup is fast
time zsh -i -c exit   # should be <200ms

# Verify PATH includes Homebrew
which brew   # /opt/homebrew/bin/brew (Apple Silicon) or /usr/local/bin/brew (Intel)
```

### 2. Git Configuration

```bash
# Verify gitconfig is managed by chezmoi (copy-mode, not a symlink)
chezmoi verify   # exit 0 means all managed files are up to date

# Verify personal config exists
cat ~/.gitconfig.local   # should show [user] name and email

# Verify hooks are active
git config --global core.hooksPath   # ~/apps/dotfiles/git-hooks

# Verify recommended settings
git config --global pull.rebase          # true
git config --global push.autoSetupRemote # true
```

### 3. SSH Access

```bash
# Verify SSH key loaded
ssh-add -l

# Test GitHub access
ssh -T git@github.com

# Test GitHub Enterprise (requires VPN)
ssh -T git@<your-ghe-host>
```

### 4. Homebrew Packages

```bash
# Verify Homebrew is functional
brew doctor

# Check installed packages match profile
brew list --formula | wc -l   # ~34 (core) or ~54 (full)
```

### 5. LaunchAgents

```bash
# Verify core agents are loaded
launchctl list | grep com.dotfiles

# Expected (core profile):
# com.dotfiles.capslock-control
# com.dotfiles.cleanup
# com.dotfiles.dotfiles-doctor
# com.dotfiles.dotfiles-sync
# com.dotfiles.git-maintain
# com.dotfiles.gui-path
# com.dotfiles.network-resilience
```

### 6. macOS Defaults

```bash
# Verify key repeat speed (should be 2 or lower)
defaults read NSGlobalDomain KeyRepeat

# Verify Finder shows hidden files
defaults read com.apple.finder AppleShowAllFiles

# Run the full macOS module check
dotfiles doctor --module macos
```

### 7. Security

```bash
# Verify SSH permissions
dotfiles doctor --module security

# Verify no secrets in tracked files
dotfiles audit
```

## Enterprise-Only Checks

Skip this section if `is_enterprise: false` in your chezmoi config.

### 8. Enterprise Tools

```bash
dotfiles doctor --module enterprise

# Expected: all checks pass for aws, kubectl, gradle, java
```

### 9. Age Encryption (if enabled)

```bash
# Verify key exists
ls -la ~/.config/chezmoi/key.txt

# Verify encrypted files decrypt correctly
chezmoi cat <path/to/encrypted_file>.age   # any encrypted_*.age from your overlay
```

## Understanding Doctor Output

`dotfiles doctor` uses these status indicators:

| Symbol | Meaning | Action |
|--------|---------|--------|
| ✓ | Check passed | None needed |
| ✗ | Check failed | Run with `--fix` or investigate |
| ⊘ | Check skipped | Module not enabled or check overridden |
| ↻ | Auto-fixed | Was broken, now repaired |

### Severity Levels

| Level | Meaning | Example Modules |
|-------|---------|-----------------|
| critical | Must fix — security or data risk | security |
| important | Should fix — affects daily workflow | git, shell, ssh |
| performance | Nice to fix — affects speed | macos, terminal |
| cosmetic | Optional — appearance or polish | prompt, editor |

Run only critical/important checks: `dotfiles doctor --severity important`

## Module Reference

All 21 doctor modules and what they check:

| Module | What It Checks |
|--------|---------------|
| agent-browser | Chrome DevTools Protocol setup |
| agentbrew | Agent config sync status |
| chrome | Chrome profile and extensions |
| claude | Claude CLI configuration |
| cursor | Cursor editor settings |
| devin | Devin CLI configuration |
| editor | Default editor setup |
| enterprise | AWS, kubectl, gradle, java |
| extras | Additional CLI tools |
| git | Gitconfig, hooks, delta, performance settings |
| jetbrains | JetBrains IDE settings |
| macos | macOS defaults (key repeat, Finder, Spotlight, etc.) |
| prompt | Starship prompt configuration |
| security | SSH permissions, secrets scanning, audit |
| shell | Zsh config, PATH, caches, startup time |
| ssh | SSH config management and permissions |
| sync | Auto-sync LaunchAgent and git status |
| terminal | Terminal emulator settings |
| tools | Core CLI tools (fd, ripgrep, jq, etc.) |
| upgrade | Auto-upgrade agent configuration |
| workflow | LaunchAgents, Spotlight tuning |

Check a specific module: `dotfiles doctor --module <name>`
List all check IDs: `dotfiles doctor --list`

## Common First-Run Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Missing symlinks | First apply didn't run | `dotfiles apply` |
| Git hooks not active | `core.hooksPath` not set | `dotfiles doctor --fix --module git` |
| LaunchAgents not loaded | Plists not registered | `dotfiles doctor --fix --module workflow` |
| Shell startup slow (>200ms) | Caches not generated | `dotfiles doctor --fix --module shell` |
| Brew packages missing | Brew lifecycle script didn't run | `dotfiles apply` (triggers brew install) |

## Full Diagnostic Report

Generate a shareable markdown report of all checks:

```bash
dotfiles doctor --report > ~/Desktop/dotfiles-report.md
```

Or output as JSON for scripting:

```bash
dotfiles doctor --json
```

## Further Reading

- [Troubleshooting](troubleshooting.md) — symptom-first guide for specific issues
- [Onboarding](onboarding.md) — full setup walkthrough
- [Security model](security-model.md) — trust boundaries and audit capabilities
- [Module reference](module-reference.md) — detailed module documentation
