# Plan: keepawake-desktop-and-scheduled-jobs

## Goal

The keepawake manager tracks Claude desktop app sessions, not only the Claude
Code CLI. `dotfiles-resilience-setup` says whether closing the lid sleeps the
Mac and how to change it.

## Why

- A Mac used mainly through the Claude desktop app lost two nightly
  LaunchAgent runs on lid close (user report, 2026-10-21).
- The desktop app runs Claude Code from
  `~/Library/Application Support/Claude/claude-code/<version>/<hash>/claude.app/Contents/MacOS/claude`.
  `dotfiles_agent_claude_paths` knew only `~/.local/bin/claude` and `claude`
  on `PATH`, so `--dry-run` did not list these sessions.
- `pmset sleep 0` does not stop lid-close sleep, and the setup wizard did not
  say so.

## Scope (in)

- `lib/agent-keepawake.sh`: match desktop sessions by path shape
  (`claude-code/<one segment>/<one segment>/claude.app/Contents/MacOS/claude`),
  so a new app version needs no change. The `disclaimer` wrapper process is
  not tracked; its child is.
- LaunchAgent gate and the two resilience doctor checks also accept the
  desktop app's `claude-code` folder, so a desktop-only Mac gets the manager.
- `dotfiles-resilience-setup --lid-close`: a read-only report. It reads
  `pmset -g` (`SleepDisabled`), the manager's Amphetamine owner marker, and
  enabled user LaunchAgents with `StartCalendarInterval`. It names both fixes.

## Scope (out)

- Keeping the Mac awake for scheduled jobs. Only an Amphetamine session or
  `pmset disablesleep 1` stops lid-close sleep; `caffeinate` cannot. Holding
  a session "while a job is due in N hours" means all night on a Mac with a
  23:30 and a 06:00 job: the same cost as the manual fix, but hidden. launchd
  already runs a missed calendar job at the next wake. The report lists the
  affected jobs and the two manual fixes instead.
- Never runs `sudo` or changes `pmset`.

## Verification

- `bats tests/agent-keepawake.bats tests/resilience-setup.bats tests/module-resilience.bats`
  (fake `ps` snapshots and stub `pmset`; no real processes).
- On a Mac with a desktop session: `dotfiles-agent-keepawake --dry-run` lists
  a `.../claude-code/<version>/<hash>/claude.app/Contents/MacOS/claude` PID.
