# User Stories

Dotfiles manages shell, git, macOS, and editor config with self-healing health checks. One command deploys everything; LaunchAgents keep it running.

**Data safety guarantee:** personal overrides (`~/.zshrc.local`, `~/.gitconfig.local`) are gitignored and never touched. Symlinked files are edited in place — chezmoi only manages the symlink.

See [../README.md](../../README.md) for installation and CLI reference.

## Flows

| # | Use Case | One-liner | Command |
|---|----------|-----------|---------|
| 1 | [Set up a new Mac](01-fully-configured-mac.md) | Stock macOS to fully configured in one command | `bin/dotfiles-install run --yes` |
| 2 | [Start the day ready to code](02-start-day-ready-to-code.md) | Pull, health check, dashboard | `morning` |
| 3 | [Add and maintain config](03-add-and-maintain-config.md) | Scaffolding commands for files, tools, defaults, modules | `dotfiles add` |
| 4 | [Switch profiles and customize](04-switch-profiles-and-customize.md) | Core/full profiles + personal overrides | `dotfiles profile` |
| 5 | [Config heals itself](05-config-heals-itself.md) | Auto-sync + auto-doctor via LaunchAgents | `dotfiles doctor --fix` |
| 6 | [Stay safe from damage](06-stay-safe-from-damage.md) | Deletion protection, git-safe, secret scanning | `dotfiles audit` |
| 7 | [Git workflow helpers](07-git-workflow-helpers.md) | PR, hotfix, review scripts | `pr`, `hotfix`, `review` |
| 8 | [Time saved by automation](08-time-saved-by-automation.md) | Runs, time saved, streak | `dotfiles stats` |
| 9 | [Run AI coding agents on a local model](09-run-local-models-fast.md) | Local LLM fallback for agent loops | `dotfiles doctor --module local-llm` |
| 10 | [Add your company's config without forking](10-fork-for-your-company.md) | Signed, pinned company plugin (`dotfiles plugin add`) | `dotfiles apply` |

## Metric and Tests lines

Each story names how we know it works:

- **`**Metric:**`** names one row of [docs/metrics.md](../metrics.md#metrics):
  an outcome that users create, such as runs, drift, or time saved. A test
  count may follow only after `Guard:`.
- **`**Tests:**`** names the test files. Each story with a hermetic e2e has a
  test named `USNN e2e: …` in `tests/e2e/` (happy and error case); `make e2e`
  runs them in a sandboxed scratch HOME. US07 and US09 use unit bats only:
  their commands need GitHub or a local model.

`tests/user-stories.bats` fails when a Metric line names no metrics row, when
a Tests line names a missing file, or when an e2e test has no story ID.

## Ownership Boundary

| What | Owner |
|------|-------|
| Shell, git, macOS, SSH, editor, terminal config | **dotfiles** |
| Agent config (CLAUDE.md, MCP, skills, rules) | **agentbrew** |
| Orchestrator, personas, pipelines | **minsky** |

## Agent workflow acceptance

Every story and source-owned workflow inherits these requirements. Claude
Code and ChatGPT Work/Codex use the same CLI action handlers. Discover actions
with `dotfiles actions --json`; do not keep another command list. A terminal-only
action retains its reason and the command to run. Host-specific controls may
differ, but the result, confirmation rules, and local data owner stay the same.

Before context-dependent agent work, inspect the configured shared `memory`
MCP. Use `get_bootstrap_profile` and semantic `memory_search` for the repo and
task. When memory is configured but unavailable, name the failed tool and
report **shared memory unavailable**. Do not silently skip recall or claim
that a context-dependent workflow is ready. Restore it through
`agentbrew memory doctor` and the fix it reports. Deterministic local CLI
actions can still run; they do not require a model or upload business data.
When memory is deliberately unconfigured, state that scope before proceeding.

At completion, store only reusable, non-sensitive decisions through the
configured memory session tool. Do not copy OAuth sessions, credentials,
account privacy choices, schedules, or private records between hosts. Project
memory ingestion is separate from live shared recall; an ingestion warning
does not prove that recall is unavailable.

Acceptance uses synthetic inputs: equivalent CLI results on both hosts, an
explicit missing-memory result, and unchanged owner files. The existing
`tests/user-stories.bats` checker enumerates numbered stories, command sources
from `Agentfile.yaml`, and repo-owned skill sources. Missing host,
memory, or regression acceptance fails the gate. Mutation fixtures add a new
story and a new command source without acceptance and must be rejected.

A command source may be a directory or one `.md` file. An individual file
imports only that workflow; sibling files remain outside its acceptance scope.
