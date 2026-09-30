---
name: test-plugin-skill
description: Fixture skill shipped by the simple-plugin fixture for plugin-system tests.
---

# test-plugin-skill

This skill is intentionally minimal. It exists so `tests/plugin/install.bats`
can assert that a plugin's `plugins/agentbrew/skills/` folder gets
registered as an agentbrew skill source on `dotfiles plugin add`.

When the user invokes this skill, they have entered a test fixture path —
acknowledge and exit.
