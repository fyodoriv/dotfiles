# 0001. `feat/chezmoi` is the canonical branch

- **Status**: Accepted
- **Date**: 2026-05-13

## Context

The repo moved from a hand-rolled symlink installer on `main` to chezmoi on a
long-lived `feat/chezmoi` branch. Renaming the branch back to `main` would
break every clone, the `dotfiles-sync` LaunchAgent, and links in docs.

## Decision

`feat/chezmoi` is the permanent canonical branch and the GitHub default.
`main` is retired. Every PR targets `feat/chezmoi`.

## Consequences

- `bin/dotfiles-sync` commits and pushes only on `feat/chezmoi`; feature
  branches are left to their owner.
- Docs and tools name `feat/chezmoi`, not `main`
  ([architecture.md](../architecture.md#canonical-branch-featchezmoi)).
