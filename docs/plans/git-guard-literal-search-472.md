# Git guard: literal search patterns (#472)

Frozen before any code change. Do not edit the controls after the fix starts.

## Problem

`agent-hooks/block-dangerous-git.sh` matches `git reset --hard`, `git clean -f`,
`git checkout .`, `git restore .` and `git branch -D` as plain text. A read-only
`rg` search whose quoted pattern names one of them is blocked (exit 2).

Reproduced on feat/chezmoi, 2026-11-08: all 4 safe controls below exit 2.

## Environment

- Hook run as `bash agent-hooks/block-dangerous-git.sh`, JSON on stdin:
  `{"tool_name":"Bash","tool_input":{"command":"<input>"}}`.
- `RIPGREP_CONFIG_PATH` unset. Hook's own `PATH`.

## Safe controls (must exit 0 after the fix)

1. `rg 'git branch -D' docs`
2. `rg -n "git reset --hard" agent-hooks`
3. `rg -F 'git push --force' .`
4. `rg 'git clean -fd' tests`

## Unsafe controls (must exit 2, before and after)

1. `git branch -D foo`
2. `rg x; git branch -D foo`
3. `rg $(git branch -D foo) .`
4. `` rg `git reset --hard` . ``
5. `rg --pre 'git reset --hard' x .` (`--pre` runs a program)
6. `RIPGREP_CONFIG_PATH=x rg 'git reset --hard' .` (config can add `--pre`)
7. `rg 'git reset --hard' . | sh`
8. `rg x && git reset --hard`

## Grammar to qualify

Only a segment whose first word is exactly `rg`, with no env-assignment prefix,
no `--pre`/`--pre-glob`/`--search-zip`/`-z`, no substitution, no redirection,
and no pipe into a shell, counts its quoted pattern as data. Anything else keeps
the current conservative match.

## Decision

- Keep: 4/4 safe exit 0, 8/8 unsafe exit 2, and `tests/block-dangerous-git*.bats`
  unchanged and green.
- Reject the approach: any unsafe control exits 0.
- Measurement: `bats tests/block-dangerous-git-literal-search.bats` (added with the fix).
