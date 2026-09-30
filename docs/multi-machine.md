# Multi-Machine Synchronization

Guide for using these dotfiles across multiple machines — common for engineers with a work machine and a personal machine, or teams sharing a fork.

## How Sync Works

The `dotfiles-sync` LaunchAgent runs every 30 minutes on each machine:

1. **Pull** remote changes with `git pull --rebase --autostash`
2. **Apply** config via `chezmoi apply` (deploys any remote changes)
3. **Commit** local changes (additions and modifications — never deletions)
4. **Push** to all configured remotes

This means changes made on Machine A appear on Machine B within ~30 minutes, without manual intervention. Deletions are excluded from auto-sync as a safety measure and require manual commits.

When chezmoi's source is a separate applied checkout (a linked worktree on its own branch that tracks the canonical branch), sync only fast-forwards that checkout and re-runs `chezmoi apply`. It never commits or pushes from it, and it leaves the checkout untouched when it has local changes or has diverged.

---

## Setting Up a Second Machine

### 1. Clone the repo

```bash
git clone git@github.com:<your-org>/dotfiles.git ~/apps/dotfiles
```

Use the same clone path on every machine — the default is `~/apps/dotfiles`.

### 2. Initialize chezmoi

```bash
chezmoi init --source ~/apps/dotfiles --apply
```

Chezmoi will prompt you for configuration values. These are stored per-machine in `~/.config/chezmoi/chezmoi.yaml` and are **not** synced via git — each machine has its own config.

> **Tip:** You can use different settings per machine. For example, `core` profile on a work machine and `full` on a personal machine. See [Per-Machine Differences](#per-machine-differences) below.

### 3. Set up personal config

These files are machine-local and not tracked in git:

```bash
# Git identity (required)
cp ~/apps/dotfiles/gitconfig.local.example ~/.gitconfig.local
# Edit with your name and email

# Personal shell config (optional)
touch ~/.zshrc.local

# Secrets (optional — different credentials per machine)
cp ~/apps/dotfiles/home/zshenv.secrets.example ~/.zshenv.secrets
```

### 4. Verify

```bash
dotfiles doctor --fix
```

---

## Per-Machine Differences

Each machine has its own chezmoi config (`~/.config/chezmoi/chezmoi.yaml`). Common variations:

| Setting | Work machine | Personal machine |
|---------|-------------|-----------------|
| `profile` | `core` | `full` |
| `is_enterprise` | `true` | `false` |
| `use_ai_tools` | `true` | `false` |
| `auto_upgrade` | `false` | `true` |
| `use_encryption` | `true` | `false` |

To change a setting on one machine without affecting others:

```bash
chezmoi init --source ~/apps/dotfiles
# Re-answer prompts with machine-specific values
dotfiles apply
```

Or edit directly:

```bash
$EDITOR ~/.config/chezmoi/chezmoi.yaml
dotfiles apply
```

### Machine-Local Shell Config

Use `~/.zshrc.local` for machine-specific aliases, PATH additions, or tool config. This file is gitignored and sourced at the end of `.zshrc`.

```bash
# Example: work machine only
export KUBECONFIG=~/.kube/config-work
alias vpn="networksetup -connectpppoeservice 'Work VPN'"
```

---

## Handling Merge Conflicts

Auto-sync uses `git pull --rebase --autostash`, which handles most cases cleanly. Conflicts can occur when both machines edit the same file between sync cycles.

### When conflicts happen

The sync agent logs a warning and stops. Check the log:

```bash
cat ~/.local/share/dotfiles/logs/dotfiles-sync.log | tail -20
```

### Resolving conflicts

```bash
cd ~/apps/dotfiles

# See what's conflicted
git status

# Fix conflicts in your editor
$EDITOR <conflicted-file>

# Mark resolved and continue
git add <conflicted-file>
git rebase --continue

# Verify and push
dotfiles doctor --fix
git push
```

### If rebase is stuck

The sync agent detects stuck rebases and aborts them automatically. If you need to do it manually:

```bash
cd ~/apps/dotfiles
git rebase --abort
git pull --rebase
```

### Preventing conflicts

- **Edit on one machine at a time** — make changes, wait for sync, then edit on the other
- **Use `.zshrc.local`** for machine-specific config instead of editing tracked files
- **Commit frequently** — smaller commits merge more cleanly

---

## Multiple Remotes

You can push to multiple git remotes (e.g., GitHub.com and GitHub Enterprise):

```bash
cd ~/apps/dotfiles
git remote add ghe git@<your-ghe-host>:<org>/dotfiles.git
```

The sync agent automatically discovers all remotes and pushes to each one. It pulls from `origin` by default.

---

## Monitoring Sync Status

### Check last sync

```bash
tail -5 ~/.local/share/dotfiles/logs/dotfiles-sync.log
```

### Verify LaunchAgent is running

```bash
launchctl list | grep dotfiles-sync
```

### Manual sync

```bash
dotfiles sync              # commit + push + pull
dotfiles sync --dry-run    # preview what would happen
```

### Sync frequency

The LaunchAgent runs every 30 minutes (`StartInterval: 1800`). To change the interval, edit `launchagents/com.dotfiles.dotfiles-sync.plist.tmpl` and run `dotfiles apply`.

---

## Protected Files

Some files are excluded from auto-sync to prevent accidental commits. List them in `.sync-protect`:

```bash
cat ~/apps/dotfiles/.sync-protect
```

Protected files require manual `git add && git commit` to sync. This is useful for files that need careful review before sharing across machines (e.g., `TASKS.md`).

---

## Troubleshooting

### Changes not appearing on the other machine

1. Check sync is running: `launchctl list | grep dotfiles-sync`
2. Check for errors: `tail -20 ~/.local/share/dotfiles/logs/dotfiles-sync.log`
3. Try manual sync: `dotfiles sync`
4. If offline, sync resumes automatically when network returns

### Sync keeps failing

Most common cause: stuck rebase from a conflict.

```bash
cd ~/apps/dotfiles
git status                # look for "rebase in progress"
git rebase --abort        # clear it
dotfiles sync             # retry
```

### Different Homebrew packages per machine

Brew packages are managed by chezmoi lifecycle scripts. Both machines get the same packages for their profile (`core` or `full`). To install something on only one machine, use `brew install <package>` directly — it won't be tracked in the dotfiles.

### Age encryption on multiple machines

If you use age encryption, each machine needs the same age key:

```bash
# On the first machine, copy your key
cat ~/.config/chezmoi/key.txt
# On the second machine, paste it
mkdir -p ~/.config/chezmoi
# Paste key content into key.txt
chmod 600 ~/.config/chezmoi/key.txt
```

The age key is never tracked in git. Transfer it securely (e.g., AirDrop, encrypted message, or password manager).

---

## Further Reading

- [Onboarding guide](onboarding.md) — full setup walkthrough
- [Key rotation](key-rotation.md) — rotating age and SSH keys
- [Troubleshooting](troubleshooting.md) — symptom-first fixes
- [Security model](security-model.md) — how secrets and encryption work
