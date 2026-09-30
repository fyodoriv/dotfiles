# Migrating from Existing Dotfiles

Already have dotfiles? This guide helps you adopt this repo without losing your setup.

## Pre-flight checklist

Before starting, verify these:

- [ ] You have a backup of `~/.zshrc`, `~/.gitconfig`, and any custom shell config
- [ ] You know what dotfiles manager you're using (if any)
- [ ] You've read the [README](../README.md) to understand what this repo does
- [ ] Homebrew is installed (`brew --version`)

## What gets preserved automatically

This repo is designed to **not overwrite personal config**:

| File | Purpose | What happens |
|------|---------|-------------|
| `~/.zshrc.local` | Personal aliases, tokens, PATH entries | Never touched — sourced by `~/.zshrc` |
| `~/.gitconfig.local` | Your name, email, signing key | Never touched — included by `~/.gitconfig` |
| `~/.zshenv.secrets` | API keys, tokens | Never touched — sourced by `~/.zshenv` |

If you put your personal config in these files before migrating, nothing is lost.

## Step 1: Back up existing config

Regardless of your current setup, start by backing up:

```bash
# Create a timestamped backup directory
backup_dir="$HOME/.dotfiles-backup-$(date +%Y%m%d)"
mkdir -p "$backup_dir"

# Back up key files
for f in .zshrc .zshenv .gitconfig .gitignore_global .tmux.conf .ideavimrc; do
  [ -f "$HOME/$f" ] && cp -L "$HOME/$f" "$backup_dir/"  # -L follows symlinks
done

# Back up directories
for d in .config/ghostty .config/starship.toml .ssh/config; do
  [ -e "$HOME/$d" ] && cp -rL "$HOME/$d" "$backup_dir/"
done

echo "Backed up to $backup_dir"
ls -la "$backup_dir"
```

## Step 2: Extract personal config

Move your personal settings into the override files *before* installing:

```bash
# Create personal shell config
touch ~/.zshrc.local
# Move any personal aliases, PATH additions, tokens here

# Create personal git config
touch ~/.gitconfig.local
# Add: [user] name, email, signingkey
```

Look through your current `~/.zshrc` for anything personal (company VPN commands, team-specific aliases, etc.) and put them in `~/.zshrc.local`.

## Step 3: Remove old management

### Migrating from plain symlinks

If you manually symlinked dotfiles:

```bash
# List current symlinks pointing to your old dotfiles
ls -la ~/.zshrc ~/.gitconfig ~/.tmux.conf 2>/dev/null | grep ' -> '

# Remove symlinks (leaves the source files intact)
for f in .zshrc .zshenv .gitconfig .tmux.conf .ideavimrc; do
  [ -L "$HOME/$f" ] && rm "$HOME/$f"
done
```

### Migrating from GNU Stow

If you use Stow:

```bash
# Unstow all packages (removes symlinks, keeps source)
cd ~/dotfiles  # or wherever your stow dir is
for pkg in */; do
  stow -D "${pkg%/}" 2>/dev/null
done
```

### Migrating from yadm

If you use yadm:

```bash
# List what yadm manages
yadm list

# Remove yadm tracking (files stay in place, yadm stops managing them)
yadm gitconfig --unset core.worktree
# Or more aggressively: remove yadm entirely
# brew uninstall yadm && rm -rf ~/.local/share/yadm
```

### Migrating from a bare git repo

If you use the `git --bare` method:

```bash
# Check what's tracked
git --git-dir=$HOME/.dotfiles --work-tree=$HOME status

# Remove the bare repo (tracked files stay in place)
rm -rf ~/.dotfiles  # or wherever your bare repo is
# Remove the alias from your shell config
```

## Step 4: Install

```bash
git clone https://github.com/<your-org>/dotfiles.git ~/apps/dotfiles
chezmoi init --source ~/apps/dotfiles --apply
```

During init, you'll be prompted for:
- **Profile**: `core` (team-friendly) or `full` (opinionated)
- **Enterprise mode**: on/off (enables org-specific overlay config)
- **AI tooling**: opt-in for Devin/Claude agent config

## Step 5: Verify

```bash
# Run doctor to check everything
dotfiles doctor --fix

# Verify your personal config is loaded
echo $PATH              # should include your custom entries from ~/.zshrc.local
git config user.name    # should show your name from ~/.gitconfig.local
```

## Rollback

If something goes wrong, roll back completely:

```bash
# 1. Remove chezmoi-managed files
chezmoi purge           # removes all managed files from ~/ and chezmoi state

# 2. Restore from backup
backup_dir="$HOME/.dotfiles-backup-YYYYMMDD"  # use your actual date
for f in "$backup_dir"/*; do
  cp -r "$f" "$HOME/.$(basename "$f")"
done

# 3. Restart shell
exec zsh
```

To roll back only macOS defaults, each `defaults write` in `macos.sh` can be reversed with `defaults delete`. The `setup-dock` command saves a Dock backup automatically — restore with the command shown in its output.

## Keeping your old config alongside

If you want to test before committing:

1. Install to a temporary location: `chezmoi init --source ~/apps/dotfiles` (without `--apply`)
2. Preview what would change: `chezmoi diff`
3. Apply only when ready: `chezmoi apply`
4. Revert anytime: `chezmoi purge`

## FAQ

**Q: Will this overwrite my SSH keys?**
No. The repo manages `~/.ssh/config` (SSH client config), not `~/.ssh/id_*` (keys). Your keys are untouched.

**Q: I have company-specific git config (proxy, insteadOf URLs). Where does it go?**
In `~/.gitconfig.local`. This file is included by the managed `~/.gitconfig` and never overwritten.

**Q: Can I keep some of my old aliases?**
Yes. Put them in `~/.zshrc.local`. It's sourced at the end of `~/.zshrc`, so your aliases take precedence.

**Q: What if `dotfiles doctor` reports failures?**
Run `dotfiles doctor --fix` to auto-repair. For checks you want to skip permanently, use `dotfiles doctor --skip <check-id>` (stored in `~/apps/dotfiles/.overrides`).
