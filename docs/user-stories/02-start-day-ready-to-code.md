# User Story: Start the Day Ready to Code

> Everything is already pulled, healthy, and visible — one command or fully automatic.

## How It Works

```bash
morning
```

Runs these steps in sequence:

1. **Pull latest on all repos** — `git pull --rebase` on every repo in `~/apps/` on `main`/`master`
2. **Health check** — `dotfiles doctor` (report only, no fixes)
3. **Today's notes** — shows today's entries from `~/.notes/` (written via `note` command)
4. **Calendar** — today's meetings via `icalBuddy` (or just the date)
5. **Disk space** — warns if below 20GB free
6. **Pending macOS / Xcode updates** — non-blocking `softwareupdate -l` check, warns if updates are queued
7. **Top resource usage** — top 3 CPU consumers
8. **Time saved summary** — how much dotfiles automation has saved

Also runs automatically via `com.dotfiles.morning` LaunchAgent at 8:30 AM.

## Example Output

```
☀ Good morning! Setting up your dev environment...

→ Pulling latest code...
  ✓ dotfiles
  ✓ agentbrew
  ✓ minsky

→ Health check...
  N passed, 0 failed, N skipped

→ Schedule:
  Monday, March 15, 2026

  ✓ Disk: 142GB free
  ✓ macOS: up to date

→ Top resource usage:
  PID  %CPU %MEM COMMAND
  412  12.3  4.2 /Applications/Cursor.app
  891   8.1  2.1 node

  ⏱  Dotfiles: ~4h 23m saved across 847 runs (12 day streak)

Ready to code! 🚀
```

## What Runs in the Background

Even without running `morning`, managed LaunchAgents keep things healthy:

| LaunchAgent | What | Frequency |
|-------------|------|-----------|
| `dotfiles-sync` | Git commit + push + pull (never commits deletions) | Every 30 min |
| `tooling-sync` | Pull agentbrew and minsky; push agentbrew TASKS.md edits | Every hour |
| `dotfiles-doctor` | Health check + auto-fix | Weekly |
| `git-maintain` | `git maintenance` on all repos | Daily |
| `cursor-priority` | Every 60s | Boost Cursor/Windsurf scheduling priority | Every 60s |
| `cursor-at-login` | Launch Cursor in background at login (`open -g -a Cursor`) | At login |
| `morning` | Morning startup routine | 8:30 AM daily |
| `capslock-control` | Caps Lock → Control remapping | At login |
| `gui-path` | Sync shell PATH to GUI apps | At login |
| `pmset-drift-watch` | Log who changed power settings (read-only) | On power-plist write + every 5 min |
| `rancher-desktop` | Start Rancher Desktop; wait until the Docker API answers | At login |
| `network-resilience` | Network watchdog for marathon sessions | Every 5 min + after wake |
| `sleepwatcher` | Run hooks on sleep/wake events | At login |
| `agent-browser-chrome` | Dashboard / SSO Chrome CDP for browser automation; manual close respected | At login, not kept alive |
| `debug-chrome` | Debug-work Chrome CDP for browser automation; manual close respected | At login, not kept alive |
| `tooling-chrome` | Tooling-repo Chrome CDP for browser automation; manual close respected | At login, not kept alive |
| `chrome-profile` | Heal Chrome Work profile + reassert ChromeWork as default browser (Slack/Outlook links) | At login + every 1 hour |
| `chrome-debug` | Chrome with Work profile + debug port | On-demand |
| `atuin-daemon` | Atuin shell history sync daemon | At login |
| `ollama` | Start Ollama LLM server (kept alive, restarts on crash) | At login |
| `opencode-serve` | Run OpenCode IDE server on localhost:4096 | At login |
| `endpoint-bootstrap` | Sign uv Pythons and core tools, link shims, and publish the ready sentinel before other agents start | At login |
| `agent-keepawake` | Keep the Mac awake while Cursor or Claude Code runs on AC or battery ≥20%; release protection when both exit | At login + every 5s |
| `heal-stuck-agents` | Clear hung git SSH sessions, stale sandbox shells, and runaway helpers that stall Cursor agents | At login + every 30s |
| `dotfiles-upgrade` | Upgrade all installed software through topgrade (opt-in: `auto_upgrade: true`) | Sundays 9:00 AM |
| `memory-sync-projects` | Ingest Claude project memory into AgentBrew shared memory | 5:30 AM daily |
| `adhoc-sign-bottles` | Ad-hoc sign Homebrew bottles and uv Pythons so endpoint security does not flag unsigned binaries | At login + daily |
| `local-ai-warmup` | GET-only local-AI health check (never spawns model publishers) | At login + every 30 min |

## Files Involved

| File | Purpose |
|------|---------|
| `bin/morning` | Morning startup script |
| `lib/colors.sh` | Shared colors and time-tracking helpers |
| `launchagents/com.dotfiles.morning.plist.tmpl` | LaunchAgent template |
