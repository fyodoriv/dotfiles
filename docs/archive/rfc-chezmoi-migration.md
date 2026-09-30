# RFC: Simplify Dotfiles with Chezmoi

**Status:** Implemented (merged to main 2026-03-12, PR #1)
**Author:** @cbrwizard
**Date:** 2026-03-12

---

## 1. Problem Statement

The dotfiles repo has grown to **~5,900 lines of custom bash** (excluding tests) across 40+ files. What started as symlink helpers now includes a bespoke framework:

| Component | Files | Lines | Purpose |
|-----------|-------|-------|---------|
| `install.sh` | 1 | 946 | Interactive picker, profiles, Homebrew, secrets, snapshots, locking |
| `lib/utils.sh` | 1 | 272 | `link_file()`, backup rotation, archive vault, colors, time-tracking |
| `snapshot.sh` | 1 | 262 | macOS defaults capture, brew list, symlink state, pruning |
| `revert.sh` | 1 | 453 | Snapshot diffing, interactive picker, selective revert, safety snapshots |
| `bootstrap.sh` | 1 | 150 | Fresh Mac one-command setup |
| `macos*.sh` | 3 | 372 | 80+ `defaults write` commands |
| `bin/` scripts | 22 | 2,832 | doctor, sync, stats, cleanup, morning, mcp-sync, CLI wrapper, etc. |
| `modules/*/install.sh` | 15 | 374 | Per-module install logic |
| `modules/*/doctor.sh` | 15 | 256 | Per-module health checks |
| `tests/` | 8 | 1,188 | bats test suite for install, link_file, snapshot, revert, doctor |

The framework layer — install, symlink management, backup, snapshot, revert, locking, dry-run — accounts for **~2,200 lines**. This is the layer that mature tools already handle. The remaining ~3,700 lines (bin scripts, macos defaults, doctor checks) are genuinely unique and stay regardless.

**The core tension:** Every new capability (templating, machine-specific configs, secrets encryption, cross-machine sync) means writing more custom bash, more tests, more edge-case handling. We're maintaining a dotfiles *engine* when we could be maintaining just dotfiles *content*.

---

## 2. Alternatives

### 2a. Chezmoi — recommended

Single Go binary, no dependencies. 13k+ GitHub stars, 500+ contributors, actively maintained.

**Key capabilities that replace our custom code:**

- **File management:** Tracks desired state in a source directory, applies with `chezmoi apply`. Handles creates, updates, deletes, permissions. Replaces `link_file()`, backup rotation, archive vault.
- **Dry-run & diff:** `chezmoi diff` shows exact changes before apply. `chezmoi apply --dry-run` simulates. Replaces our `DRY_RUN=true` plumbing across every script.
- **Templates:** Go `text/template` with machine data (hostname, OS, arch, custom variables). Replaces `~/.dotfiles-machine.sh` and per-machine file variants.
- **Scripts:** `run_once_`, `run_onchange_`, `run_after_` scripts execute at the right time. Replaces module `install.sh` orchestration.
- **Secrets:** Native integration with 1Password, Bitwarden, age, gpg, Keychain. Replaces manual `do_secrets()` + Keychain prompts.
- **Bootstrap:** `chezmoi init --apply your-org/dotfiles` on a fresh machine. One command, no clone needed. Replaces 150-line `bootstrap.sh`.
- **External sources:** `.chezmoiexternal.yaml` can pull files from other repos. Replaces manual cross-repo symlinks.

### 2b. GNU Stow

Symlink farm manager. Dead simple but only solves `link_file()` (~150 lines of our code). No templating, no secrets, no scripts, no dry-run diff. We'd keep 95% of our custom bash.

**Verdict:** Too narrow. Doesn't reduce enough code to justify migration.

### 2c. yadm

Git-native dotfiles manager with Jinja2 templates and GPG encryption. Less active than chezmoi (fewer contributors, slower release cadence). No `run_once`/`run_onchange` scripts. Weaker templating engine.

**Verdict:** Viable. Chezmoi is strictly more capable for our use case.

### 2d. Nix + home-manager

Fully declarative and reproducible. But: steep Nix language learning curve, heavy package manager dependency, poor macOS `defaults write` story, slow rebuilds. Replaces bash complexity with Nix complexity.

**Verdict:** Right tool for NixOS power users. Overkill for a focused macOS dotfiles setup.

### 2e. Do nothing

Honest assessment: **the current system works.** It's a single-user macOS repo, the code is tested, shellchecked, and stable. The question is whether the ongoing maintenance cost justifies migration effort.

Arguments for status quo:
- No migration risk or learning curve
- Full control over every behavior
- Interactive module picker is genuinely nice UX
- Symlink-based approach means edits to `~/.zshrc` instantly reflect in the repo

Arguments against:
- Every new feature requires custom bash + tests + docs
- No templating — machine-specific configs require manual `~/.dotfiles-machine.sh` hacks
- No secrets encryption — manual Keychain prompts
- 1,188 lines of tests just for infrastructure code, not for actual configs
- Bus factor: custom framework is harder for others (or future-you) to pick up than a standard tool

---

## 3. Symlinks vs Copies

This is the biggest behavioral change and deserves dedicated analysis.

### Current: symlinks everywhere

```
~/.gitconfig → ~/apps/dotfiles/home/gitconfig
~/.zshrc     → ~/apps/dotfiles/home/zshrc
```

**Pros of symlinks:**
- Edit `~/.zshrc` directly → change is immediately in the repo, `git diff` shows it
- No "sync" step between live config and repo
- `dotfiles-doctor` verifies links by checking `readlink` targets
- AI agents (Cascade, Claude Code) can edit `~/.zshrc` and changes persist in git

**Cons of symlinks:**
- Any tool that replaces (write-new + rename) instead of editing in-place breaks the link
- Backup/restore is complex (our `link_file()` needs 150 lines of backup rotation)
- Can't template — the file IS the repo file, no rendering step

### Chezmoi default: copies

```
~/.gitconfig ← copied from <chezmoi-source>/dot_gitconfig
~/.zshrc     ← copied from <chezmoi-source>/dot_zshrc
```

**Pros of copies:**
- Templating works (render Go templates → write output)
- No broken symlinks from tools that replace files
- Simpler mental model: source of truth is always the chezmoi source dir

**Cons of copies:**
- Editing `~/.zshrc` directly doesn't update the repo — you must use `chezmoi edit ~/.zshrc` or `chezmoi re-add`
- **Agent workflow impact:** AI agents editing `~/.zshrc` would modify the copy, not the source. Changes would be overwritten on next `chezmoi apply` unless re-added.

### Chezmoi symlink mode: best of both

Chezmoi supports symlinks via `symlink_` prefix on source files:

```
# In chezmoi source directory:
symlink_dot_zshrc        → chezmoi creates ~/.zshrc as symlink to this file
symlink_dot_gitconfig    → chezmoi creates ~/.gitconfig as symlink
```

**This preserves our current edit-in-place workflow** while gaining chezmoi's orchestration, scripts, and ignore system. The tradeoff: symlinked files can't use templates (same as today).

### Recommendation

Use **symlink mode for frequently-edited files** (~10 files: zshrc, gitconfig, starship.toml, etc.) and **copy mode for files that need templating** (~5 files: ssh/config, claude configs with conditional enterprise includes). This matches our current behavior almost exactly.

---

## 4. Day-to-Day Workflow Comparison

### Adding a new config file

**Today:**
1. Put file in `home/newconfig`
2. Add `link_file "$DOTFILES_DIR/home/newconfig" "$HOME_DIR/.newconfig"` to a module `install.sh`
3. Add `check_symlink "mod-newconfig" "$DOTFILES_DIR/home/newconfig" "$HOME/.newconfig"` to module `doctor.sh`
4. Run `dotfiles install --module <mod>`

**With chezmoi:**
1. `chezmoi add ~/.newconfig` (auto-copies to source dir with correct naming)
2. Done. Next `chezmoi apply` deploys it. `chezmoi verify` checks it.

### Editing an existing config

**Today:** Edit `~/.zshrc` directly (symlink). Changes appear in `git diff`.

**With chezmoi (symlink mode):** Same — edit `~/.zshrc` directly. Still a symlink.

**With chezmoi (copy mode):** `chezmoi edit ~/.zshrc` opens the source file in `$EDITOR`. Or edit `~/.zshrc` directly then `chezmoi re-add ~/.zshrc`.

### Setting up a new machine

**Today:**
```bash
git clone git@github.example.com:your-org/dotfiles.git ~/apps/dotfiles
cd ~/apps/dotfiles
./bootstrap.sh   # or ./install.sh --all
```

**With chezmoi:**
```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply your-org/dotfiles
```

One command, no manual clone. Chezmoi clones to `~/.local/share/chezmoi` by default and prompts for machine-specific data on first run.

> **Repo location decision:** `bin/` scripts are in PATH via `zshrc` (currently `~/apps/dotfiles/bin`). Two options:
> 1. **Keep default location** — update PATH in zshrc to `$(chezmoi source-path)/bin` or hardcode `~/.local/share/chezmoi/bin`. Simple but couples PATH to chezmoi internals.
> 2. **Custom source dir** — `chezmoi init --source ~/apps/dotfiles --apply your-org/dotfiles`. Clones to `~/apps/dotfiles`, PATH unchanged. Requires testing that `--source` with `init` clones to the specified path.
>
> Recommend option 2 to preserve current PATH and all scripts that reference `$DOTFILES_DIR`.

### Reverting a bad change

**Today:** `./revert.sh` — interactive snapshot picker (453 lines of code), reverts macOS defaults, symlinks, brew packages, git ref.

**With chezmoi:** `git -C $(chezmoi source-path) checkout HEAD~1 && chezmoi apply` — reverts to previous git state. For macOS defaults, keep a lightweight `revert-macos.sh` (the snapshot approach was already best-effort since it can't capture all defaults atomically).

### What happens to the `dotfiles` CLI

The current `bin/dotfiles` wrapper (144 lines) provides `dotfiles install`, `dotfiles doctor`, `dotfiles sync`, etc. Post-migration:

| Command | Current | After chezmoi |
|---------|---------|---------------|
| `dotfiles install` | Runs `install.sh` | Runs `chezmoi apply` |
| `dotfiles doctor` | Runs `dotfiles-doctor` | **Unchanged** — keep as-is |
| `dotfiles sync` | Runs `dotfiles-sync` | Simplified git sync. **Lost:** WebStorm keymap backup (live → repo), gist-based remote snapshots. Keep a slim `dotfiles-sync` for these if needed. |
| `dotfiles update` | Pull + re-run install | `chezmoi update` (built-in) |
| `dotfiles edit` | Opens repo in editor | `chezmoi cd` or keep wrapper |
| `dotfiles status` | Shows git status | **Unchanged** |
| `dotfiles stats` | Shows time-saved | **Unchanged** |

The wrapper shrinks from 144 lines to ~60 lines (just delegates to chezmoi for install/update/sync, keeps doctor/stats/edit as-is).

---

## 5. Agent Workflow Impact

AI agents (Cascade, Claude Code) interact with dotfiles in two ways:

**1. Agents editing config files (e.g., `~/.zshrc`)**

With symlink mode: no change. Agents edit the symlink target, changes persist in git.

With copy mode: agents edit the copy at `~/.zshrc`, which gets overwritten on next `chezmoi apply`. Mitigation: use symlink mode for all files agents commonly edit.

**2. Agents running dotfiles commands**

`AGENTS.md` currently references `link_file()`, module structure, and `install.sh` flags. Post-migration:
- Update `AGENTS.md` to reference chezmoi commands
- The simpler API (`chezmoi add`, `chezmoi apply`) is easier for agents to use than our custom module system

**3. External config integration**

With chezmoi, use `.chezmoiexternal.yaml` to pull files from other repos:

```yaml
".claude/CLAUDE.md":
  type: file
  url: "https://github.example.com/raw/your-org/some-repo/main/claude/CLAUDE.md"
  refreshPeriod: "24h"
```

Or keep a symlink via `symlink_` prefix if the source repo is always present locally.

---

## 6. `dotfiles-doctor` Adaptation

The doctor system (260 lines in `bin/dotfiles-doctor` + 256 lines across module `doctor.sh` files) is the most valuable custom code we keep. It needs adaptation:

### Current: symlink-based checks

```bash
check_symlink "git-config" "$DOTFILES_DIR/home/gitconfig" "$HOME/.gitconfig"
# → Passes if ~/.gitconfig is a symlink pointing to the exact source path
```

### After: content-based checks for copied files

For files managed as copies, replace `check_symlink` with `check_managed`:

```bash
check_managed() {
  local id="$1" src="$2" dst="$3"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    pass "$dst → dotfiles (symlink)"
  elif [ -f "$dst" ] && chezmoi verify "$dst" &>/dev/null; then
    pass "$dst → dotfiles (managed)"
  elif $FIX_MODE; then
    chezmoi apply "$dst"
    fixed "$dst"
  else
    fail "$dst not managed by chezmoi"
  fi
}
```

For files managed as symlinks (symlink mode), `check_symlink` works unchanged.

**Effort:** ~2 hours. Add `check_managed()` to `bin/dotfiles-doctor` (since `lib/utils.sh` is deleted), update ~15 calls across module `doctor.sh` files.

### `chezmoi doctor` vs `dotfiles-doctor`

Chezmoi has its own `chezmoi doctor` that checks chezmoi health (binary version, config, git status). It does **not** check:
- macOS `defaults` values
- Homebrew package presence
- SSH key permissions
- LaunchAgent status
- Git config values (rerere, fsmonitor, etc.)

Our `dotfiles-doctor` remains valuable and complements `chezmoi doctor`. They serve different purposes.

---

## 7. Homebrew Management

### Current

`install.sh` collects `Brewfile` from each active module directory, concatenates them, and runs `brew bundle`. The 946-line installer handles Homebrew installation, Xcode CLT checks, and recovery.

### With chezmoi

Use a `run_onchange_` script triggered by Brewfile content changes:

```bash
#!/bin/bash
# .chezmoiscripts/run_onchange_brew.sh.tmpl
# Hash: {{ include "Brewfile" | sha256sum }}

brew bundle --file="{{ .chezmoi.sourceDir }}/Brewfile" --no-lock
```

The `{{ include "Brewfile" | sha256sum }}` in the comment makes chezmoi re-run the script only when Brewfile content changes. First-run Homebrew installation moves to `run_once_bootstrap.sh`.

Profile-based Brewfile sections use Go templates:

```ruby
# Brewfile.tmpl
brew "bat"
brew "eza"
brew "fd"
brew "ripgrep"

{{ if eq .profile "full" -}}
brew "lazygit"
cask "ghostty"
cask "font-jetbrains-mono-nerd-font"
{{- end }}

{{ if .is_enterprise -}}
brew "awscli"
brew "kubernetes-cli"
brew "gradle"
{{- end }}
```

This replaces the per-module Brewfile concatenation with a single templated file.

---

## 8. Proposed Directory Structure

The repo root IS the chezmoi source directory. This is the standard chezmoi pattern — non-dotfile files (bin/, tests/, docs/) go in `.chezmoiignore` so chezmoi doesn't try to deploy them to `$HOME`.

Current `home/` files get renamed with chezmoi prefixes and move to repo root. The `home/` directory goes away.

```
dotfiles/                              # = chezmoi source dir
├── .chezmoi.yaml.tmpl                 # Init-time prompts for profile/enterprise
├── .chezmoiignore                     # Ignore non-dotfile repo files + profile conditions
├── .chezmoiexternal.yaml              # External sources
│
│   # ── Dotfiles (deployed to $HOME) ─────────────────────────
├── symlink_dot_zshrc                  # → ~/.zshrc (symlink, edit-in-place)
├── symlink_dot_zshenv                 # → ~/.zshenv
├── symlink_dot_gitconfig              # → ~/.gitconfig
├── symlink_dot_gitignore_global       # → ~/.gitignore_global
├── symlink_dot_ideavimrc              # → ~/.ideavimrc
├── symlink_dot_tmux.conf              # → ~/.tmux.conf
├── dot_editorconfig                   # → ~/.editorconfig (copy, rarely edited)
├── dot_hushlogin                      # → ~/.hushlogin
├── dot_npmrc                          # → ~/.npmrc
├── dot_tigrc                          # → ~/.tigrc
├── private_dot_ssh/                   # → ~/.ssh/ (private = 0700 permissions)
│   ├── config.tmpl                    # Templated: conditional enterprise Include
│   └── config.enterprise              # Only deployed if is_enterprise=true
├── dot_config/
│   ├── starship.toml                  # → ~/.config/starship.toml
│   ├── atuin/config.toml              # → ~/.config/atuin/config.toml
│   ├── ghostty/config                 # → ~/.config/ghostty/config
│   └── lazygit/config.yml             # → ~/.config/lazygit/config.yml
│
│   # ── Lifecycle scripts ────────────────────────────────────
├── .chezmoiscripts/
│   ├── run_once_bootstrap.sh          # First-run: install Homebrew, Xcode CLT
│   ├── run_onchange_brew.sh.tmpl      # Re-run when Brewfile changes
│   ├── run_onchange_macos.sh.tmpl     # Re-run when macos.sh changes
│   ├── run_onchange_launchagents.sh.tmpl  # Re-run when plist templates change
│   └── run_after_cache-inits.sh       # Cache fzf/zoxide/direnv inits
│
│   # ── Non-dotfile repo files (all in .chezmoiignore) ───────
├── bin/                               # Utility scripts — in PATH via zshrc (see §4 repo location note)
│   ├── dotfiles                       # CLI wrapper (simplified)
│   ├── dotfiles-doctor                # Health checks (adapted for chezmoi)
│   ├── dotfiles-sync                  # Simplified: git sync + WebStorm keymap backup
│   ├── dotfiles-stats                 # Time-saved tracking (unchanged)
│   ├── cleanup, morning, ...          # 18 more scripts (unchanged)
├── Brewfile.tmpl                      # Single templated Brewfile
├── macos.sh                           # macOS defaults (called by run_onchange_)
├── macos-visual.sh                    # Visual preferences
├── macos-apps.sh                      # App preferences
├── modules/                           # Only doctor.sh files remain
│   ├── git/doctor.sh
│   ├── shell/doctor.sh
│   └── ...
├── launchagents/                      # Plist templates (deployed by run_onchange_)
├── git-hooks/                         # Git hooks
├── tests/                             # Kept: doctor, smoke, modules, stats tests
│   ├── doctor.bats                    # 170 lines
│   ├── smoke.bats                     # 109 lines
│   ├── modules.bats                   # 79 lines
│   └── stats.bats                     # 155 lines
├── docs/                              # RFCs and documentation
├── AGENTS.md
├── README.md
└── Makefile
```

### `.chezmoiignore` — non-dotfile files + profile conditions

```
# Non-dotfile repo files (never deployed to $HOME)
bin
Brewfile.tmpl
macos.sh
macos-visual.sh
macos-apps.sh
modules
launchagents
git-hooks
tests
docs
AGENTS.md
README.md
CHANGELOG.md
CLAUDE.md
CONTRIBUTING.md
Makefile
.github
.gitignore
.sync-protect
tasks-queue.yaml

# Profile-based ignoring
{{- if ne .profile "full" }}
symlink_dot_ideavimrc
symlink_dot_tmux.conf
dot_config/ghostty
dot_config/lazygit
{{- end }}

{{- if not .is_enterprise }}
private_dot_ssh/config.enterprise
{{- end }}
```

### `.chezmoi.yaml.tmpl` — first-run prompts

```yaml
{{- $profile := promptChoiceOnce "profile" "Installation profile" (list "full" "core" "minimal") -}}
{{- $enterprise := promptBoolOnce "is_enterprise" "Enable enterprise configs (AWS, K8s, Gradle)" false -}}

data:
  profile: {{ $profile | quote }}
  is_enterprise: {{ $enterprise }}
```

Replaces the gum-powered interactive module picker with chezmoi's built-in prompt system. Less visual, but zero custom code.

---

## 9. What Gets Deleted

| File | Lines | Replacement | Tests deleted |
|------|-------|-------------|---------------|
| `install.sh` | 946 | `chezmoi apply` + `.chezmoiscripts/` | `install.bats` (168 lines) |
| `lib/utils.sh` | 272 | chezmoi engine + simplified `check_managed()` | `link_file.bats` (146 lines) |
| `snapshot.sh` | 262 | `git log` + `chezmoi diff` | `snapshot.bats` (224 lines) |
| `revert.sh` | 453 | `git checkout` + `chezmoi apply` | `revert.bats` (137 lines) |
| `bootstrap.sh` | 150 | `chezmoi init --apply` | — |
| `modules/*/install.sh` (15 files) | 374 | `.chezmoiscripts/run_onchange_*` | — |
| `bin/dotfiles-sync` | 123 | Simplified to git sync only. WebStorm keymap backup + gist remote snapshots dropped (or kept in a ~30 line script). | — |

**Total deleted:** ~2,580 lines of bash + ~675 lines of tests = **~3,255 lines removed**

**Total kept:** ~3,460 lines (bin scripts, macos defaults, doctor checks, remaining tests incl. `stats.bats`, launchagents)

**New code written:** ~200 lines (`.chezmoi*.yaml`, `.chezmoiscripts/`, `check_managed()`, CLI wrapper updates)

**Net reduction: ~3,050 lines** (from ~6,500 to ~3,500)

---

## 10. Migration Plan

Clean rewrite on a dedicated branch. No parallel coexistence — delete old framework code and replace with chezmoi in one pass. Rollback = `git checkout main`.

### Phase 1: Rewrite (1-2 days)

Branch: `feat/chezmoi`

1. `brew install chezmoi`
2. Rename `home/` files to chezmoi naming at repo root (`symlink_dot_zshrc`, `dot_editorconfig`, `private_dot_ssh/`, etc.). Remove `home/` directory.
3. Write `.chezmoi.yaml.tmpl` with profile/enterprise prompts
4. Write `.chezmoiignore` with profile-based conditions
5. Write `.chezmoiscripts/` — `run_once_bootstrap.sh`, `run_onchange_brew.sh.tmpl`, `run_onchange_macos.sh.tmpl`, `run_onchange_launchagents.sh.tmpl`
6. Write templated `Brewfile.tmpl` and `private_dot_ssh/config.tmpl`
7. Delete `install.sh`, `lib/utils.sh`, `snapshot.sh`, `revert.sh`, `bootstrap.sh`
8. Delete `modules/*/install.sh` (keep `doctor.sh` files)
9. Delete obsolete tests (`install.bats`, `link_file.bats`, `snapshot.bats`, `revert.bats`)
10. Add `check_managed()` to doctor, update check calls
11. Simplify `bin/dotfiles` CLI wrapper
12. Update `README.md`, `AGENTS.md`, `Makefile`
13. Test full cycle: `chezmoi init --apply` on clean home dir (use temp `$HOME`)
14. Merge to main

### Phase 2: Enhancements (ongoing)

- ~~Secrets encryption via age or 1Password CLI~~ ✅ Done (age builtin, enterprise SSH config encrypted)
- `.chezmoiexternal.yaml` for external config integration
- ~~`chezmoi doctor` integration into `dotfiles doctor`~~ ✅ Done (chezmoi health section in doctor output)
- Auto-apply on file change via `chezmoi --watch` (experimental) — deferred

---

## 11. Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Edit-in-place workflow changes for copied files | **High** | Use `symlink_` mode for all frequently-edited files (~10). Only use copies for templated files (~5). |
| `dotfiles-doctor` assumes symlinks | Medium | Add `check_managed()` function (~20 lines). Update ~15 check calls. ~2 hours of work. |
| AI agents edit `~/.zshrc` copy, changes lost on apply | Medium | Symlink mode for agent-touched files. Document in `AGENTS.md`. |
| Snapshot/revert of macOS defaults lost | Medium | macOS defaults snapshot was already best-effort (can't atomically capture all defaults). Keep a minimal `revert-macos.sh` if needed, but `defaults read` + `defaults write` scripts are ~50 lines. |
| Go template syntax errors in config files | Low | Only ~5 files need templates. `chezmoi execute-template` validates before apply. |
| `dotfiles` CLI wrapper breaks | Low | Simplify to delegate to chezmoi. Test in Phase 2. |
| LaunchAgent loading edge cases | Low | Keep existing `launchctl` logic in `run_onchange_` script — same code, different trigger mechanism. |
| Interactive module picker UX loss | Low | `chezmoi init` prompts for profile choice. Less visual than gum picker but zero maintenance. |

---

## 12. Decision

**Migrate to chezmoi.**

The framework layer (install, symlink, backup, snapshot, revert, bootstrap, locking) is ~2,600 lines of custom bash that chezmoi handles better — with templating, secrets, dry-run diffing, and a large active community maintaining edge cases we'd never discover.

The unique value of this repo — macOS defaults scripts, 22 utility bin scripts, health checks, LaunchAgents — is untouched. Chezmoi manages these as regular files.

**Key design decisions:**
- **Symlink mode** for frequently-edited files (zshrc, gitconfig, etc.)
- **Copy mode** only for templated files (ssh/config, enterprise conditionals)
- **Keep `dotfiles-doctor`** — adapted for mixed symlink/copy verification
- **Keep `bin/dotfiles` wrapper** — simplified to delegate to chezmoi

**Estimated effort:** 1-2 days for the rewrite on a dedicated branch. Rollback = `git checkout main`.
