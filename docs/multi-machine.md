# Multi-Machine Synchronization

Guide for using these dotfiles across multiple machines — common for engineers with a work machine and a personal machine, or teams sharing a fork.

## How Sync Works

The `dotfiles-sync` LaunchAgent runs every 30 minutes on each machine:

1. **Pull** remote changes with `git pull --rebase --autostash`
2. **Apply** config via `chezmoi apply` (deploys any remote changes). The apply runs only when the pull brought new commits, the record of the last successful apply does not match (a failed apply, uncommitted source changes, or a new chezmoi config or plugin lock), or `chezmoi status` shows drift (a hand-edited or missing file). Otherwise the run costs one `chezmoi status`, about 1 s, and logs `skipped chezmoi apply`. `dotfiles apply` always runs the full apply.
3. **Commit** local changes (additions and modifications — never deletions)
4. **Push** to all configured remotes

This means changes made on Machine A appear on Machine B within ~30 minutes, without manual intervention. Deletions are excluded from auto-sync as a safety measure and require manual commits.

When chezmoi's source is a separate applied checkout (a linked worktree on its own branch that tracks the canonical branch), sync only fast-forwards that checkout and re-runs `chezmoi apply` under the same rule. It never commits or pushes from it, and it leaves the checkout untouched when it has local changes or has diverged.

An apply never unloads the `dotfiles-sync` LaunchAgent while a sync runs, because unloading kills the run. This covers the sync's own `chezmoi apply` and a manual `chezmoi apply` that starts while launchd runs a sync (the sync holds `~/.dotfiles.lock`). The apply writes a marker in `~/.local/state/dotfiles/pending-reload/`, and the sync reloads the agent once after it ends.

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

## Personal Agent Files

dotfiles moves shell and git config, and agentbrew rebuilds the shared agent
config from its sources (`agentbrew sync`). Neither moves the files you wrote
for your own agent: memory, personal skills, and hand-edited rules or
settings. Keep those in a **private** git repo of their own.

| Part | In the private repo? |
|---|---|
| Memory, personal skills, personal rules and settings | yes |
| Files agentbrew generates (synced skills, deployed rules, MCP config) | no: `agentbrew sync` rebuilds them |
| Secrets (OAuth client files, MCP URLs with keys, API tokens) | never: keep them in your password manager |
| Logins, tokens, sessions, caches, transcripts | no: log in again on each Mac |

### Back up

1. Use an allow-list `.gitignore` in the agent folder (`*` first, then `!`
   lines for the folders you keep), so a new cache never lands in git.
2. Before each commit, scan the staged files for secrets and stop on a hit
   (for example a refresh token, an OAuth client secret, or a key in a URL).
   Use `gitleaks protect --staged --redact`, so it prints file names only,
   never the matched value.
3. Commit with a conventional message. The `commit-msg` hook (installed
   globally by dotfiles) rejects others. Push only to a private remote. Check with
   `gh repo view <repo> --json visibility`.

### Restore on a new Mac

1. Install dotfiles (see [onboarding.md](onboarding.md)), then agentbrew
   (`agentbrew sync`).
2. Clone the private repo into the agent folder.
3. Put the secret files back from your password manager.
4. Re-register each MCP server or connector and log in to each account.
5. Run `dotfiles doctor` and `agentbrew status`, then start a session and
   confirm that the memory and personal skills load.

### Share with another person

Share skills, never memory or secrets. Package the skills as an agent plugin
or a skill source repo they add with agentbrew. Each person logs in with
their own accounts, so actions show under their name.

## Further Reading

- [Onboarding guide](onboarding.md) — full setup walkthrough
- [Key rotation](key-rotation.md) — rotating age and SSH keys
- [Troubleshooting](troubleshooting.md) — symptom-first fixes
- [Security model](security-model.md) — how secrets and encryption work
