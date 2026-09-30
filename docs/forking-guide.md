# Forking & Adoption Guide

How to fork this repo and adapt it for your team. Covers what to keep, what to remove, how to change enterprise variables, and how to add your own tools.

## Quick start

```bash
# 1. Fork the repo on GitHub, then clone your fork
git clone git@github.com:<your-org>/dotfiles.git ~/apps/dotfiles

# 2. Initialize chezmoi — you'll be prompted for profile and options
chezmoi init --source ~/apps/dotfiles --apply

# 3. Verify everything works
dotfiles doctor --fix
```

During `chezmoi init`, you'll be asked for configuration values. See [Configuration variables](#configuration-variables) for what each one does.

## Configuration variables

All values are prompted once at `chezmoi init` and stored in `~/.config/chezmoi/chezmoi.yaml`. Edit that file and run `dotfiles apply` to change them later.

| Variable | Default | Purpose |
|----------|---------|---------|
| `profile` | `full` | `core` (team-friendly) or `full` (opinionated) |
| `is_enterprise` | `false` | Enable enterprise tools (AWS, K8s, Gradle, enterprise SSH) |
| `work_email_domain` | `example.com` | Work email domain for Chrome profile detection (enterprise only) |
| `github_enterprise_host` | `github.example.com` | GitHub Enterprise hostname (enterprise only) |
| `use_ai_tools` | `false` | Enable AI agent tooling (Devin CLI, ANTHROPIC_MODEL, agent-browser) |
| `dotfiles_dir` | `apps/dotfiles` | Dotfiles repo path relative to `$HOME` |
| `repos_dir` | `apps` | Repos directory relative to `$HOME` (exported as `DOTFILES_REPOS_DIR`) |
| `brew_skip` | `[]` | List of Homebrew packages to exclude (e.g. `["poetry", "pyenv"]`) |
| `auto_upgrade` | `false` | Enable auto-upgrade LaunchAgent (brew upgrade weekly) |
| `use_encryption` | `false` | Enable age encryption for secrets |

**For your team:** change the defaults in `.chezmoi.yaml.tmpl` to match your organization. For example, set `work_email_domain` default to `yourcompany.com` and `github_enterprise_host` to `github.yourcompany.com`.

## Choose a profile

| | Core | Full |
|--|------|------|
| **Modules** | 7 | 21 |
| **Homebrew packages** | essentials (`make count`, `core` profile) | full profile (`make count`, `full` profile) |
| **Opinionated?** | No | Yes |
| **Best for** | Team-wide rollout | Individual power users |

Start with `core` for team adoption. Users can upgrade to `full` later:

```bash
dotfiles profile full    # switch to full
dotfiles profile core    # switch back to core
```

> If your organization keeps a private overlay (e.g. `dotfiles-<org>`), see its onboarding doc for recommended `profile` / `is_enterprise` / `use_ai_tools` combinations per role.

## Removing modules you don't need

Every module lives in `modules/<name>/doctor.sh`. Deleting the directory removes all its health checks.

**Safe removal steps:**

```bash
# 1. Check the dependency table below
# 2. Delete the module
git rm -r modules/<name>

# 3. Verify nothing broke
dotfiles doctor

# 4. Commit (--no-verify bypasses the pre-commit hook that protects module deletion)
git commit --no-verify -m "chore: remove <name> module"
```

**Cross-module dependencies:**

| Module | Depended on by | Safe to remove? |
|--------|----------------|-----------------|
| `tools` | shell (fzf/zoxide cache), git (delta pager) | Yes, but fzf/delta checks will fail |
| `shell` | git (PATH for bin/), sync (stats) | Yes, but some path checks will fail |
| `extras` | macos (dockutil for Dock config) | Yes, macos gracefully skips dockutil |
| `agentbrew` | claude, cursor (MCP server registration) | Yes, unless you use AI coding agents |

**Common removals for team forks:**

| If your team doesn't use... | Remove these modules |
|------------------------------|---------------------|
| AI coding agents | `claude`, `cursor`, `agentbrew`, `agent-browser`, `devin` |
| JetBrains IDEs | `jetbrains` |
| Enterprise tools (AWS, K8s) | `enterprise` |
| Ghostty terminal | `terminal` (or just remove Ghostty checks) |

## Changing enterprise variables

If your company uses GitHub Enterprise:

1. **Edit `.chezmoi.yaml.tmpl`** — change the default values:
   ```yaml
   work_email_domain: "yourcompany.com"      # was: example.com
   github_enterprise_host: "github.yourcompany.com"  # was: github.example.com
   ```

2. **Edit enterprise SSH config** — update `private_dot_ssh/config.enterprise.tmpl` with your organization's SSH hosts.

## Authoring an organization overlay

Org-specific configuration (private Homebrew taps, internal MCP servers, custom
doctor checks, role-based onboarding docs) does **not** belong in this OSS
repo. The supported pattern is an "overlay" repo that plugs into a small
public extension API.

Recommended layout: a second repo named `dotfiles-<org>` at
`~/apps/dotfiles-<org>/`. Auto-discovered hooks:

| Hook                | Overlay path                | Loaded by                                            |
| ------------------- | --------------------------- | ---------------------------------------------------- |
| `EXTRA_DOCTOR_DIR`  | `modules/<name>/doctor.sh`  | `bin/dotfiles-doctor`                                |
| `EXTRA_BREWFILE`    | `brewfile/Brewfile`         | `.chezmoiscripts/run_onchange_brew.sh.tmpl`          |
| `EXTRA_VALIDATE_DIR`| `validate/<name>.sh`        | `bin/dotfiles-validate`                              |
| `EXTRA_AGENTFILE`   | `Agentfile.yaml`            | `.chezmoiscripts/run_after_agentbrew-sync.sh`        |

If the overlay isn't installed, every hook is a no-op — the OSS dotfiles
repo works standalone exactly as the public release intends. When the
overlay is present, its content layers on top.

## Customizing the enterprise module

The enterprise module (`modules/enterprise/doctor.sh`) checks that enterprise-specific CLI tools are installed. By default it checks for `aws`, `kubectl`, `gradle`, and `java`. Customize this for your organization:

### Changing the enterprise tool list

Edit `modules/enterprise/doctor.sh` to add or remove tools:

```bash
#!/bin/bash
# Doctor checks for enterprise module

# Replace this list with your org's required tools
for tool in aws kubectl terraform vault; do
  case "$tool" in
    aws)       brew_pkg="awscli" ;;
    kubectl)   brew_pkg="kubernetes-cli" ;;
    terraform) brew_pkg="hashicorp/tap/terraform" ;;
    vault)     brew_pkg="hashicorp/tap/vault" ;;
    *)         brew_pkg="$tool" ;;
  esac
  check "enterprise.$tool" "$tool installed" "command -v $tool" "brew install $brew_pkg"
done
```

The `case` block maps CLI command names to Homebrew package names (they differ for some tools). Each `check` line creates a doctor health check that verifies the tool is installed and can auto-fix by running `brew install`.

### Adding org-specific Homebrew taps

If your enterprise tools come from a private tap, add the tap to the Brewfile in `.chezmoiscripts/run_onchange_brew.sh.tmpl`:

```bash
# Inside the brew bundle section, add your tap:
tap "yourcompany/internal"
brew "yourcompany/internal/your-cli-tool"
```

Then add the corresponding doctor check in `modules/enterprise/doctor.sh`:

```bash
check "enterprise.your_tool" "your-cli-tool installed" \
  "command -v your-cli-tool" "brew install yourcompany/internal/your-cli-tool"
```

### Encrypted enterprise SSH config

The base repo ships no encrypted SSH config. The org overlay carries it. Put an
age-encrypted `encrypted_config.enterprise.age` in the overlay's `private_dot_ssh/`
directory. chezmoi decrypts it to `~/.ssh/config.enterprise` when
`use_encryption: true` is set.

To create one:

```bash
cat > /tmp/config.enterprise << 'EOF'
Host github.yourcompany.com
  HostName github.yourcompany.com
  IdentityFile ~/.ssh/id_ed25519
EOF
chezmoi encrypt /tmp/config.enterprise > private_dot_ssh/encrypted_config.enterprise.age
rm /tmp/config.enterprise
```

To use a plain-text config instead, add a template in the overlay:

```bash
cat > private_dot_ssh/config.enterprise.tmpl << 'EOF'
Host {{ .github_enterprise_host }}
  HostName {{ .github_enterprise_host }}
  IdentityFile ~/.ssh/id_ed25519
EOF
```

## Adding team-specific tools

**Add a Homebrew package:**

```bash
dotfiles brew-add <package>                  # CLI tool (all profiles)
dotfiles brew-add <package> --cask           # GUI app
dotfiles brew-add <package> --full-only      # only in full profile
```

This adds the package to the inline Brewfile in `.chezmoiscripts/run_onchange_brew.sh.tmpl` and creates a doctor check.

**Add a macOS default:**

```bash
dotfiles defaults-add com.apple.dock tilesize 48 int
```

**Create a new doctor module:**

```bash
dotfiles new-module mytools --severity important
# Edit modules/mytools/doctor.sh to add checks
```

## Disabling AI tooling

If your team doesn't use AI coding agents, the simplest approach:

1. Set `use_ai_tools: false` (the default) during `chezmoi init`
2. Remove these modules entirely:
   ```bash
   git rm -r modules/{claude,cursor,agentbrew,agent-browser,devin}
   git commit --no-verify -m "chore: remove AI tooling modules"
   ```
3. Remove the agentbrew lifecycle script:
   ```bash
   git rm .chezmoiscripts/run_after_agentbrew-sync.sh
   git rm .chezmoiscripts/run_after_devin-caffeinate.sh
   ```
4. Remove `home/zshrc.ai-tools` if you don't want the file in your repo at all.

## Creating a custom profile

The repo ships with two profiles (`core` and `full`). Large teams may want additional profiles for different roles — e.g., `frontend`, `backend`, or `devops`. Here's a worked example of adding a `backend` profile.

### Step 1: Add the choice to `.chezmoi.yaml.tmpl`

Update the profile prompt to include your new option:

```go
{{- $choices := list "full" "core" "backend" -}}
{{- $profile := promptChoiceOnce . "profile" "Installation profile (full = all modules, core = essential only, backend = backend services)" $choices "core" -}}
```

The first line defines valid choices. The second prompts the user and stores the selection. The last argument (`"core"`) is the default.

### Step 2: Gate files in `.chezmoiignore`

Add a block to `.chezmoiignore` to exclude files that backend developers don't need:

```go
{{- if eq .profile "backend" }}
# Backend profile: skip frontend/editor config
.ideavimrc
.tmux.conf
.config/ghostty
.config/lazygit
.config/fastfetch
{{- end }}
```

**How it works:** `.chezmoiignore` uses Go template syntax. Lines inside the `if` block are **target paths** (relative to `$HOME`) that chezmoi will skip during `apply`. The `eq .profile "backend"` condition checks the stored profile value.

### Step 3: Gate Homebrew packages in the Brewfile

In `.chezmoiscripts/run_onchange_brew.sh.tmpl`, add a profile-gated section:

```bash
{{ if eq .profile "backend" -}}
# Backend-specific tools
brew "postgresql@16"
brew "redis"
brew "protobuf"
brew "grpcurl"
{{ end -}}
```

This block is rendered by chezmoi before the script runs, so packages only appear in the Brewfile when the profile matches.

### Step 4: Gate doctor checks in modules

In any `modules/<name>/doctor.sh` where checks should be profile-specific, gate them:

```bash
# Only run for backend profile
if [ "${DOTFILES_PROFILE:-full}" = "backend" ]; then
  check "enterprise.postgresql" "postgresql running" \
    "pg_isready -q" ""
fi
```

The `$DOTFILES_PROFILE` variable is set by `dotfiles-doctor` from the chezmoi config data. Doctor modules can read it to conditionally run checks.

### Step 5: Gate LaunchAgents (optional)

If your profile needs specific LaunchAgents, gate them in `.chezmoiscripts/run_onchange_launchagents.sh.tmpl`:

```bash
{{ if or (eq .profile "full") (eq .profile "backend") -}}
load_agent "com.dotfiles.db-maintain"
{{ end -}}
```

### Step 6: Test

```bash
# Re-initialize with the new profile
chezmoi init --source ~/apps/dotfiles
# Select "backend" when prompted

# Apply and verify
dotfiles apply
dotfiles doctor --fix
```

### Summary of gating mechanisms

| What to gate | Where | Syntax |
|-------------|-------|--------|
| Config files deployed to `$HOME` | `.chezmoiignore` | `{{ if eq .profile "backend" }}` target paths `{{ end }}` |
| Homebrew packages | `.chezmoiscripts/run_onchange_brew.sh.tmpl` | `{{ if eq .profile "backend" }}` brew lines `{{ end }}` |
| macOS defaults | `.chezmoiscripts/run_onchange_macos.sh.tmpl` | Same Go template syntax |
| Doctor health checks | `modules/<name>/doctor.sh` | `if [ "$DOTFILES_PROFILE" = "backend" ]; then ... fi` |
| LaunchAgents | `.chezmoiscripts/run_onchange_launchagents.sh.tmpl` | Same Go template syntax |

## Personal overrides (never touched by dotfiles)

These files are gitignored and never overwritten — safe for personal customization:

| File | Purpose |
|------|---------|
| `~/.zshrc.local` | Personal aliases, tokens, company-specific PATH |
| `~/.gitconfig.local` | Your name, email, signing key |
| `~/.zshenv.secrets` | API keys, tokens (see `home/zshenv.secrets.example`) |

## What happens on `dotfiles apply`

Chezmoi runs lifecycle scripts in order:

1. **`run_once_bootstrap.sh`** — Xcode CLT, Homebrew, chezmoi (first run only)
2. **`run_onchange_brew.sh.tmpl`** — `brew bundle` with inline Brewfile (re-runs when packages change)
3. **`run_onchange_macos.sh.tmpl`** — macOS `defaults write` commands
4. **`run_onchange_launchagents.sh.tmpl`** — render and load LaunchAgent plists
5. **`run_after_cache-inits.sh`** — cache tool init scripts to `~/.cache/zsh/`
6. **`run_after_agentbrew-sync.sh`** — sync AI agent config (if Agentfile.yaml exists)

## Checklist for team adoption

- [ ] Fork the repo
- [ ] Update `.chezmoi.yaml.tmpl` defaults for your org
- [ ] Remove modules your team doesn't need
- [ ] Edit the Brewfile to add/remove team-specific packages
- [ ] Update enterprise SSH config (or remove if not needed)
- [ ] Remove or replace the CI `validation` job
- [ ] Update README with your org's clone URL and instructions
- [ ] Test with `core` profile on a clean machine
- [ ] Share with the team

## Further reading

- [README.md](../README.md) — full feature overview
- [docs/onboarding.md](onboarding.md) — step-by-step onboarding guide
- [docs/architecture.md](architecture.md) — system architecture and data flow
- [CONTRIBUTING.md](../CONTRIBUTING.md) — development workflow and editing rules
- [docs/module-reference.md](module-reference.md) — every doctor check ID documented (live set via `dotfiles doctor --list`)
