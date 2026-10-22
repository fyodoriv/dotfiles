# Plan: one command starts dotfiles

- **Task**: one-command-start
- **Status**: implemented 2026-10-22

## Goal

The owner's rule "One command to start any app": `dotfiles` with no
arguments (and `/dotfiles` in an agent) sets up what is missing, refreshes,
and prints what matters now and the next step. Settings have one table and a
`config` command that people and agents share.

## Design

- `bin/dotfiles-start` (the no-argument path of `bin/dotfiles`) prints one
  line each for set up, applied, background jobs, health, and updates, then a
  numbered "Needs you" list and a `Next:` line.
  - **Applied** reuses `lib/apply-state.sh`, the same test as
    `dotfiles apply --if-changed`: `chezmoi status` drift, or a source,
    config, or plugin change since the last full apply. With no record and no
    drift (right after an install) it says the files match and asks nothing.
  - **Health** reads the last doctor run from `~/.dotfiles-stats.jsonl`. A
    fresh `dotfiles-doctor --quiet` took 97 s on this Mac at load 90, so it
    runs only with `--health`.
  - **Background jobs** compares `~/Library/LaunchAgents/com.dotfiles.*.plist`
    with `launchctl list`. It never loads one: some start Chrome or a local
    model. It names `dotfiles-reload-launchagents` instead (the task's pivot:
    print the exact next step).
  - **Update** reads the last fetch and starts at most one background fetch
    an hour, like the update check of the other commands.
  - It applies (`dotfiles apply --if-changed`) or installs
    (`dotfiles install run --yes`) only with a yes: `y` at a terminal prompt,
    or `--yes`. Agents get no prompt. From a worktree it reports the applied
    checkout and never applies.
- `bin/dotfiles-config` reads `config/settings.yaml` (type, default,
  description; same shape as `config/plugin-options.yaml`) and the values
  under `data:` in `~/.config/chezmoi/chezmoi.yaml`. `config set` checks the
  value, then writes it with `yq` (values pass through `strenv`, never the
  expression) to a copy with the same mode and swaps it in under
  `~/.dotfiles.lock`. It never applies. Bash 3.2 safe (no associative arrays).
- `tests/dotfiles-config.bats` renders `.chezmoi.yaml.tmpl` for a new user and
  fails when a key or a default differs from the table, and when README
  "Configuration" misses a key.
- `commands/dotfiles.md` is the agent command; `Agentfile.yaml` already
  declares `commands: [./commands]`.

## Measurement

The task's e2e is `tests/dotfiles-start.bats` "fresh clone e2e": a clone in a
scratch HOME, then only `bin/dotfiles`.

- Baseline 2026-10-22: `dotfiles` printed the help, so a fresh clone showed no
  state. Seeing the state took a remembered sequence (`dotfiles status`,
  `chezmoi status`, `dotfiles doctor --quiet`, `launchctl list | grep
  com.dotfiles`), and changing a setting meant a hand edit (`dotfiles config`
  was "Unknown command").
- Success: 1 command shows the first useful screen, and `dotfiles config set`
  round-trips one setting.
- Pivot: a part that cannot start safely by default prints the exact next
  step instead (LaunchAgents, the doctor run).
