# 0003. One public home on github.com, guarded by leak gates

- **Status**: Accepted
- **Date**: 2026-09-29

## Context

dotfiles once had a public mirror and private copies. Mirroring caused drift
and leaks, and a force-push does not purge old commits from GitHub.

## Decision

`github.com/fyodoriv/dotfiles` is the only home. Every machine uses the same
flow: feature branch, push, PR, merge. Org-specific content lives in an overlay
repo, never here. Git hooks block private emails and private-pattern matches
before they reach github.com, and they fail closed when the pattern file is
missing or outdated.

## Consequences

- `git-hooks/pre-commit`, `git-hooks/pre-push`, `bin/gh`, and
  `tests/no-internal-refs.bats` enforce the contract ([SECURITY.md](../../SECURITY.md)).
- A leak that does reach GitHub means recreating the repository from a clean
  commit, so prevention matters more than cleanup.
