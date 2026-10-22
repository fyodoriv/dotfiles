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
| `~/.config/dotfiles/Agentfile.local.yaml` | you | Optional, untracked Agentfile layer for this Mac only, for example an extra MCP server. See [Add an MCP server on one Mac](#add-an-mcp-server-on-one-mac). |
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

After an `Agentfile.yaml` edit, `make check` parses the file as YAML
(`tests/agentfile.bats`, with `yq` or the system Ruby) and runs only the tests
that read it. It skips the install e2e: the e2e never runs agentbrew, so it
never reads the Agentfile.

## Add an MCP server on one Mac

Use the local layer when one Mac needs an MCP server (or a skill or rule)
that the shared `Agentfile.yaml` does not list. For example, `figma` was
removed from `Agentfile.yaml` on 2026-10-13 because it was unused, but one
Mac may still want it.

1. Create `~/.config/dotfiles/Agentfile.local.yaml` (or
   `$XDG_CONFIG_HOME/dotfiles/Agentfile.local.yaml`). It is a normal
   Agentfile, outside the repo, and never committed:

   ```yaml
   mcp:
     - figma
   ```

2. Run `dotfiles apply`. The sync merges the layers in this order: the
   shared `Agentfile.yaml`, plugin Agentfiles, the owner rules (owner
   machines only), this local file, and this Mac's model override. For
   list keys (`mcp:`, `skills:`, `sources:`, and so on), each layer adds
   its entries, and an MCP entry with the same name replaces the earlier
   one.
   - The local file may not hold `hooks:`, also not through a YAML anchor
     or merge key (`<<: *base`). In agentbrew's merge, a hook replaces
     every earlier hook with the same event and matcher, so one local
     `Bash` hook would drop the shared `block-dangerous-git.sh`.
   - Before the merge, agentbrew reads the file alone with its own parser.
     A file it cannot read (bad YAML, a duplicate key, an unknown `!tag`,
     a second `---` document) or one whose result has hooks is skipped
     with a warning that names the problem. The other layers still sync.
     If the check itself cannot run (no temp file), the file is skipped
     too: it is never trusted unchecked.
   - With mikefarah `yq` installed (the Brewfile has it), apply also warns
     about a list key written as a single value (for example
     `mcp: figma`; write `mcp:` then `- figma`), a `rules:` that is not
     text, and a key agentbrew's merge does not use. agentbrew ignores
     those keys.
3. Check: `dotfiles doctor --module agentbrew`.
   `agentbrew.local_agentfile_valid` names the first problem in the local
   file, and says "checked with yq only" when the doctor finds no agentbrew
   that can merge. The `agentbrew.global_agentfile_in_sync` check builds the same list from
   `lib/agentfile-layers.sh`, so it passes. An entry added by hand to
   `~/.config/agentbrew/Agentfile.yaml` still fails it: that file is
   generated, and the next apply overwrites it.

`dotfiles apply --if-changed` (and plain `dotfiles`) also run the full apply
after you edit the local file, because the last-apply record includes its
hash (`lib/apply-state.sh`). To remove the server, delete its line (or the
file) and run `dotfiles apply` again.

Rules for what goes where:

- Every machine needs it, and it works for a fresh user without company
  login or network: add it to `Agentfile.yaml`.
- A company or team needs it (company login, internal network, paid
  entitlement): add it to the company plugin's Agentfile
  (`contributes.agentbrew`, [plugins.md](plugins.md)), never to
  `Agentfile.yaml`.
- Only this Mac needs it: use the local file. It can name servers that need
  a login, because it never leaves the Mac. Keep tokens in
  `~/.zshenv.secrets`, not in the file.

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
