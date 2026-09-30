# Tests

[bats](https://github.com/bats-core/bats-core) tests. Every script in `bin/`, every module in `modules/`, and every library in `lib/` has corresponding tests.

## Running tests

```bash
make test          # affected tests only (cached, git-aware — fast for iteration)
make test-all      # full suite (cached)
make test-force    # full suite, no cache
make lint          # shellcheck all scripts
make check         # lint + test (run before committing)
```

Run a single test file:

```bash
bats tests/doctor.bats
```

Run tests matching a name pattern:

```bash
bats tests/doctor.bats --filter "json"
```

## File naming conventions

| Pattern | Tests for | Example |
|---------|-----------|---------|
| `<script>.bats` | `bin/<script>` | `doctor.bats` tests `bin/dotfiles-doctor` |
| `module-<name>.bats` | `modules/<name>/doctor.sh` | `module-git.bats` tests `modules/git/doctor.sh` |
| `<lib>.bats` | `lib/<lib>.sh` | `colors.bats` tests `lib/colors.sh` |
| `macos-*.bats` | `macos*.sh` defaults scripts | `macos-defaults.bats` tests `macos.sh` |

## Writing a new test

1. Create a file matching the naming convention above.
2. Load the shared helper and set up isolation:

```bash
#!/usr/bin/env bats
load test_helper

@test "my feature works" {
  # test_helper.bash creates TEST_DIR, TEST_HOME, TEST_DOTFILES
  # and sets HOME and DOTFILES_DIR to isolated temp dirs
  create_file "$TEST_DOTFILES/bin/my-script" '#!/bin/bash\necho hello'
  chmod +x "$TEST_DOTFILES/bin/my-script"

  run bash "$TEST_DOTFILES/bin/my-script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello"* ]]
}
```

3. Run it: `bats tests/my-test.bats`

## Helper functions (`test_helper.bash`)

| Function | Purpose |
|----------|---------|
| `create_file <path> <content>` | Create a file with content (creates parent dirs) |
| `assert_symlink <path> <target>` | Assert path is a symlink pointing to target |
| `assert_file <path>` | Assert path exists as a regular file |
| `assert_no_file <path>` | Assert path does not exist |

The `setup()` function creates isolated temp directories:
- `$TEST_DIR` — temp root (cleaned up in teardown)
- `$TEST_HOME` — fake `$HOME`
- `$TEST_DOTFILES` — fake dotfiles repo root

## Common patterns

**Testing a check function** (doctor modules):

```bash
@test "check passes when condition is met" {
  check "my.id" "description" "true" ""
  [ "$pass_count" -eq 1 ]
}
```

**Testing CLI output**:

```bash
@test "script outputs expected text" {
  run bash "$BATS_TEST_DIRNAME/../bin/my-script" --flag
  [ "$status" -eq 0 ]
  [[ "$output" == *"expected text"* ]]
}
```

**Testing file operations**:

```bash
@test "script creates config file" {
  run bash "$BATS_TEST_DIRNAME/../bin/my-script"
  assert_file "$TEST_HOME/.config/myapp/config"
}
```

## Tips

- Tests run in isolated temp dirs — never touch the real `$HOME`
- Use `$BATS_TEST_DIRNAME/../bin/script` to reference scripts relative to the test file
- Doctor module tests typically override `pass()`, `fail()`, `fixed()`, `skipped()` to just increment counters (see `doctor.bats` for the pattern)
- `run` captures stdout in `$output` and exit code in `$status`
- Use `[[ ]]` for pattern matching, `[ ]` for strict equality
