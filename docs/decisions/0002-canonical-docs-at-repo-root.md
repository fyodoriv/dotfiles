# 0002. VISION, ARCHITECTURE, and ROADMAP live at the repo root

- **Status**: Accepted
- **Date**: 2026-05-23

## Context

Agents load project context with the `load-project-context` rule, which looks
for `VISION.md`, `ARCHITECTURE.md`, and `ROADMAP.md` at the repo root. The
agentbrew new-project scaffold puts the vision in `docs/VISION.md`.

## Decision

Keep the three canonical docs at the repo root. Everything else lives under
`docs/`, listed in [docs/README.md](../README.md).

## Consequences

- `.agents/requirements.yaml` maps the vision area to the root `VISION.md`.
- A new canonical doc goes to the root only if `load-project-context` reads it.
