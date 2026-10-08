# User Story: Set Up a New Mac in One Command

> Clone, run one command, answer the chezmoi init prompts — fully configured development environment.

## Steps

```bash
git clone https://github.com/<your-org>/dotfiles.git ~/apps/dotfiles
chezmoi init --source ~/apps/dotfiles --apply
```

Prompts cover profile, enterprise mode, AI tooling, paths, auto-upgrade, encryption, and your git identity, plus a few conditional follow-ups — see the [README configuration table](../../README.md#configuration) for the full list and defaults.

The bootstrap script auto-creates `~/.gitconfig.local` and prompts for your name and email.

## What Happens

`chezmoi init --apply` triggers the full lifecycle:

1. **Renders templates** — profile-conditional files via `.chezmoi.yaml.tmpl`
2. **Deploys symlinks** — `home/*` → `~/.*` (gitconfig, zshrc, tmux, etc.)
3. **Copies managed files** — `dot_*` → `~/.*` (editorconfig, npmrc, etc.)
4. **Runs lifecycle scripts** (in order):
   - `run_once_bootstrap.sh` — Homebrew, Xcode CLT, gitconfig.local
   - `run_onchange_brew.sh.tmpl` — all Homebrew packages
   - `run_onchange_macos.sh.tmpl` — core macOS defaults
   - `run_onchange_launchagents.sh.tmpl` — profile-gated LaunchAgents

## Permission Prompts

Up to 4 during first run:

1. **Xcode Command Line Tools** — git, compilers
2. **GitHub authentication** — cloning/pushing
3. **sudo for Homebrew** — system-managed paths
4. **macOS system prompts** — system behavior settings

## Profiles

| Profile | Modules | Best for |
|---------|---------|----------|
| `core` | git, macos, ssh, tools, workflow, sync, security | Team machines, minimal setup |
| `full` | core + shell, editor, jetbrains, terminal, prompt, extras, upgrade, claude, cursor, agentbrew, agent-browser, chrome, enterprise | Personal daily driver |

## Files Involved

| Source | Purpose |
|--------|---------|
| `.chezmoi.yaml.tmpl` | Profile prompts and data |
| `.chezmoiscripts/run_once_bootstrap.sh` | First-time Homebrew + CLT + gitconfig.local |
| `.chezmoiscripts/run_onchange_brew.sh.tmpl` | Package installation |
| `.chezmoiscripts/run_onchange_launchagents.sh.tmpl` | LaunchAgent setup |
| `bin/dotfiles` | CLI wrapper |
