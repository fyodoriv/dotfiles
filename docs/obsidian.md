# Obsidian + Claude Code

Recommended Obsidian terminal plugin for running Claude Code inside a vault:
**[Lean Terminal](https://github.com/sdkasper/lean-obsidian-terminal)** by
sdkasper. This doc explains the choice, links to the install steps, and pins
the configuration that matches how Claude Code expects to be launched.

Use this guide when adding Claude Code support to a teammate's Obsidian
vault, or when troubleshooting why an existing terminal plugin behaves
strangely with Claude Code.

## Why Lean Terminal

There are three actively-maintained Obsidian terminal plugins:

| Plugin | Stars | Picks for Claude Code |
|---|---|---|
| [polyipseity/obsidian-terminal](https://github.com/polyipseity/obsidian-terminal) | 809 | Two open bugs specifically break Claude Code — see below |
| [sdkasper/lean-obsidian-terminal](https://github.com/sdkasper/lean-obsidian-terminal) | 90 | **Built with Claude Code in mind** — recommended |
| [ZyphrZero/Termy](https://github.com/ZyphrZero/Termy) | 37 | Command runner, not a full PTY — interactive UI breaks |

### Three reasons to pick Lean Terminal

1. **Built with Claude Code in mind.** Startup command config, a session
   registry that scans `~/.claude/projects/` for active conversations, and
   `Shift+Enter` muscle-memory support match how Claude Code wants to be
   used inside a writing-focused editor.

2. **Avoids two open polyipseity bugs that specifically break Claude Code.**
   - [`polyipseity#70`](https://github.com/polyipseity/obsidian-terminal/issues/70)
     — scroll-to-top during streaming on macOS. Claude Code streams long
     responses; the bug yanks the view away from the assistant's
     in-progress output every time it appends a token.
   - [`polyipseity#142`](https://github.com/polyipseity/obsidian-terminal/issues/142)
     — Windows PTY resizer accidentally invokes `claude.exe --print` on
     startup, which exits before the interactive session can begin. The
     plugin then reports "terminal exited cleanly" even though nothing
     ran.

3. **Full PTY via `node-pty`, not a command runner.** Claude Code's
   interactive UI (keyboard shortcuts, in-place updates, color escape
   codes) needs a real pseudo-TTY. Termy and similar "run a command and
   print the output" plugins can't host an interactive session.

## Install

1. In Obsidian, open **Settings → Community plugins → Browse**.
2. Search for **"Lean Terminal"**.
3. Click **Install**, then **Enable**.

The plugin store entry is `lean-terminal`. If your vault has community
plugins disabled (the default for fresh vaults), enable them under
**Settings → Community plugins → Turn on community plugins** first.

A standalone-install path exists for environments without plugin-store
access — clone `https://github.com/sdkasper/lean-obsidian-terminal` into
`<vault>/.obsidian/plugins/lean-terminal/` and reload Obsidian.

## Configure for Claude Code

Open **Settings → Lean Terminal**:

| Setting | Value | Why |
|---|---|---|
| Startup command | `claude` | Launches Claude Code's default mode in the current vault directory |
| (optional) Startup args | `--project .` | Pins the session to the current Obsidian vault's path |
| Working directory | `${vault}` | The plugin's default — runs Claude Code at the vault root so file references resolve |
| Keybinding for new terminal | `Cmd+J` (macOS) / `Ctrl+J` (Windows/Linux) | Same shortcut as the built-in console; muscle memory |

The plugin reads `claude` from your shell's `PATH`. If `claude` isn't on
`PATH` (e.g. you used `npm install -g @anthropic-ai/claude-code` in a
different shell session), point the Startup command at the absolute path:
`/Users/<you>/.local/bin/claude` or `/opt/homebrew/bin/claude` depending
on how Claude Code was installed.

## Verify

After install + configure:

1. Open the command palette (`Cmd+P` / `Ctrl+P`).
2. Run **Lean Terminal: Open new terminal**.
3. You should see Claude Code's startup banner and a prompt waiting for
   input.

If you see a generic shell prompt instead, the Startup command setting
didn't take — re-check it under **Settings → Lean Terminal → Startup
command**.

If the terminal opens and closes immediately, you've likely hit the same
class of bug `polyipseity#142` documents — the plugin invoked Claude Code
in non-interactive mode. Lean Terminal v1.1.1+ should not have this
issue; if you do, file an issue against `sdkasper/lean-obsidian-terminal`
with the Claude Code version and your platform.

## Why this doc lives in dotfiles

Lean Terminal is configured by editing the Obsidian vault's per-plugin
settings, which dotfiles doesn't manage (vault data lives outside the
home-directory chezmoi scope). This doc captures the *choice* — which
plugin to pick and how to configure it — so every contributor who needs
Claude Code inside Obsidian arrives at the same setup without
re-evaluating the three plugins from scratch.

## Verified

| Platform | Lean Terminal version | Claude Code version | Date |
|---|---|---|---|
| macOS arm64 (Apple Silicon) | v1.1.1 | (current) | 2026-05-18 |

Add a row when you confirm a new platform / version combination works.
