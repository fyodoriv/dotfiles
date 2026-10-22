---
description: Start dotfiles on this Mac (what is missing, what changed, what needs you) and walk the user through it
allowed-tools: Bash(dotfiles:*)
---

Run `dotfiles` with no arguments. If `dotfiles` is not on PATH, run `bin/dotfiles` from the dotfiles checkout (`chezmoi source-path` prints it; a new Mac uses `~/apps/dotfiles`). It is safe and fast: no sudo, and it applies or installs nothing without a yes. It prints one line each for set up, applied, background jobs, health, and updates, then a numbered "Needs you" list and a `Next:` line.

Then, answer first:

1. One line: is dotfiles up to date on this Mac? Use the ✓, !, ✗, and ? lines.
2. Each "Needs you" item: say in plain words what the command does and what changes for the user. Run it only after the user says yes:
   - `dotfiles apply --if-changed`: applies the waiting changes; it can take minutes, and macOS may show permission prompts.
   - `dotfiles install run --yes`: installs on a new Mac; it backs up first. Show `dotfiles install plan` before you ask.
   - `dotfiles update`: pulls, applies, updates agents and packages, then runs the doctor.
   - `dotfiles doctor --fix`: repairs the failing health checks.
   - `dotfiles-reload-launchagents`: reloads the background jobs; some of them start Chrome or a local model.
3. A step that needs sudo or a password: give the user the exact command to run in their own terminal. Never run sudo.

For a fresh health check, run `dotfiles --health` (1 to 2 minutes).

To change a setting the user asks for, run `dotfiles config` (every setting, its value, its source, and the allowed values) or `dotfiles config <key>` (what one setting does). Then run `dotfiles config set <key> <value>`: it checks the value and saves it. Apply it with `dotfiles apply --if-changed` after the user says yes. Never hand-edit `~/.config/chezmoi/chezmoi.yaml` or generated agent config under `~/.claude/`.

Every other command: `dotfiles --help`.

If dotfiles fails, surprises you, or could clearly work better, offer once to report it (CONTRIBUTING.md "Report problems and ideas"). Show the user the exact text, and post only after they say yes.
