# Onboarding Guide

Get from stock macOS to a fully configured development environment. Estimated time: 10-15 minutes.

> **Enterprise users:** Follow this guide first, then see your organization's overlay docs (e.g. `~/apps/dotfiles-<org>/docs/onboarding.md`) for additional enterprise-specific steps.

## Before You Start

Verify these prerequisites before running any install commands. Missing items will cause silent failures or confusing errors mid-setup.

| Requirement | Verification command | Notes |
|-------------|---------------------|-------|
| macOS 13+ (Ventura, Sonoma, or Sequoia) | `sw_vers --productVersion` | Apple Silicon or Intel |
| 5 GB free disk space | `df -h /` | Homebrew + packages need ~3 GB |
| Admin (sudo) access | `sudo -v` | Needed for macOS defaults and Homebrew |
| Xcode Command Line Tools | `xcode-select -p` | Install: `xcode-select --install` |
| GitHub SSH access | `ssh -T git@github.com` | Must see "successfully authenticated" |

## Step 1: Fork and clone

Fork this repo into your org (or personal account), then clone:

```bash
git clone https://github.com/<your-org>/dotfiles.git ~/apps/dotfiles
```

## Step 2: Initialize chezmoi

```bash
chezmoi init --source ~/apps/dotfiles --apply
```

You'll be prompted for:

| Prompt | Options | Recommendation |
|--------|---------|---------------|
| **Installation profile** | `core` (essentials) or `full` (opinionated) | Start with `core` -- upgrade later with `dotfiles profile full` |
| **Enterprise configs** | `true` / `false` | `false` unless you need AWS, K8s, Gradle |
| **AI agent tooling** | `true` / `false` | `false` -- enables Devin CLI, ANTHROPIC_MODEL, agent-browser config |
| **Auto-upgrade** | `true` / `false` | `false` -- silent `brew upgrade` at 3am Sunday |
| **Age encryption** | `true` / `false` | `false` unless you have an age key for encrypted secrets |
| **Dotfiles directory** | path (relative to `$HOME`) | `apps/dotfiles` -- leave as default unless your dotfiles are at a different path |
| **Repos directory** | path (relative to `$HOME`) | `apps` -- leave as default unless your repos live elsewhere |

This single command:
- Deploys all config files (symlinks + copies)
- Installs Homebrew packages
- Applies macOS defaults (key repeat, Spotlight pruning/exclusions, Finder, etc.)
- Loads LaunchAgents for automation

> **What macOS defaults change?** The `chezmoi apply` lifecycle script runs `macos.sh`, which modifies system preferences. Notable changes include:
>
> | Change | Impact |
> |--------|--------|
> | LSQuarantine disabled | Gatekeeper stops quarantining downloaded files |
> | Power management (via `sudo pmset`) | 15-minute idle lock, sleep, disk sleep, Power Nap settings modified |
> | Spotlight pruning and indexing exclusions | Results limited to files/contacts/calendar; `node_modules`, `vendor`, and similar dirs excluded |
> | Dock/Finder/SystemUIServer restart | UI processes restarted to apply changes |
> | Auto-correct & smart quotes off | System-wide text substitution disabled |
>
> Review `macos.sh` before running if you want to see every setting. The `full` profile also applies visual preferences (`macos-visual.sh`) and app-specific settings (`macos-apps.sh`).

## Step 3: Set up personal git config

Your name and email live in `~/.gitconfig.local` -- never tracked in git:

```bash
cp ~/apps/dotfiles/gitconfig.local.example ~/.gitconfig.local
```

Edit `~/.gitconfig.local` and fill in your details:

```ini
[user]
    name = Your Name
    email = your@email.com
```

Running `dotfiles doctor` will warn you if this file is missing.

## Step 4: Personal shell config (optional)

Create `~/.zshrc.local` for personal aliases, tokens, or PATH additions:

```bash
touch ~/.zshrc.local
```

This file is sourced at the end of `.zshrc` and is gitignored.

For secrets and API keys, create `~/.zshenv.secrets`:

```bash
touch ~/.zshenv.secrets
```

This file is sourced by `.zshenv` and should never be committed.

See [Environment variables](../README.md#environment-variables) in the README for the full list of configurable variables, their defaults, and what they control.

## Step 5: Verify your setup

```bash
dotfiles doctor --fix
```

This runs every doctor check across all modules and auto-repairs any drift (`dotfiles doctor --list` shows the live set). Common first-run fixes:
- Symlinks created for gitconfig, zshrc, zshenv
- Git config defaults applied (pull.rebase, push.autoSetupRemote, etc.)
- LaunchAgents loaded for sync, doctor, cleanup

## Skipping checks you don't need

Not every check applies to every developer. If you don't use JetBrains, Ghostty, or enterprise tools, those checks will report warnings. You can skip them permanently.

**List all available check IDs:**

```bash
dotfiles doctor --list
```

**Skip a check permanently:**

```bash
dotfiles doctor --skip jetbrains.ideavimrc
```

This adds the check ID to `~/apps/dotfiles/.overrides`. The doctor will skip that check on all future runs.

**Example workflow:** "I don't use JetBrains, how do I stop seeing those warnings?"

```bash
# See which JetBrains checks are failing
dotfiles doctor --module jetbrains

# Skip them all
dotfiles doctor --skip jetbrains.ideavimrc
dotfiles doctor --skip jetbrains.settings_sync
```

**Validate your overrides** (useful after repo updates that may rename check IDs):

```bash
dotfiles doctor --validate-overrides
```

The `.overrides` file is tracked in git, so your team fork can pre-configure which checks to skip for your group.

## Profiles

| Dimension | `core` | `full` |
|-----------|--------|--------|
| Doctor modules | 7 enabled (14 auto-skipped) | All 21 |
| Brew packages | essentials set (`make count` with `core`) | full profile set (`make count` with `full`) |
| macOS defaults | 90 (system) | 149 (+visual, +app prefs) |
| LaunchAgents | 7 (sync, doctor, cleanup, git-maintain, capslock, gui-path, network) | All 15 (+morning, upgrade, chrome-debug, etc.) |
| Config files | zshrc, zshenv, gitconfig, starship, ssh | +tmux, Ghostty, lazygit, JetBrains, fastfetch |
| Best for | Team-wide baseline -- minimal opinions | Power users -- opinionated terminal + editor setup |

**Recommendation:** Start with `core`. It covers everything needed for day-to-day work. Upgrade to `full` later if you want tmux, Ghostty, or the extra CLI tools.

Switch anytime:

```bash
dotfiles profile full    # switch to full
dotfiles profile core    # switch to core
dotfiles apply           # deploy the change
```

## Enterprise mode

Toggle enterprise-specific tools (AWS CLI, K8s, Gradle, Java 21, enterprise SSH):

```bash
dotfiles enterprise on   # enable
dotfiles enterprise off  # disable
dotfiles apply
```

**What gets installed:** Enterprise mode sets `is_enterprise: true` in your chezmoi config, which conditionally includes the `enterprise` module on the next `dotfiles apply`. This adds:

| Tool | What it provides |
|------|-----------------|
| AWS CLI | `aws` command for cloud access |
| Kubernetes tools | `kubectl`, `helm`, and related CLIs |
| Gradle | JVM build system |
| Java 21 (Temurin) | JDK for JVM-based services |
| Enterprise SSH config | Host aliases and proxy settings for internal infrastructure |

## Day-to-day commands

```bash
dotfiles apply           # re-deploy config after editing source files
dotfiles update          # pull latest changes + re-apply
dotfiles doctor --fix    # audit + auto-repair drift
dotfiles stats           # see automation stats (runs, time saved)
dotfiles cheat           # quick command reference
```

## Customizing your fork

### Adding a Homebrew package

```bash
dotfiles brew-add <package>              # core formula
dotfiles brew-add <package> --cask       # GUI app
dotfiles brew-add <package> --full-only  # full profile only
```

### Adding a config file

```bash
dotfiles add ~/.some-config              # symlink mode (default)
dotfiles add ~/.some-config --copy       # copy mode
```

### Creating a doctor module

```bash
dotfiles new-module <name>
# Edit modules/<name>/doctor.sh with your checks
```

### Adding a macOS default

```bash
dotfiles defaults-add <domain> <key> <value> <type>
```

## Troubleshooting

> For the full symptom-first troubleshooting guide, see [troubleshooting.md](troubleshooting.md).

### `chezmoi init` fails with age encryption error

You selected `use_encryption: true` but don't have an age key. Two options:

**Option A: Generate an age key** (if you want encrypted secrets):

```bash
mkdir -p ~/.config/chezmoi
age-keygen -o ~/.config/chezmoi/key.txt
```

This creates a key pair. The public key (printed to stdout) is your `age_recipient` -- save it somewhere safe. The private key in `key.txt` decrypts secrets managed by chezmoi. Use encryption for sensitive files like SSH configs or API tokens that you want stored encrypted in the repo.

Then re-run init and select `true` for age encryption when prompted, pasting your public key as the recipient.

**Option B: Skip encryption** (simpler setup):

```bash
chezmoi init --source ~/apps/dotfiles --apply
```

Select `false` for age encryption when prompted.

### `dotfiles doctor` shows git.local_config failure

Create `~/.gitconfig.local` -- see Step 3 above.

### LaunchAgents not loading

```bash
dotfiles doctor --fix --module workflow
```

This auto-loads all LaunchAgent plists.

## Rollback / Recovery

If something goes wrong during setup, here's how to undo changes.

### Full removal

```bash
dotfiles uninstall          # remove all symlinks and LaunchAgents
dotfiles uninstall --dry-run  # preview what would be removed
```

This removes chezmoi-managed symlinks and unloads LaunchAgents. Your personal files (`~/.gitconfig.local`, `~/.zshrc.local`, `~/.zshenv.secrets`) are preserved.

### Revert git config

```bash
rm ~/.gitconfig.local       # remove personal overrides
git config --global --unset-all user.name   # if set globally by accident
```

### Revert Homebrew packages

```bash
brew list --formula | xargs brew uninstall   # nuclear option -- removes all formulae
brew list --cask | xargs brew uninstall      # remove all casks
```

### macOS defaults

macOS defaults changed by `macos.sh` **do not auto-revert**. To reset a specific default:

```bash
defaults delete <domain> <key>    # remove the custom value
# Example: defaults delete NSGlobalDomain KeyRepeat
```

For a full reset to stock macOS behavior, review `macos.sh` and reverse each `defaults write` command. A system restart applies most changes.

## Further reading

- [README.md](../README.md) -- full feature overview, CLI reference, performance benchmarks
- [CONTRIBUTING.md](../CONTRIBUTING.md) -- architecture and editing rules
- [AGENTS.md](../AGENTS.md) -- ownership boundaries, repo layout
- [Forking guide](forking-guide.md) -- what to keep, remove, and customize when adopting
- [Multi-machine setup](multi-machine.md) -- syncing dotfiles across multiple Macs
- [Migration guide](migration.md) -- migrating from plain symlinks, Stow, yadm, or bare git repos
