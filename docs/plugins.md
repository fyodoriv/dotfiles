# Company plugins

This is the only page that describes how a company adds its private
settings, checks, and tools on top of dotfiles. The design and its history
are in issue #145.

A company **plugin** is a git repo with `dotfiles-plugin.yaml` at its root.
The core installs it pinned and signed, and runs only what it declares.
Private data never goes into the public core.

Preview: the plugin commands need `DOTFILES_PLUGINS_V2=1` until the next
major version removes the v1 overlay (see [Legacy v1 overlay](#legacy-v1-overlay)).

## Quick start

```sh
export DOTFILES_PLUGINS_V2=1
dotfiles plugin new acme                     # scaffold dotfiles-acme/
# edit dotfiles-acme/dotfiles-plugin.yaml, push it, then release:
git -C dotfiles-acme tag -s v1.0.0 -m v1.0.0 # SSH-signed annotated tag
dotfiles plugin add git@git.example.com:it/dotfiles-acme.git@v1.0.0 \
  --signer "$(cat release-key.pub)"
dotfiles apply
dotfiles doctor
```

## Manifest

Schema: [`config/dotfiles-plugin.schema.json`](../config/dotfiles-plugin.schema.json).
The keys `schema`, `name`, `version`, `requires_core`, `capabilities`, and
`contributes` match agentbrew's `agentbrew-plugin.yaml`. Unknown keys,
absolute paths, and `..` paths are refused.

```yaml
schema: 1
name: acme                    # [a-z0-9-], unique on the machine
version: 1.0.0
capabilities:                 # deny by default
  brew: {taps: [acme/private], casks: true}
  launchagents: [com.acme.*]
  defaults_write: [com.acme.*]
  network_hosts: [git.acme.example.com]
  hooks: [pre-push]
  shell_fragment: true
  sudo: false
  secrets: [keychain:acme-jira-token]   # names only, never values
contributes:
  doctor_modules: doctor      # doctor/<module>/doctor.sh (+ severity)
  validate: validate          # validate/*.sh
  brewfile: Brewfile
  launchagents: launchagents  # *.plist templates
  hooks: hooks                # hooks/<git hook name>
  settings: {vscode: settings/vscode.json}
  shell: shell/zshrc.zsh
  options: {chrome.restore_session: true, mas.skip_ids: ["123456789"]}
  blocked_software: blocked.yaml
  leak_patterns: leak-patterns.yaml   # reserved
  agentbrew: agentbrew                # reserved for agentbrew
```

## Install, lock, and verify

| Command | What it does |
|---|---|
| `dotfiles plugin add <url>@<tag> [--signer <key>] [--yes]` | Clones the tag, checks the signature, validates the manifest and options, shows the capabilities, and asks once. It runs no plugin code. |
| `dotfiles plugin add --dev <path>` | Links a local checkout for authors. Not pinned; doctor warns on every run. |
| `dotfiles plugin remove <name>` | Unloads its LaunchAgents and deletes the checkout and the lock entry. |
| `dotfiles plugin list` / `verify [<name>]` | Shows each plugin and re-checks it against the lock. |
| `dotfiles plugin trust <name> --signer <key> [--revoke]` | Adds or removes a trusted signer (needs a terminal or `--yes`). |
| `dotfiles plugin options` | Each core option, its value, who set it, and conflicts. |
| `dotfiles plugin lint <name>` | Exported secrets and unpinned packages. |
| `dotfiles plugin new <name>` / `migrate <v1 dir>` | Scaffold a plugin; draft a manifest from a v1 overlay. |

- Plugins install to `~/.local/share/dotfiles/plugins/<name>`, outside every
  tracked tree.
- `~/.config/dotfiles/plugins.lock` (mode 0600) records, for each plugin:
  source, ref, version, commit, `tree_hash`, `capabilities_sha`, `signer`,
  path, dev, and locked_at.
- A plugin runs only while it matches its lock: same commit and tree, no
  changed or added files, same capabilities, and a signer that is still
  trusted. Otherwise it is disabled, and the doctor check
  `plugins.<name>.verified` prints the difference. Folder names never make
  code trusted.

## Trust and signing

- A release ref must be an annotated tag signed with an SSH key.
- Trusted keys live in one file shared with agentbrew:
  `~/.config/agent-plugins/allowed_signers` (or
  `$AGENT_PLUGINS_ALLOWED_SIGNERS`), in git `gpg.ssh.allowedSignersFile`
  format. The principal is the plugin name, so a key trusted for one plugin
  cannot sign another.
- `git verify-tag` runs against a scratch file with only this plugin's keys,
  so the user's git config cannot widen trust.
- Key rotation: `plugin trust <name> --signer <new key>`, release a new tag,
  then `--revoke` the old key. A revoked signer disables the plugin.

## Capabilities

The core runs plugin steps only through helpers that check the manifest
first (`lib/plugin-capabilities.sh`). An undeclared step exits 3 with:

```
capability not declared: <kind> <value> (plugin <name>)
```

`sudo` also needs a person to confirm at a terminal.

## Extension points

Only verified plugins contribute (`lib/plugin-extensions.sh`).

| Point | Rule |
|---|---|
| Doctor modules, validate scripts | Run in a child process: cleaned environment (no `DOTFILES_*`, no tokens), the plugin root as the working folder, and a timeout (`DOTFILES_PLUGIN_TIMEOUT`, default 60 s). Ids show as `<plugin>/<id>`. Fix commands never run. |
| Brewfile | A separate `brew bundle` pass after the core. Taps must be declared; casks need `brew.casks`. A failure prints `unreachable (plugin <name>)`. |
| LaunchAgents | The core renders templates (`@HOME@`, `@PLUGIN_DIR@`), checks each `Label`, installs, and reloads only on change. Plugins never edit core plists. |
| Settings (VS Code) | Deep merge, later wins: core default < plugin < user (`~/.config/dotfiles/settings/vscode.user.json`) < a plugin's `_force`. Conflicts show as doctor warnings. |
| Shell | One generated loader (`~/.local/state/dotfiles/plugin-shell.zsh`), sourced by `home/zshrc` before `~/.zshrc.local`. Needs `shell_fragment: true`. |
| Git hooks | The core pre-commit and pre-push run the plugin's `hooks/<name>` (declared in `capabilities.hooks`) after the leak gates, then the repo-local hook. |
| Blocked software | `apps`, `casks`, `formulae` lists; the doctor check `plugins.<name>.blocked_software` fails while any is installed. |

## Core options

A plugin sets values only for options declared in
[`config/plugin-options.yaml`](../config/plugin-options.yaml). Booleans: the
last plugin in lock order wins. Lists: union.

| Option | Effect |
|---|---|
| `chrome.purpose_headed` | The purpose Chrome LaunchAgent runs without `--headless=new`. |
| `chrome.restore_session` | It starts with `--restore-last-session`. |
| `spotlight.exclude_worktrees` | Default true. False skips the agent-worktree Spotlight check. |
| `mas.skip_ids` | `dotfiles-mas-upgrade` never upgrades these App Store ids. |
| `brew.skip` | Removed from the core Brewfile. |

Rule of thumb: if a fresh external user could use it without company
identity, network, or entitlement, it belongs in the core as an option. The
plugin passes data only. For example, an endpoint-agent dialog healer reads
known dialog titles from a plugin `heal.env` instead of the plugin shipping
its own healer.

## Secrets and supply chain

- Manifests name secrets; they never hold values.
- `dotfiles-mcp-launch --secret NAME=keychain:<item> [--ca-bundle <file>]
  [--path-minimal] -- <command>` resolves a secret only inside the process
  that needs it. It refuses `@latest` and unpinned `npx -y`.
- `plugins.<name>.lint` flags a shell fragment that exports a token from
  `security …`, and any `@latest` or unpinned `npx -y` in plugin files.

## Leak gates

- Pattern files are parsed as data, never sourced. With a plugin or overlay
  installed and no pattern loaded, pre-commit, pre-push, and the `gh` guard
  block. See [privacy-gates.md](privacy-gates.md) and [SECURITY.md](../SECURITY.md).
- `dotfiles-sync` never pushes to a public remote without a person at a
  terminal; it writes `~/.local/state/dotfiles/sync-needs-review` instead.
- The only bypass is `dotfiles leak allow --once [<sha>]`, run by a person in
  a terminal: one blocked push (with a sha) or one blocked `gh` write, within
  10 minutes.

## Authoring

`dotfiles plugin new <name>` creates a repo with the manifest, a
`.gitignore`, example doctor and validate code, `tests/plugin.bats` (schema,
options, and lint against a core checkout in `DOTFILES_CORE`), and a CI
workflow (those tests, shellcheck, gitleaks).

## Legacy v1 overlay

Until the next major version, a v1 overlay still works when set explicitly:
`EXTRA_OVERLAY_ROOT=<dir>` or the chezmoi key `extra_overlay_root`. It reads
`modules/`, `validate/`, `brewfile/Brewfile`, `vscode/`, `hooks/`,
`Agentfile.yaml`, and `oss-readiness.env` from that folder. Convert one with
`dotfiles plugin migrate <dir>`. The older tooling-app plugin system
(`dotfiles plugin add <path>` without `DOTFILES_PLUGINS_V2`) is described in
[plugin-system.md](plugin-system.md) and goes away in the same release.

## Files

| File | Role |
|---|---|
| `lib/plugin.sh` | Lock, manifest validation, verify, overlay lookup |
| `lib/plugin-signers.sh` | Shared allowed-signers file, signed-tag check |
| `lib/plugin-capabilities.sh` | Capability checks and helpers |
| `lib/plugin-extensions.sh` | Extension points, options, lint |
| `lib/plugin-sandbox-runner.sh` | Child-process runner for plugin checks |
| `bin/dotfiles-plugin-v2` | `dotfiles plugin …` commands |
| `bin/dotfiles-mcp-launch` | Secrets-by-reference launcher |
| `bin/dotfiles-leak`, `lib/leak-allow.sh` | Human-only bypass |
| `modules/plugins/doctor.sh` | Verified, lint, and blocked-software checks |
