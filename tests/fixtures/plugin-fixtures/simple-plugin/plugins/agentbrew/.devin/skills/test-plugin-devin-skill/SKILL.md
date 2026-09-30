---
name: test-plugin-devin-skill
description: Devin-only fixture skill. Plugin install skips this folder when the Devin CLI is not present (per US-4 in docs/plugin-system.md).
---

# test-plugin-devin-skill

This skill is shipped under `plugins/agentbrew/.devin/skills/`. The plugin
install registers it as a separate skill source with label
`<plugin-name>-devin-skills` only when `command -v devin` succeeds.
Users without Devin get nothing from this folder.
