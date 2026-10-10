# Machine updates (Phase 4)

Invoking `/tooling-checkup` is the user's explicit request to upgrade
third-party software. The `update-tooling` ban on package upgrades does not
apply inside this skill. All other `update-tooling` rules still apply.

## 1. Skip check (fast path)

Skip the upgrade run when both are true:

- `~/.local/share/dotfiles/last-upgrade` is less than 12 hours old.
- `brew outdated --greedy --quiet` prints nothing.

Report the skip with both facts. Still do steps 3 and 4.

## 2. Upgrade everything Topgrade knows

Run the dotfiles wrapper from the applied checkout. It takes the dotfiles lock,
runs Topgrade with the dotfiles config (Homebrew formulae and greedy casks,
npm and pnpm globals, uv and pipx tools, mise, gh extensions, App Store), and
re-signs new bottles.

```bash
DOTFILES_APPLIED="$(chezmoi source-path)"
env -u DOTFILES_DIR "$DOTFILES_APPLIED/bin/dotfiles-upgrade"
```

It can take 5 to 20 minutes. Run it in the background and keep working on
Phases 5 to 7. Its log is `~/.local/share/dotfiles/logs/dotfiles-upgrade.log`.

The wrapper exits early in endpoint Node safe mode
(`~/.local/state/dotfiles/endpoint-node-publisher-blocked`). Report that as
"skipped: safe mode". Do not set the opt-in variable yourself.

## 3. Claude Code

Topgrade skips Claude Code on purpose. Update it here:

```bash
claude --version                      # before
claude update
claude --version                      # after; must match the version `claude update` names
python3 <skill-dir>/scripts/pty_capture.py --timeout 60 -- claude doctor
```

`claude doctor` prints nothing without a terminal, so use `pty_capture.py`.
Report every line that is not OK. Examples: `Last update attempt: failed`,
a second installation, a wrong install method, or "issues found".

A running session keeps its old binary. The new version starts in new sessions.

## 4. Verify (report only)

```bash
brew outdated --greedy
npm outdated -g --depth=0
pnpm outdated -g 2>/dev/null
uv tool list --outdated 2>/dev/null
pipx list --short
command -v mise >/dev/null && mise outdated
softwareupdate --list 2>&1 | head -20   # never install macOS updates from here
env -u DOTFILES_DIR "$DOTFILES_APPLIED/bin/dotfiles" doctor
```

Topgrade's exit code hides partial success. Read the log tail and the doctor
result. Do not trust the exit code alone.

## Known environment failures

These come back often. They are machine state, not code bugs.

| Symptom | Fix |
|---|---|
| oh-my-zsh step fails on a case-only file rename | `git -C ~/.oh-my-zsh config core.ignorecase true`, then run again |
| `pnpm update -g` fails with "no global packages" | Harmless. Report it. |
| Poetry launcher fails in a path with spaces | Harmless for this machine. Report it. |
| A cask fails because its app is missing | Ask the user: reinstall or `brew uninstall --cask <name>` |
| `dotfiles update` or apply fails on a missing `ggrep` | `brew install grep` |
| A bottle is blocked by an endpoint agent | `dotfiles-adhoc-sign-bottles` (Topgrade runs it after upgrades) |

A new failure that recurs belongs in a `TASKS.md` task in dotfiles, with the
log lines as evidence.
