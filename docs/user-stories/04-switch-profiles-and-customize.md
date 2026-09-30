# User Story: Switch Profiles and Customize Per Machine

> Switch between core and full profiles instantly, add enterprise tools, or override shared config — without changing the shared repo.

## Switch Profile

```bash
dotfiles profile full     # switch to full and apply
dotfiles profile core     # switch to core and apply
dotfiles profile          # show current profile
```

| Profile | Modules | Best for |
|---------|---------|----------|
| `core` | git, macos, ssh, tools, workflow, sync, security | Team machines, minimal |
| `full` | core + shell, editor, jetbrains, terminal, prompt, extras, upgrade, claude, cursor, agentbrew, agent-browser, chrome, devin, enterprise | Personal daily driver |

Profile controls four things:
- **File deployment** — `.chezmoiignore` skips files conditionally (core deploys fewer files)
- **Homebrew packages** — brew script gates packages by profile
- **macOS defaults** — visual and app-specific defaults only in full profile
- **LaunchAgents** — `run_onchange_launchagents.sh.tmpl` skips full-only agents (morning, sleepwatcher, agent-browser-chrome, etc.) on core

Switching to `core` won't uninstall full-only packages, but they won't be managed or updated.

## Enterprise Toggle

Independent of profile — you can be `core` + `enterprise` or `full` + `enterprise`:

```bash
dotfiles enterprise on    # adds AWS, K8s, Gradle, Java, company tools
dotfiles enterprise off
```

## Per-Machine Overrides

The shared repo defines defaults. Each machine stores overrides in two places — neither is committed:

| Override layer | What it controls | File |
|---------------|-----------------|------|
| **Chezmoi data** | Profile, enterprise flag, machine-level toggles | `~/.config/chezmoi/chezmoi.yaml` |
| **`.local` files** | Name, email, aliases, paths | `~/.gitconfig.local`, `~/.zshrc.local` |

```bash
# Set your git identity
cat >> ~/.gitconfig.local << 'EOF'
[user]
  name = Your Name
  email = your@email.com
EOF
```

These local files are gitignored and never overwritten by `git pull` or `dotfiles apply`.

## Files Involved

| File | Purpose |
|------|---------|
| `.chezmoi.yaml.tmpl` | Profile prompts and data schema |
| `~/.config/chezmoi/chezmoi.yaml` | Stored profile + enterprise selection (not committed) |
| `.chezmoiignore` | Conditional file exclusions by profile |
| `~/.gitconfig.local`, `~/.zshrc.local` | Per-machine overrides (not committed) |
