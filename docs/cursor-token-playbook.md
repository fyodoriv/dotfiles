# Cursor token playbook

Human-readable mirror of the **`cursor-token-playbook`** agentbrew skill
(`skill-plugins/dev/cursor-token-playbook/SKILL.md`). After `agentbrew sync`,
invoke the skill in Cursor for the live copy agents use.

## Quick reference

| Topic | Guidance |
|-------|----------|
| **Models** | ~70% fast Composer · ~20% strong when stuck · ~10% Ask-only |
| **New chat** | New deliverable, ring > ~60%, after rule/MCP sync, huge log dumps |
| **Proactive nudge** | Agents tell you when triggers match (see skill § "When to tell the user") |
| **Scope** | `@file` / `@folder` — not whole repo |
| **MCP** | Fewer enabled servers; disable unused this week |
| **Ignore** | Copy `templates/project.cursorignore` → repo `.cursorignore` |
| **Measure** | `agentbrew measure context` → `~/.config/agentbrew/metrics/latest.json` |
| **After ship-it** | New chat + measure context (see ship-it Step 12–13) |

## Per-repo `.cursorignore`

```bash
cp ~/apps/tooling/dotfiles/templates/project.cursorignore /path/to/repo/.cursorignore
```

Edit project-specific paths (large fixtures, generated dirs) as needed.

## Deep dives

- **Static config audit** — load `context-budget` skill
- **Ship-it post-delivery** — `docs/ship-it-reference.md` Step 12 (`measure context`, openusage/tokscale)
- **Runtime usage** — openusage, ccusage, tokscale (optional; graceful skip OK)
