# Install dotfiles (and agentbrew) with your AI agent

This file is a playbook for an AI coding agent (Claude Code, Cursor, Codex).
A person starts it with one sentence:

> Install dotfiles by following https://github.com/fyodoriv/dotfiles/blob/feat/chezmoi/INSTALL.md

It sets up the Mac (shell, git, Homebrew packages, macOS settings, health
checks) and then agentbrew (skills, rules, and MCP servers for AI agents).

Agent: follow the steps below in order. Do not skip the plan or the
questions. Use your structured question tool (`AskUserQuestion` in Claude
Code) when you have one. Give every question its full context: what the
choice is, what each option does, and what changes for the person.

## 1. Choose where the code goes

Ask: "Where should I put the dotfiles code? It is a git clone; your config
links point into it, so keep it in place. agentbrew goes next to it."
Options:

- `~/apps/dotfiles` (recommended; the default the config expects)
- `~/code/dotfiles`
- `~/dotfiles`
- Another folder (let the person type a path)

Then clone it (or update an existing clone):

```bash
git clone https://github.com/fyodoriv/dotfiles.git <DIR>   # or: git -C <DIR> pull --ff-only
```

## 2. Explain the plan

```bash
bash <DIR>/bin/dotfiles-install plan
```

Show the person, in your own short words:

- what they need: Xcode Command Line Tools, Homebrew, git, Homebrew jq
  (not `/usr/bin/jq`), chezmoi; 10-20 minutes (core) or 30-60 (full); their
  Mac password once or twice; power and network. A line with `→ … will be
  installed` is a tool that `run` installs with Homebrew; `plan` installs
  nothing,
- their Mac today, from the "Your Mac today" lines: zsh start median, free
  disk, LaunchAgents, and the disk the chosen profile will use. `run` saves
  the same numbers before it changes anything, in an install receipt
  (`~/.local/state/dotfiles/install-receipt.json`, with the time to
  configured); later, `dotfiles metrics --gains` prints before vs now,
- what will change: shell and git config, Homebrew packages, macOS settings,
  background jobs, then agentbrew,
- that a backup is made first: config files, LaunchAgents, the chezmoi
  config, and every macOS settings domain the install may touch,
- that a critical error restores the backup by itself and removes the files
  and folders the install created, but Homebrew packages stay installed, and
  caches and tools the install scripts made stay too (restore lists them),
- how to undo later: `bash <DIR>/bin/dotfiles-install restore`.

If a prerequisite is missing, help install it first. Homebrew and the Xcode
tools ask for the person's password or show a dialog: tell them, and let
them type it. Then show the plan again.

## 3. Ask for preferences

Ask these together, in one round:

1. "Which profile? **core** sets up the essentials: shell, git, the main
   developer tools, and safe macOS settings. **full** adds visual and app
   preferences, more apps, and more background jobs." core (recommended) /
   full.
2. "What name and email should your git commits use?" (free text; suggest
   the values from `git config --global user.name` / `user.email` if set).
3. "May I change macOS system settings (Finder, Dock, keyboard, screenshots,
   and similar)? They are backed up first and can be restored." Yes
   (recommended) / No, keep my settings.
4. "Also install agentbrew? It gives your AI agents a shared set of skills,
   rules, and MCP servers, and keeps them in sync." Yes (recommended) / No.
   If yes, also ask agentbrew's three questions from
   https://github.com/fyodoriv/agentbrew/blob/main/INSTALL.md step 3
   (recommended set, background repair job, shell hook).

Map the answers to flags: `--profile core|full`, `--name "<name>"`,
`--email "<email>"`, `--no-macos-defaults`, `--no-agentbrew`, and
`--agentbrew-flags "<agentbrew flags>"` (for example `"--no-auto-repair"`).

## 4. Install

Get a clear yes to the plan, then run it in a terminal the person can see
(Homebrew may ask for the password):

```bash
bash <DIR>/bin/dotfiles-install run --yes --profile core --name "..." --email "..." [more flags]
```

The script backs up, runs `chezmoi apply`, heals with `dotfiles doctor
--fix`, verifies with `chezmoi verify` and a clean zsh start, and then runs
agentbrew's installer. On a critical error it restores the backup by itself
and exits 1. Then tell the person what failed and that their setup is back,
show them any paths the restore listed as kept, and offer to open an issue
with the output.

## 5. Finish

Tell the person:

- open a new terminal to load the new shell,
- where the backup is and how to undo (`dotfiles-install restore`),
- `dotfiles doctor` checks health; `dotfiles metrics` shows how the tools
  behave on their Mac,
- if anything in the install was wrong or confusing, they can fix it and
  send it upstream from their own fork. Offer to do it with them: create a
  branch, make the fix, add or update a test (`tests/*.bats`) and the docs,
  run `make check`, then `dotfiles contribute` (it forks the repo and opens
  the PR; `--repo agentbrew` does the same for agentbrew).
  `dotfiles metrics --share metrics.md` is a privacy-safe snapshot to attach.
