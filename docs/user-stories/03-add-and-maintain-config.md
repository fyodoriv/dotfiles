# User Story: Add and Maintain Config

> One command to add a config file, a Homebrew package, a macOS default, or a new health check module — each includes automatic verification.

## Add a Config File

```bash
dotfiles add ~/.my-tool-config              # symlink mode (default)
dotfiles add ~/.npmrc --copy                # copy mode
dotfiles add ~/.ssh/config --copy --module ssh  # copy + specific module
```

Defaults to symlink mode (`--copy` switches to copy), auto-detects the doctor module from the path, creates the symlink template or copy file, and adds a doctor health check. Prints `Next: dotfiles apply` — run that yourself to deploy.

### Which mode?

| Criteria | Symlink | Copy |
|----------|---------|------|
| Edit frequently | ✓ | |
| Changes appear instantly | ✓ | |
| Needs template rendering | | ✓ |
| Other tools may overwrite | | ✓ |
| Needs restricted permissions | | ✓ (private) |

- **Symlink** — content in `home/`, symlinked to `~/`. Edit source, changes appear instantly.
- **Copy** — prefixed `dot_*` at repo root, copied on `dotfiles apply`.
- **Private** — `private_dot_*`, copied with 0700 permissions.
- **Template** — add `.tmpl` suffix for profile-conditional rendering.

## Add a Homebrew Package

```bash
dotfiles brew-add ripgrep                        # core package
dotfiles brew-add ghostty --cask --full-only     # full-only GUI app
dotfiles brew-add kubectl --enterprise           # enterprise-only
```

Inserts the package in the right section of the brew lifecycle script. Prints `Next: dotfiles apply` — run that yourself; the `run_onchange` trigger detects the content hash changed and runs `brew bundle`.

## Add a macOS Default

```bash
dotfiles defaults-add com.apple.finder ShowPathbar 1 bool
```

Adds both the `defaults write` line to the appropriate script and a doctor health check in one step.

## Add a Health Check Module

```bash
dotfiles new-module mymodule --severity important
```

Creates `modules/mymodule/doctor.sh` with skeleton checks and registers severity. The doctor auto-discovers it — no registration needed.

### Available check functions

| Function | What it verifies |
|----------|-----------------|
| `check` | Run a test command, optionally auto-fix |
| `check_advisory` | Warning-only check (audit advisory, never fails the run) |
| `check_symlink` | Symlink exists and points correctly |
| `check_managed` | Chezmoi-managed file exists |
| `check_defaults` | macOS default matches expected value |

## Remove Managed Config

```bash
dotfiles unmanage ~/.my-tool-config
```

Removes the managed file from the repo and cleans up the symlink template or copy file.

## Files Involved

| Location | Purpose |
|----------|---------|
| `home/*` | Symlink targets |
| `symlink_dot_*.tmpl` | Symlink template pointers |
| `dot_*`, `private_dot_*` | Copy-mode files |
| `modules/*/doctor.sh` | Health checks (auto-discovered) |
| `.chezmoiscripts/run_onchange_brew.sh.tmpl` | Brewfile + install script |
