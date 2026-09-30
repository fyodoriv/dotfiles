---
name: dotfiles-development
disable-model-invocation: true
description: >
  How to work with this chezmoi-powered dotfiles repo. Covers conventions, testing,
  committing, file modes, and the CLI. Use when editing any file in the dotfiles repo.
  Don't use for creating new modules (use dotfiles-new-module).
---

## Repo Structure

```
dotfiles/
├── bin/                    # CLI scripts (dotfiles, dotfiles-doctor, cleanup, morning, etc.)
├── lib/                    # Shared shell libraries (colors.sh, stats.sh, output.sh)
├── modules/                # Doctor modules (auto-discovered by dotfiles-doctor)
│   └── <name>/
│       └── doctor.sh       # Health checks (bash, sourced by doctor)
├── home/                   # Symlinked dotfiles (~/.gitconfig → home/gitconfig)
├── tests/                  # Bats test suite
│   └── test_helper.bash    # Shared setup/teardown for isolated test environments
├── .chezmoiscripts/        # Lifecycle scripts (run during chezmoi apply)
├── dot_*                   # Copy-mode files (deployed to ~/.<name>)
├── symlink_dot_*.tmpl      # Symlink templates (point to home/<name>)
├── macos.sh                # macOS defaults (sourced during apply)
├── Makefile                # lint, test, check targets
├── AGENTS.md               # Agent instructions
└── CONTRIBUTING.md         # Full architecture guide
```

## File Modes

| Source naming | Mode | Deployed as |
|--------------|------|-------------|
| `symlink_dot_*.tmpl` → `home/*` | Symlink | `~/.<name>` → `home/<name>` (edit in place) |
| `dot_*` | Copy | `~/.<name>` (run `dotfiles apply` after editing) |
| `private_dot_*` | Private copy (0700) | `~/.<name>` |
| `*.tmpl` | Template | Rendered with chezmoi data |

## Verification Commands

```bash
make lint       # shellcheck all scripts
make test       # bats test suite
make check      # lint + test (MUST pass before committing)
```

## Prompt And Task Interpretation

Minsky pipeline prompts sometimes include machine-generated labels from
previous pipeline state. Treat the files in the active worktree as the source of
truth, then reconcile labels against `context.md` and `manager.md`.

- Trust `[ZERO-SCOPE TASK]` only when `context.md`, `manager.md`, and the git
  diff all agree there is no code or docs work left. In that case, do not invent
  implementation work; verify the no-op, explain why it is complete, remove the
  task block, and commit the queue cleanup.
- Override `[ZERO-SCOPE TASK]` when `context.md` records a Manager PASS with
  concrete file changes, failing verification, or remaining implementation
  steps. The label is stale pipeline metadata in that case.
- Override `[ZERO-SCOPE TASK]` when `manager.md` contains a non-trivial plan or
  names files to edit. Implement the plan normally and note the override in the
  final summary.
- Use `context.md` as ground truth when it conflicts with the prompt summary.
  If line numbers or file paths are provided, open the live files and verify the
  locations before editing; line numbers drift between pipeline iterations.
- Worktree paths in prompts are literal. Run commands from that path or pass
  `-C <worktree>` / absolute file paths; subdirectory tools such as biome and
  TypeScript resolve file arguments relative to the current working directory.

## Formatter And Baseline Failures

Dotfiles itself uses shellcheck and bats, but many sibling repos use biome and
TypeScript. When a dotfiles task captures cross-repo editor guidance, preserve
the distinction between changed-file checks and full verification.

- Run a targeted biome write pass such as `npx biome check --write <changed-files>`
  soon after editing TypeScript/JavaScript files; it catches unused imports and
  formatting drift before the full verify loop.
- In repos with documented baseline warnings, run changed-file checks first
  (`npx biome check <changed-files>`, not `npx biome check .`) so pre-existing
  complexity warnings in untouched files do not hide regressions from your diff.
- Do not churn on pre-existing verify failures. Capture the failing command,
  confirm it also fails without your changes or outside your touched files, and
  report it as pre-existing instead of "fixing" unrelated noise.
- Full verify still matters before completion; changed-file checks are an early
  diagnostic, not a replacement for the repo's documented gate.

## Shell Script Conventions

1. **Use `fd` instead of `find`** in all scripts
2. **Never hardcode `$HOME` paths** — use `$HOME` variable or chezmoi templates
3. **Use `set -euo pipefail`** at the top of standalone scripts (not in sourced libraries)
4. **Quote all variables** — `"$var"` not `$var`
5. **Use `command -v`** to check for tool existence, not `which`
6. **Use `local`** for all function variables
7. **Add shellcheck directives** when needed: `# shellcheck disable=SC2154`

## Testing with Bats

Tests live in `tests/`. Each test file uses an isolated temp environment:

```bash
#!/usr/bin/env bats
load test_helper

@test "description of what you're testing" {
  # test_helper provides: $TEST_DIR, $TEST_HOME, $TEST_DOTFILES
  # HOME and DOTFILES_DIR are overridden for isolation
  create_file "$TEST_DOTFILES/some/file" "content"
  
  # Run the thing being tested
  run some_command
  
  # Assert
  [ "$status" -eq 0 ]
  [[ "$output" == *"expected text"* ]]
  assert_file "$TEST_HOME/.config/something"
  assert_symlink "$TEST_HOME/.gitconfig" "$TEST_DOTFILES/home/gitconfig"
  assert_no_file "$TEST_HOME/.should-not-exist"
}
```

**Available helpers** from `test_helper.bash`:
- `create_file <path> [content]` — create a file with optional content
- `assert_symlink <path> <target>` — verify symlink points correctly
- `assert_file <path>` — verify regular file exists
- `assert_no_file <path>` — verify file does not exist

## Commit Rules

- Use short-lived feature branches for queued work; fast-forward `main` locally
  after verification only when the task runner needs direct local progress.
- Use conventional commits: `feat:`, `fix:`, `docs:`, `chore:`, `test:`
- Keep the commit subject at or under 72 characters; count before committing
  because the local `commit-msg` hook rejects longer subjects.
- Run `make check` before every commit
- Update README alongside behavior changes — README drift is a bug

## Ownership Boundary

| What | Owner |
|------|-------|
| Shell, git, macOS, SSH, editor config | **dotfiles** |
| Agent config (CLAUDE.md, MCP, skills, rules) | **agentbrew** |
| Orchestrator, personas, pipelines | **minsky** |

## Rules

- **Never edit files managed by agentbrew** (CLAUDE.md, MCP configs, agent skills)
- **Brewfile is inlined** in `.chezmoiscripts/run_onchange_brew.sh.tmpl`, not a standalone file
- **New modules need `modules/<name>/doctor.sh`** — auto-discovered by dotfiles-doctor
- **lib/ files are sourced**, not executed — they must not have `set -euo pipefail`
- **doctor.sh files are sourced** into dotfiles-doctor — they have access to `check()`, `check_symlink()`, `check_managed()`, `check_defaults()`, and `run_checks_from_yaml()`
