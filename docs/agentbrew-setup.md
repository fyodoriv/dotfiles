# Agentbrew Setup and Recovery

Agentbrew owns AI agent configuration: MCP servers, skills, rules, commands,
and generated agent files. Dotfiles owns the declaration in
[`Agentfile.yaml`](../Agentfile.yaml), the shell environment that exposes AI
tools, and doctor checks that verify the sync is healthy.

Use this guide when onboarding a teammate, enabling AI tooling on a new Mac, or
recovering from an `agentbrew sync` failure.

## What Gets Managed

| Source | Owner | Target |
|--------|-------|--------|
| `Agentfile.yaml` | dotfiles | Declarative list of MCP servers, skills, sources, and shared rules |
| `config/agentfile-owner-rules.yaml` | dotfiles | The owner's personal workflow rules (closing "Needed from you" line, memory-MCP calls, approved-family delivery, deprecated-agent notes). `dotfiles apply` merges it into `~/.config/agentbrew/Agentfile.yaml` only when `owner_machine` is true (or `DOTFILES_OWNER_MACHINE=true`), so a new user's agents get only the general rules in `Agentfile.yaml`. The sync script and the `agentbrew.global_agentfile_in_sync` doctor check both get this layer from `lib/agentfile-layers.sh`, so they cannot drift. |
| `~/.config/agentbrew/state.yaml` | agentbrew | Local registry of installed items and detected agents |
| `~/.claude/` | agentbrew or the agent | Generated agent config; do not edit by hand |
| `~/.zshenv.secrets` | you | Local tokens used by MCP servers |
| `~/.config/agentbrew/hooks-overlay/manifest.yaml` | you, plus dotfiles | Per-machine hook overlay. Your `disabled:` list and comments stay. `dotfiles apply` only adds missing opt-in hooks to `enabled:`, through `dot_config/agentbrew/hooks-overlay/modify_manifest.yaml.tmpl`. It adds the owner-workflow hooks (`gh-pr-body-requires-docs`, `perf-task-review`, `poll-loop-hint`, `usage-tip`, and others) only when `owner_machine` is true, so a new user gets none. List a hook under `disabled:` to opt out on one machine. |

### Agent time skills

agentbrew's perf hooks are on by default, so `dotfiles apply` needs no hook
overlay change for them. The two skills that read the perf data are not
default on a machine with an Agentfile, so `Agentfile.yaml` lists them under
`skills:`:

- `perf-review` (agentbrew): reads `agent-perf.mjs report` and turns real
  speedups into tasks.
- `session-report` (official plugin): tokens, cache, and active hours. The
  checkup runs its analyzer with `--json --since 7d` and reads only the
  `overall` totals, never the prompt list.

Check them with `ls ~/.claude/skills | rg 'session-report|perf-review'`.
README "Agent time metrics" explains how to read the numbers.

If generated config looks wrong, update `Agentfile.yaml` or agentbrew state and
sync again. Do not patch generated files directly; the next sync will overwrite
them.

## First-Time Setup

1. **Install dotfiles with AI tooling enabled.**

   During `chezmoi init`, answer `true` for `use_ai_tools`. To enable it later:

   ```bash
   $EDITOR ~/.config/chezmoi/chezmoi.yaml
   dotfiles apply
   ```

   Open a new terminal so `~/.zshrc.ai-tools` and `~/.zshenv` are loaded.

2. **Install agentbrew.**

   If your team already has a local checkout at `~/apps/agentbrew`, dotfiles can
   use that checkout during `dotfiles apply`. For normal teammate setup, install
   the CLI:

   ```bash
   npm install -g agentbrew
   agentbrew init
   ```

   Dotfiles also ships a real `bin/agentbrew` shim for machines with a local
   checkout at `~/apps/agentbrew` or `~/apps/tooling/agentbrew`; it works in
   non-interactive shells and launch agents, not just interactive zsh.
   `agentbrew init` detects installed agents such as Claude Code and Codex
   config directories.

3. **Configure MCP credentials.**

   Run the guided setup for every MCP server that needs credentials:

   ```bash
   agentbrew setup
   # or target one server:
   agentbrew setup atlassian
   agentbrew setup jenkins
   ```

   The wizard explains where to create each token and writes exports to
   `~/.zshenv.secrets`. You can also copy
   [`home/zshenv.secrets.example`](../home/zshenv.secrets.example) and fill in
   only the servers you use.

4. **Sync the canonical Agentfile.**

   ```bash
   dotfiles apply
   ```

   The lifecycle script merges `~/apps/dotfiles/Agentfile.yaml` plus any
   configured overlay Agentfile into `~/.config/agentbrew/Agentfile.yaml`, then
   runs `agentbrew sync --agentfile ~/.config/agentbrew/Agentfile.yaml` when the
   installed `agentbrew` supports `agentfile merge`. Older agentbrew releases
   fall back to syncing the base Agentfile first and the overlay Agentfile with
   `--no-prune`. Merge or sync failure is non-fatal so shell and git setup can
   still finish.

5. **Verify health.**

   ```bash
   agentbrew status
   dotfiles doctor --module agentbrew
   ```

   `agentbrew status` shows drift and generated-config health. The dotfiles
   doctor module checks that agentbrew is available, state exists, the global
   Agentfile was generated, the global Agentfile still matches the
   dotfiles/overlay merge when the installed CLI can compute it, and registered
   MCP servers have the required env vars.

## Credential Prerequisites

The current dotfiles Agentfile installs MCP servers that may need these local
credentials:

| Server | Required values | Setup command |
|--------|-----------------|---------------|
| Atlassian | `JIRA_URL`, `JIRA_USERNAME`, `JIRA_API_TOKEN` | `agentbrew setup atlassian` |
| Jenkins | `JENKINS_URL`, `JENKINS_USER`, `JENKINS_API_TOKEN` | `agentbrew setup jenkins` |
| Google Drive | OAuth browser approval for the local MCP checkout | Follow the Google-Drive MCP setup prompt |

Store secrets only in `~/.zshenv.secrets` or a secret manager. Never commit
tokens to `Agentfile.yaml`, generated agent config, docs, or tests.

## Recovery Playbook

### `agentbrew sync` Fails During `dotfiles apply`

Run the sync directly so you can see the full error:

```bash
dotfiles apply
agentbrew status
dotfiles doctor --module agentbrew
```

If `agentbrew` is not on `PATH`, first make sure dotfiles' `bin/` directory is
on `PATH` and that a local checkout exists at `~/apps/agentbrew` or
`~/apps/tooling/agentbrew`. The shim should make this work:

```bash
command -v agentbrew
agentbrew status
```

If there is no local checkout, install the packaged CLI with
`npm install -g agentbrew`.

After fixing the CLI or manifest error, rerun `dotfiles apply` so chezmoi and
agentbrew agree about the generated state.

### MCP Server Reports Missing Credentials

Check which credential is missing, then run the targeted setup wizard:

```bash
dotfiles doctor --module agentbrew
agentbrew setup <server-name>
source ~/.zshenv
dotfiles apply
```

Use `home/zshenv.secrets.example` as the field list when pairing with a
teammate. Keep the actual token values local to that user's machine.

### Generated Config Keeps Drifting

Generated files under agent directories are outputs, not source. Rebuild them
from agentbrew instead of editing them:

```bash
agentbrew status --fix
dotfiles apply
dotfiles doctor --module agentbrew
```

If `~/.config/agentbrew/state.yaml` appears corrupt after an interrupted sync,
back it up before rebuilding:

```bash
cp ~/.config/agentbrew/state.yaml ~/.config/agentbrew/state.yaml.bak
agentbrew init
dotfiles apply
```

Do not delete generated agent directories as a first step. They may contain
agent-owned preferences outside the agentbrew-managed sections.

## Team Rollout Checklist

- Enable `use_ai_tools: true` only for teammates who want AI agent integration.
- Run `agentbrew init` before the first `agentbrew sync`.
- Run `agentbrew setup` for credential-bearing MCP servers.
- Verify with `agentbrew status` and `dotfiles doctor --module agentbrew`.
- Keep all shared agent changes in `Agentfile.yaml`; never copy generated files
  between machines.
