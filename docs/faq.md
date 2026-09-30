# FAQ

Common questions about setup, customization, and daily use.

---

## Setup

### Will this overwrite my existing config files?

No. Chezmoi uses symlink mode for most files — your `~/.zshrc` becomes a symlink to `home/zshrc` in the dotfiles repo. If a regular file already exists, `chezmoi diff` shows you what would change before `chezmoi apply` does anything. Your personal config lives in `~/.zshrc.local` and `~/.gitconfig.local`, which are never tracked or overwritten.

### Will this overwrite my SSH keys?

No. The dotfiles only manage `~/.ssh/config` (connection settings). Your private keys (`id_ed25519`, `id_rsa`, etc.) are never touched, tracked, or overwritten.

### What's the difference between `core` and `full` profiles?

| Dimension | `core` | `full` |
|-----------|--------|--------|
| Brew packages | essentials set — run `make count` on `core` | full profile set — run `make count` on `full` |
| macOS defaults | 90 (system) | 149 (+visual, +app prefs) |
| LaunchAgents | 7 (sync, doctor, cleanup, etc.) | All 15 (+morning, upgrade, etc.) |
| Config files | zshrc, zshenv, gitconfig, starship, ssh | +tmux, Ghostty, lazygit, JetBrains |
| Best for | Team-wide baseline | Power users |

Start with `core`. Upgrade anytime: `dotfiles profile full && dotfiles apply`.

### What if I don't enable enterprise mode?

Everything works fine. Enterprise mode adds AWS CLI, kubectl, Gradle, Java 21, and enterprise SSH config. Skip it if you don't need those tools. Enable later with `dotfiles enterprise on && dotfiles apply`.

### Do I need to be on VPN during setup?

Only if cloning from a GitHub Enterprise host (e.g. `<your-ghe-host>`). Disconnect VPN before running `chezmoi init` — Homebrew downloads may time out behind the corporate proxy. Reconnect after setup.

---

## Customization

### Where do I put personal aliases and shell config?

`~/.zshrc.local` — sourced at the end of `.zshrc`, gitignored. Create it with `touch ~/.zshrc.local`.

### Where do I put API keys and secrets?

`~/.zshenv.secrets` — sourced by `.zshenv` on every shell startup, gitignored. Copy the template: `cp ~/apps/dotfiles/home/zshenv.secrets.example ~/.zshenv.secrets`.

### How do I add a Homebrew package?

```bash
dotfiles brew-add <package>              # core formula
dotfiles brew-add <package> --cask       # GUI app
dotfiles brew-add <package> --full-only  # full profile only
```

### How do I switch profiles?

```bash
dotfiles profile full    # switch to full
dotfiles profile core    # switch back to core
dotfiles apply           # deploy the change
```

### How do I add a config file to be managed?

```bash
dotfiles add ~/.some-config              # symlink mode (default)
dotfiles add ~/.some-config --copy       # copy mode
```

### I already have a dotfiles setup. Can I migrate?

Yes. See the [migration guide](migration.md). Chezmoi shows diffs before applying — you can review every change. Your personal config survives in `.local` files.

### How do I fork this for my team?

See the [forking guide](forking-guide.md). Key steps: fork the repo, update `.chezmoi.yaml.tmpl` prompts for your org, customize the Brewfile, remove modules you don't need.

---

## Daily Use

### How do I update when the repo changes?

```bash
dotfiles update   # pulls latest + re-applies
```

Or let the auto-sync LaunchAgent handle it — it runs every 30 minutes.

### What does `dotfiles doctor` actually check?

Health checks across modules: shell config, git settings, SSH permissions, macOS defaults, LaunchAgents, security posture, and more. Run `dotfiles doctor --list` to see all check IDs.

### `dotfiles doctor` shows failures — is that bad?

Not always. Some checks are informational (cosmetic severity). Run `dotfiles doctor --fix` to auto-repair what it can. For checks that don't apply to your setup, skip them permanently:

```bash
dotfiles doctor --skip <CHECK_ID>
```

`--skip` validates the ID first, so run `dotfiles doctor --list` to copy the
exact check ID. Typos are rejected without changing `.overrides`.

### How do I check just one module?

```bash
dotfiles doctor --module git      # only git checks
dotfiles doctor --module security # only security checks
```

### How do I see all check IDs?

```bash
dotfiles doctor --list
```

### How do I permanently skip a check?

```bash
dotfiles doctor --skip <CHECK_ID>
```

Skips are stored in `.overrides` and persist across runs. `--skip` avoids
duplicate entries and rejects unknown IDs; verify existing entries with
`dotfiles doctor --validate-overrides`.

### Where are doctor logs?

`~/Library/Logs/dotfiles-doctor.log` (from the weekly LaunchAgent). For interactive runs, output goes to your terminal.

---

## Enterprise & Security

### How do I enable age encryption?

```bash
age-keygen -o ~/.config/chezmoi/key.txt
# Note the public key from stdout
# Re-run chezmoi init, select use_encryption: true, paste your public key
dotfiles apply
```

See [key-rotation.md](key-rotation.md) for rotation procedures.

### What's the difference between runtime secrets and encrypted files?

Two layers:
1. **Runtime secrets** (`~/.zshenv.secrets`) — plaintext, gitignored, sourced at shell startup. For API tokens, passwords.
2. **Encrypted files** (`encrypted_*.age`) — tracked in git, decrypted by chezmoi using your age key. For secrets shipped by an org overlay (for example enterprise SSH config).

See [security-model.md](security-model.md) for details.

### What macOS defaults does this change?

90 system defaults (all profiles) plus 59 more on `full`. Categories: keyboard speed, Finder settings, Spotlight pruning/exclusions, 15-minute idle lock, animation removal, privacy/analytics opt-outs, power management. Review `macos.sh` for the full list. All changes are user-scoped except power management (`sudo pmset`).

### Are git hooks blocking or advisory?

- **Blocking**: secret scanning, forbidden file types, shellcheck, excessive deletions
- **Advisory**: JIRA ticket reference, branch naming convention

Bypass once with `git commit --no-verify`. See [security-model.md](security-model.md#git-hooks) for details.

---

## Troubleshooting

### Shell startup is slow (>200ms)

Tool init caches are stale. Fix: `dotfiles doctor --fix --module shell`. Verify: `time zsh -i -c exit`.

### `command not found: brew`

Homebrew not on PATH. Check: `ls /opt/homebrew/bin/brew`. If missing, install Homebrew. If present, verify `~/.zshrc` is a symlink: `dotfiles doctor --fix --module shell`.

### `chezmoi apply` shows unexpected diffs

A tracked file was edited directly. Preview: `chezmoi diff`. Accept dotfiles version: `chezmoi apply --force`. Or keep your version: `chezmoi re-add ~/.zshrc`.

### LaunchAgents not running

```bash
dotfiles doctor --fix --module workflow
launchctl list | grep com.dotfiles
```

### How do I completely uninstall?

```bash
dotfiles uninstall          # removes symlinks and LaunchAgents
dotfiles uninstall --dry-run  # preview first
```

Personal files (`~/.gitconfig.local`, `~/.zshrc.local`, `~/.zshenv.secrets`) are preserved.

For the full symptom-first troubleshooting guide, see [troubleshooting.md](troubleshooting.md).

---

## What's the difference between dotfiles and agentbrew?

| | dotfiles | agentbrew |
|--|----------|-----------|
| **Manages** | Shell config, git, SSH, macOS defaults, LaunchAgents | AI agent config (MCP servers, skills, rules) |
| **Config files** | `~/.zshrc`, `~/.gitconfig`, `~/.ssh/config` | `~/.claude/`, `~/.cursor/mcp.json` |
| **Tool** | chezmoi | agentbrew CLI |
| **Source** | `~/apps/dotfiles` | `Agentfile.yaml` in each repo |

Rule: never have both write to the same target path.

---

## Further Reading

- [Onboarding guide](onboarding.md) — full setup walkthrough
- Your organization's overlay onboarding doc — enterprise-specific steps
- [Troubleshooting](troubleshooting.md) — symptom-first fixes
- [Forking guide](forking-guide.md) — how to adopt for your team
- [Security model](security-model.md) — trust boundaries and audit
- [Key rotation](key-rotation.md) — age and SSH key procedures
- [Verify setup](verify-setup.md) — post-install checklist
