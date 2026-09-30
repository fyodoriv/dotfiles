# User Stories

Dotfiles manages shell, git, macOS, and editor config with self-healing health checks. One command deploys everything; LaunchAgents keep it running.

**Data safety guarantee:** personal overrides (`~/.zshrc.local`, `~/.gitconfig.local`) are gitignored and never touched. Symlinked files are edited in place — chezmoi only manages the symlink.

See [../README.md](../../README.md) for installation and CLI reference.

## Flows

| # | Use Case | One-liner | Command |
|---|----------|-----------|---------|
| 1 | [Set up a new Mac](01-fully-configured-mac.md) | Stock macOS to fully configured in one command | `chezmoi init --apply` |
| 2 | [Start the day ready to code](02-start-day-ready-to-code.md) | Pull, health check, dashboard | `morning` |
| 3 | [Add and maintain config](03-add-and-maintain-config.md) | Scaffolding commands for files, tools, defaults, modules | `dotfiles add` |
| 4 | [Switch profiles and customize](04-switch-profiles-and-customize.md) | Core/full profiles + personal overrides | `dotfiles profile` |
| 5 | [Config heals itself](05-config-heals-itself.md) | Auto-sync + auto-doctor via LaunchAgents | `dotfiles doctor --fix` |
| 6 | [Stay safe from damage](06-stay-safe-from-damage.md) | Deletion protection, git-safe, secret scanning | `dotfiles audit` |
| 7 | [Git workflow helpers](07-git-workflow-helpers.md) | PR, hotfix, review scripts | `pr`, `hotfix`, `review` |
| 8 | [Time saved by automation](08-time-saved-by-automation.md) | Runs, time saved, streak | `dotfiles stats` |
| 9 | [Run AI coding agents on a local model](09-run-local-models-fast.md) | Local LLM fallback for agent loops | `dotfiles doctor --module local-llm` |
| 10 | [Add your company's config without forking](10-fork-for-your-company.md) | Private overlay repo plugs in via `extra_overlay_root` | `dotfiles apply` |

## Ownership Boundary

| What | Owner |
|------|-------|
| Shell, git, macOS, SSH, editor, terminal config | **dotfiles** |
| Agent config (CLAUDE.md, MCP, skills, rules) | **agentbrew** |
| Orchestrator, personas, pipelines | **minsky** |
