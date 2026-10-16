# 0004. Build on chezmoi instead of a custom deploy engine

- **Status**: Accepted (recorded 2026-10-16; the move happened before 2026-05-13)
- **Date**: 2026-10-16

## Context

Rule 0 says GET, then WRAP, then CONTRIBUTE, and ABSORB only when blocked.
chezmoi already handles templates, secrets, per-machine data, and drift
detection. The competitive scorecard measures dotfiles against chezmoi, Stow,
yadm, dotbot, and home-manager ([scorecard](../competition/scorecard.md)).

## Decision

dotfiles deploys files with chezmoi and adds what chezmoi lacks: doctor checks
that heal drift, macOS settings, LaunchAgents, and the agent tooling setup.

## Consequences

- Cold apply costs about what chezmoi costs; `dotfiles apply` adds a small
  wrapper overhead on top.
- [VISION.md kill criteria](../../VISION.md#kill-criteria) retire the wrapper
  if it does not beat the plain tools by 2027-04-30.
