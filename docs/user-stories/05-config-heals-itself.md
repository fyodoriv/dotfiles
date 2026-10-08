# User Story: Config Heals Itself Automatically

> After setup, config stays in sync and self-heals — no manual maintenance needed.

## Three Layers of Automation

### 1. Auto-sync (every 30 minutes)

The `dotfiles-sync` LaunchAgent pulls remote changes, commits local modifications, and pushes to all remotes:

```bash
dotfiles sync    # manual trigger (same as what the LaunchAgent does)
```

**Safety:** auto-sync never commits file deletions. If it detects staged deletions, it unstages them and warns — deletions require a manual commit.

### 2. Auto-doctor (weekly)

The `dotfiles-doctor` LaunchAgent runs `dotfiles doctor --fix` weekly, silently repairing any drift. Chrome Work-profile + default-browser drift is also healed hourly by `com.dotfiles.chrome-profile` (`bin/chrome-heal`) so Slack/Outlook links keep routing through ChromeWork without waiting for Monday.

Modules check shell, git, macOS defaults, SSH, CLI tools, editors, terminals, browsers, AI tooling, security, enterprise config, and sync/upgrade infrastructure.

On managed endpoints where policy blocks the Node.js Foundation publisher,
self-healing enters a bounded safe mode: all Node-backed `com.agentbrew.*`
jobs and weekly Topgrade are unloaded, apply-time agentbrew sync is skipped,
and Node/Python publisher-dependent doctor modules remain off until their
machine-scoped exceptions are approved. Shell/macOS/security healing continues
without those runtimes.

| Severity | Modules | Meaning |
|----------|---------|---------|
| 🚨 Critical | security, ssh, workflow | Security and safety |
| ⚙️ Important | agent-browser, agentbrew, chezmoi, chrome, editor, git, local-bin, memory, personal-machine, resilience, shell, sync, upgrade | Core developer config |
| ⚡ Performance | macos, tools | System performance |
| 💅 Cosmetic | claude, cursor, enterprise, extras, jetbrains, local-ai, local-llm, minsky, obsidian, prompt, terminal, vscode, workspace | Personal preference |

### 3. Safe updates from upstream

Per-machine overrides live outside the repo (`~/.config/chezmoi/chezmoi.yaml`, `~/.gitconfig.local`, `~/.zshrc.local`), so `git pull` never conflicts with them. New packages, defaults, and checks from the maintainer apply automatically on the next sync cycle.

## Manual Commands (if needed)

```bash
dotfiles doctor              # audit all modules
dotfiles doctor --fix        # auto-repair everything fixable
dotfiles doctor --skip ID    # permanently skip a check
dotfiles doctor --list       # show all check IDs
dotfiles apply               # re-deploy config
dotfiles diff                # preview pending changes
dotfiles sync                # pull + commit + push
dotfiles update              # pull latest + re-apply
```

## Files Involved

| File | Purpose |
|------|---------|
| `bin/dotfiles-sync` | Auto-sync script (commit + push + pull, never commits deletions) |
| `bin/dotfiles-doctor` | Self-healing config audit |
| `modules/*/doctor.sh` | Per-module health checks (auto-discovered) |
| `.sync-protect` | Files protected from auto-sync commits |
| `launchagents/com.dotfiles.dotfiles-sync.plist.tmpl` | Sync LaunchAgent |
| `launchagents/com.dotfiles.dotfiles-doctor.plist.tmpl` | Doctor LaunchAgent |
