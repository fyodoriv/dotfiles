---
name: dotfiles-new-module
disable-model-invocation: true
description: >
  Create a new doctor module for the dotfiles repo. Covers module structure, check types,
  checks.yaml format, severity assignment, and testing. Use when adding a new doctor module.
  Don't use for general dotfiles development (use dotfiles-development).
---

## What a Module Is

A doctor module is a directory in `modules/` that defines health checks. The doctor
auto-discovers all `modules/*/doctor.sh` files — no registration needed.

```
modules/<name>/
├── doctor.sh       # Health checks (required — sourced by dotfiles-doctor)
└── severity        # Severity level file (optional — defaults to cosmetic)
```

## Step 1 — Scaffold

Use the built-in scaffolding command:

```bash
dotfiles new-module <name> [severity]
```

This creates the directory, `doctor.sh` with commented examples, and a `severity` file.
Severity options: `critical`, `important`, `performance`, `cosmetic` (default).

Or manually:

```bash
mkdir -p modules/<name>
```

## Step 2 — Write doctor.sh

The `doctor.sh` file is **sourced** (not executed) by `dotfiles-doctor`. It has access to
these check functions from `lib/output.sh`:

### check()

Generic check with test command and optional auto-fix:

```bash
check "<id>" "<description>" "<test_cmd>" "<fix_cmd>"
```

Example:
```bash
check "mymod.tool_installed" "my-tool installed" \
  "command -v my-tool" \
  "brew install my-tool"
```

### check_symlink()

Verify a symlink points to the right place:

```bash
check_symlink "<id>" "<source_path>" "<dest_path>"
```

Example:
```bash
check_symlink "symlink.myconfig" "$DOTFILES_DIR/home/myconfig" "$HOME/.myconfig"
```

### check_managed()

Verify a chezmoi-managed file exists (symlink or copy):

```bash
check_managed "<id>" "<source_path>" "<dest_path>"
```

### check_defaults()

Verify a macOS defaults value:

```bash
check_defaults "<id>" "<description>" "<domain>" "<key>" "<expected>" "<type>"
```

Example:
```bash
check_defaults "mymod.dark_mode" "Dark mode enabled" \
  "NSGlobalDomain" "AppleInterfaceStyle" "Dark" "string"
```

### run_checks_from_yaml()

Load data-driven checks from a YAML file:

```bash
run_checks_from_yaml "$DOTFILES_DIR/modules/<name>/checks.yaml"
```

## Step 3 — Write checks.yaml (optional)

For modules with many declarative checks, use `checks.yaml` instead of bash:

```yaml
# Supported types: defaults, git_config, symlink, file_perms

- id: mymod.setting_enabled
  desc: "My setting enabled"
  type: defaults
  domain: com.apple.finder
  key: ShowPathbar
  expected: "1"
  value_type: bool

- id: symlink.myconfig
  desc: myconfig symlink
  type: symlink
  src: "$DOTFILES_DIR/home/myconfig"
  dst: "$HOME/.myconfig"

- id: mymod.git_setting
  desc: "some git setting"
  type: git_config
  key: some.setting
  expected: "value"
  # optional: match: contains | not_empty | exact (default)
  # optional: fix: "custom fix command"

- id: mymod.script_executable
  desc: my-script is executable
  type: file_perms
  path: "$DOTFILES_DIR/bin/my-script"
  mode: executable
  fix: "chmod +x $DOTFILES_DIR/bin/my-script"
```

Then in `doctor.sh`:
```bash
#!/bin/bash
run_checks_from_yaml "$DOTFILES_DIR/modules/mymod/checks.yaml"

# Add any dynamic checks that need runtime logic below
```

## Step 4 — Assign Severity

Edit the `severity` file or pass severity to `dotfiles new-module`:

| Severity | When to use | Examples |
|----------|-------------|---------|
| 🚨 critical | Security, safety | ssh, workflow |
| ⚙️ important | Core developer config | git, shell, editor |
| ⚡ performance | System performance | macos, tools |
| 💅 cosmetic | Personal preference | jetbrains, terminal, prompt, extras |

If the module needs to be in a specific severity group in `dotfiles-doctor`, add
the module name to the appropriate `MODULE_SEVERITY_*` array in `bin/dotfiles-doctor`.

## Step 5 — Write Tests

Create `tests/<name>.bats`:

```bash
#!/usr/bin/env bats
load test_helper

@test "<name> module: doctor.sh exists" {
  create_file "$TEST_DOTFILES/modules/<name>/doctor.sh" "#!/bin/bash"
  assert_file "$TEST_DOTFILES/modules/<name>/doctor.sh"
}

@test "<name> module: check detects missing config" {
  # Source the check framework
  source "$BATS_TEST_DIRNAME/../lib/output.sh"
  
  # Test that the check correctly detects drift
  # ...
}
```

## Step 6 — Verify

```bash
make check                          # lint + test must pass
dotfiles doctor                     # see your new checks
dotfiles doctor --fix               # verify auto-fix works
dotfiles doctor --list | grep mymod # verify check IDs appear
```

## Check ID Conventions

- IDs are dot-separated: `<module>.<check_name>`
- Symlink checks use prefix: `symlink.<name>`
- Use lowercase, underscores for multi-word: `git.pull_rebase`
- IDs must be unique across all modules

## Rules

- `doctor.sh` is **sourced** — do NOT add `set -euo pipefail` (it would affect the parent)
- Use `$DOTFILES_DIR` for paths, never hardcode
- Check IDs must be globally unique
- Every fix command should be idempotent (safe to run multiple times)
- Use `checks.yaml` for declarative checks, `doctor.sh` for dynamic/runtime checks
- Run `make check` before committing
