---
name: dotfiles-doctor-debug
disable-model-invocation: true
description: >
  Debug and fix dotfiles-doctor check failures. Covers how the check framework works,
  common failure patterns, overrides, and the fix flow. Use when doctor checks fail
  or when troubleshooting the doctor system itself.
  Don't use for creating new modules (use dotfiles-new-module).
---

## How Doctor Works

`dotfiles-doctor` sources every `modules/*/doctor.sh` file. Each module calls check
functions that test a condition and optionally auto-fix it.

```
dotfiles doctor          # report only — shows pass/fail for all checks
dotfiles doctor --fix    # auto-fix all failures (respects .overrides)
dotfiles doctor --list   # list all check IDs
dotfiles doctor --quiet  # one-line summary (for scripts/prompts)
dotfiles doctor --report # markdown report
dotfiles doctor --trends # show pass/fail history over time
```

## Debugging a Failing Check

### Step 1 — Identify the check

```bash
dotfiles doctor 2>&1 | grep "✗"    # find failing checks
dotfiles doctor --list              # list all check IDs
```

Each check has a unique ID like `git.pull_rebase` or `symlink.gitconfig`.

### Step 2 — Find the check definition

Checks are defined in one of two places:

**In `doctor.sh`** (bash):
```bash
# modules/<module>/doctor.sh
check "mymod.some_check" "description" "test_cmd" "fix_cmd"
```

**In `checks.yaml`** (data-driven):
```bash
# modules/<module>/checks.yaml — find the check by ID
grep -A5 "id: <check_id>" modules/*/checks.yaml
```

### Step 3 — Run the test command manually

Extract the test command and run it:

```bash
# For a check like: check "git.pull_rebase" "pull.rebase = true" "[ \"$(git config --global pull.rebase)\" = 'true' ]"
# Run the test:
git config --global pull.rebase
# → should output "true"
```

### Step 4 — Run the fix command manually

```bash
# For the same check, the fix is:
git config --global pull.rebase true
```

### Step 5 — Verify

```bash
dotfiles doctor 2>&1 | grep "<check_id>"   # should now show ✓
```

## Common Failure Patterns

### Symlink checks fail

```
✗ symlink.gitconfig — gitconfig symlink
```

**Cause**: The symlink is missing or points to wrong target.

**Debug**:
```bash
ls -la ~/.gitconfig                     # check current state
readlink ~/.gitconfig                   # check where it points
ls -la ~/apps/dotfiles/home/gitconfig   # check source exists
```

**Fix**:
```bash
dotfiles doctor --fix   # auto-fixes symlinks
# or manually:
ln -sf ~/apps/dotfiles/home/gitconfig ~/.gitconfig
```

### macOS defaults checks fail

```
✗ macos.dock_autohide — Dock auto-hide enabled
```

**Debug**:
```bash
defaults read com.apple.dock autohide   # check current value
```

**Fix**:
```bash
dotfiles doctor --fix
# or manually:
defaults write com.apple.dock autohide -bool true
killall Dock
```

### Tool not installed

```
✗ tools.fd_installed — fd installed
```

**Fix**:
```bash
brew install fd
```

### Git config drift

```
✗ git.pull_rebase — pull.rebase = true
```

**Cause**: Git config was changed manually or by another tool.

**Fix**:
```bash
dotfiles doctor --fix    # resets all git config to expected values
```

## Overrides

Some checks can be permanently skipped if they don't apply to your setup:

```bash
dotfiles doctor --skip <check_id>    # adds to .overrides file
```

The `.overrides` file (`$DOTFILES_DIR/.overrides`) is a list of check IDs to skip:

```
macos.dock_autohide
tools.rancher_installed
```

Overrides are committed to the repo. Use them for intentional deviations, not to
hide real problems.

## The Check Framework Internals

### lib/output.sh

Defines the check functions and output formatting:

- `check()` — runs test_cmd, reports pass/fail, optionally runs fix_cmd in --fix mode
- `check_symlink()` — specialized: tests readlink, fixes with ln -sf
- `check_managed()` — specialized: tests file exists (symlink or copy)
- `check_defaults()` — specialized: tests `defaults read`, fixes with `defaults write`
- `pass()` / `fail()` / `skip()` — output helpers
- Counters: `$pass_count`, `$fail_count`, `$skip_count`, `$fix_count`

### Severity groups

Defined in `bin/dotfiles-doctor` as `MODULE_SEVERITY_*` arrays:

| Severity | Modules |
|----------|---------|
| 🚨 Critical | ssh, workflow |
| ⚙️ Important | git, shell, editor |
| ⚡ Performance | macos, tools |
| 💅 Cosmetic | jetbrains, terminal, prompt, extras, claude, cursor, enterprise |

Modules not in any array default to cosmetic.

## Adding a Fix to an Existing Check

If a check reports failure but has no auto-fix:

1. Find the check in `modules/<module>/doctor.sh` or `checks.yaml`
2. Add a fix command (4th argument to `check()`, or `fix:` field in YAML)
3. Fix must be idempotent (safe to run multiple times)
4. Test: `dotfiles doctor --fix` should resolve the failure
5. Run `make check` before committing

## Rules

- Never delete a check to make doctor pass — fix the underlying issue
- Override checks only for intentional deviations from the standard
- Fix commands must be idempotent
- Test the fix by running `dotfiles doctor --fix` then `dotfiles doctor` again
- Run `make check` before committing any changes to doctor modules
