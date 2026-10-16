# Decisions (ADRs)

Each file records one decision that is hard to reverse: the context, the
decision, and its consequences (Nygard, "Documenting Architecture Decisions",
2011). Add a new numbered file for a new decision; never rewrite an accepted
one. Supersede it with a new ADR and update the old one's status line.

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-canonical-branch-feat-chezmoi.md) | `feat/chezmoi` is the canonical branch | Accepted 2026-05-13 |
| [0002](0002-canonical-docs-at-repo-root.md) | VISION, ARCHITECTURE, and ROADMAP live at the repo root | Accepted 2026-05-23 |
| [0003](0003-single-public-home-with-leak-gates.md) | One public home on github.com, guarded by leak gates | Accepted 2026-09-29 |
| [0004](0004-build-on-chezmoi.md) | Build on chezmoi instead of a custom deploy engine | Accepted (recorded 2026-10-16) |
| [0005](0005-rule-9-fields-on-p0-p1-only.md) | Rule-9 hypothesis fields are required on P0/P1 only | Accepted 2026-10-16 |

The short decision log in [ROADMAP.md](../../ROADMAP.md#decision-log) links here.
