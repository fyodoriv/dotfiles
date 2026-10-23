# Company plugins

This is the only page that describes how a company adds its private
settings, checks, and tools on top of dotfiles. The design and its history
are in issue #145.

A company **plugin** is a git repo with `dotfiles-plugin.yaml` at its root.
The core installs it pinned and signed, and runs only what it declares.
Private data never goes into the public core.

The v1 overlay was removed; see [Migrating from the v1 overlay](#migrating-from-the-v1-overlay).

## Quick start

```sh
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
  agentbrew: agentbrew                # folder with Agentfile.yaml (MCP servers, skills, rules)
```

## Install, lock, and verify

| Command | What it does |
|---|---|
| `dotfiles plugin add <url>@<tag> [--signer <key>] [--yes]` | Clones the tag, checks the signature, validates the manifest and options, shows the capabilities, and asks once. It runs no plugin code. |
| `dotfiles plugin add --dev <path>` | Links a local checkout for authors. Not pinned; doctor warns on every run. |
| `dotfiles plugin update <name> [<tag>] [--yes] [--dry-run] [--unattended]` | Moves an installed plugin to another signed tag in place. Without a tag, it takes the newest tag that is newer than the installed one and signed by a trusted signer. `--dry-run` says what would change; `--unattended` never asks and exits 3 when a person must decide. `dotfiles upgrade` runs it for every pinned plugin. See [Update](#update). |
| `dotfiles plugin remove <name> [--yes]` | Unloads its LaunchAgents and deletes the checkout and the lock entry. It asks first; without a terminal it needs `--yes`. |
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

### Update

`dotfiles plugin update <name> [<tag>]` keeps the plugin working while it
moves to a new release. It never removes the plugin first.

1. It clones the lock's `source` into a staging folder beside the checkout.
2. It picks the tag: the one you name, or else the newest stable release
   (`vX.Y.Z` or `X.Y.Z`, nothing after it) that is newer than the locked
   `ref` by [semver](https://semver.org) order and that a trusted signer
   signed. Pre-releases (`v1.1.0-rc.1`) and other names (`wip`, `latest`)
   install only when you name them. It skips and names each newer release
   that is unsigned or signed by another key. No newer signed release: it
   prints "up to date" and changes nothing. If the locked `ref` is not a
   version, name the tag.
3. It checks the new tag as `add` does: SSH signature from a key trusted for
   this plugin, valid manifest and options, and the same plugin `name`.
4. Same capabilities as the approved version: no prompt. Changed
   capabilities: it shows them and asks once (a terminal or `--yes`).
5. It moves the old checkout aside, moves the new one in, rewrites the lock
   entry (commit, `tree_hash`, `capabilities_sha`, signer, ref, version),
   and runs the same check as `verify`. If that fails, the old checkout and
   lock come back and the command exits non-zero.

Any failed step, Ctrl-C, or `TERM` before the new checkout verifies leaves
the installed version and its lock as they were: an exit handler moves the
old checkout back and restores the lock. If it cannot, it keeps the staging
folder (with the old checkout) and prints its path. Every lock write goes to
a 0600 temp file in the same folder and then one rename, so the lock is
always the old one or the new one.

A crash with no exit handler (SIGKILL, a power cut) leaves a `.staging.*`
folder. Each one holds `owner.pid` (the run's PID and boot ID), and an
update's also holds `plugin.name`. The next `add`, `update`, `remove`,
`list`, or `verify` (but not a `--dry-run`) looks in the plugin home and beside each pinned checkout
for a folder whose run is gone (another boot, or the PID no longer runs):
- the checkout still matches the lock: the update had finished, so the old
  copy is deleted;
- otherwise the old checkout and its lock entry come back.

Until then the doctor check `plugins.staging_clean` names the folder.
Recovery messages go to stderr and never fail the command. When it cannot
tell whether a run is gone (an unknown boot ID, a sandbox that blocks the
check), it counts the run as live. It never touches a folder without
`owner.pid`, or anything beside a `--dev` link. A
named tag older than the installed one installs with a "downgrade" note;
without a tag, update never goes back. Naming the locked tag on a checkout
that no longer matches its lock reinstalls it, so the doctor fix for
`plugins.<name>.verified` is `dotfiles plugin update <name> <ref>`. A
`--dev` plugin is not pinned; update it with git in its folder. Then run
`dotfiles apply` to load new LaunchAgents, Brewfile entries, and Agentfile
layers. A new signer must be trusted first (`plugin trust`, see below).

`dotfiles upgrade` (the weekly LaunchAgent, after its `--yes` gate) runs
`dotfiles plugin update <name> --unattended` for every pinned plugin:
- a plugin with a newer stable signed release and the same capabilities
  moves to it, with every check above;
- a plugin whose capabilities changed is skipped, and the summary names it
  with the command to run (`dotfiles plugin update <name>`), because new
  capabilities need a person's approval;
- a newer release that failed its signature check is skipped and named
  with the reason; only when no trusted key signed it (after a key
  rotation, say) does the line suggest `dotfiles plugin trust`;
- a release it moves to says which newer, untrusted release it skipped;
- a checkout that changed on disk (commit, files, capabilities) is never
  replaced unattended (that would erase what changed in it): it is named
  and fails the run;
- after a key rotation (the installed release's signer revoked), it moves
  to the newest release a trusted key signed; with none, it fails and
  says to install one (`dotfiles plugin update <name> <tag>`);
- a failed update is named in the summary and fails the run (exit 1), as
  a failed topgrade step does; the other plugins still update;
- `--dev` links are left alone.

The summary ends with "Run dotfiles apply" when a plugin moved. The log
(`~/.local/share/dotfiles/logs/dotfiles-upgrade.log`, mode 0600) keeps
each plugin's full output, without any `user:token@` part of a URL.

`dotfiles upgrade --dry-run` lists the pending plugin updates (with
`dotfiles plugin update <name> --dry-run`) and changes nothing.

## Trust and signing

- A release ref must be an annotated tag signed with an SSH key.
- Trusted keys live in one file shared with agentbrew:
  `~/.config/agent-plugins/allowed_signers` (or
  `$AGENT_PLUGINS_ALLOWED_SIGNERS`), in git `gpg.ssh.allowedSignersFile`
  format. The principal is the plugin name, so a key trusted for one plugin
  cannot sign another.
- `git verify-tag` runs against a scratch file with only this plugin's keys,
  so the user's git config cannot widen trust.
- The check reads the tag object at exactly `refs/tags/<ref>`, and the
  checkout is that object's commit (`add` and `update` prove it). A name
  that looks like an object ID (40 or 64 hex digits) is refused, because
  git would read it as an ID and check some other, real signature. A tag
  object whose own name differs from `<ref>` (an old signed tag pushed
  under a new name) is refused too.
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
| Agentfile | `contributes.agentbrew/Agentfile.yaml` is merged into `~/.config/agentbrew/Agentfile.yaml` on apply, before `agentbrew sync`. It may add to the shared layer (hooks, MCP servers, skills), never take from it: see [Agentfile rules](#agentfile-rules). |
| Blocked software | `apps`, `casks`, `formulae` lists; the doctor check `plugins.<name>.blocked_software` fails while any is installed. |

### Agentfile rules

Apply merges the earlier layers (the shared Agentfile, then each plugin kept
so far) with and without the plugin, using the real agentbrew. It skips the
plugin's Agentfile, and says why, when the plugin would:

- **Replace or weaken a shared hook.** An earlier hook entry (compared
  whole) is gone, or a second copy of a shared hook command appears for the
  same event, under any matcher.
- **Turn off an agent.** `excludeAgents:` turns off all agentbrew sync for
  that agent, the shared hooks included.
- **Re-define a shared MCP server** under its name.
- **Set `recommended: true`.** That installs the whole recommended set.
- **Ship a command or agent with a shared name.** A `commands:` or
  `agents:` folder holds a `*.md` file named like one in a shared folder of
  that kind, in any letter case. For an agent, its front matter `name:`
  counts too. agentbrew keeps one file per name, and which copy wins
  depends on the order the folders first reached it, so the plugin's copy
  could replace the shared one. A name with non-ASCII letters cannot be
  compared, so it is refused too.
- **Make a local skill copy match a `skills:` entry.** A local `sources:`
  folder (of this plugin or an earlier one) holds a skill (`SKILL.md`,
  `skill.md`, or `DESIGN.md`, by folder name or front matter `name:`) that a
  `skills:` entry asks for, and it did not match before this plugin; or a
  source the plugin adds holds a second copy of such a skill (agentbrew
  would then ask which source to use).
  agentbrew installs a `skills:` name that has no catalog entry (a built-in
  skill) by searching every source, and a local source ranks before the
  built-in. A name only the plugin asks for counts when it is an agentbrew
  built-in, because agentbrew installs no other unknown name; when the
  built-in list cannot be found (no `AGENTBREW_DIR`, no agentbrew
  `dist/cli.js`, no checkout), every such name counts. A remote
  source cannot be read before the sync, so this rule does not cover it.

Without `agentfile merge` (older agentbrew), a stricter rule is read from
the files: any `hooks:`, `excludeAgents:`, or `recommended: true`, a file
that is not one map or uses a YAML merge key (`<<`), an entry for a shared
MCP server that is not written the same way, or a command, agent, or skill
name as above (folders as agentbrew reads them when it applies the file on
its own) skips it.

The one exception: `defaultModel`, `defaultEffort`, and `modelOverrides`
may change, because an overlay sets them on purpose
([model-configuration.md](model-configuration.md)).

The doctor check `agentbrew.plugin_agentfile_shared` finds agentbrew the way
apply does (PATH, then the checkout's `dist/cli.js`, then its `tsx`) and
names the plugin and what it would take. Give a plugin hook its own command,
and a plugin MCP server, command, agent, or skill its own name. To keep
people off an agent, use `blocked_software`.

## Core options

A plugin sets values only for options declared in
[`config/plugin-options.yaml`](../config/plugin-options.yaml). Booleans: the
last plugin in lock order wins. Lists: union.

| Option | Effect |
|---|---|
| `chrome.purpose_headed` | The purpose Chrome LaunchAgent runs without `--headless=new`. |
| `chrome.dock_guard` | Default `true`. `false` with `chrome.purpose_headed: true` removes `com.dotfiles.chrome-dock-guard` on apply and skips its doctor check. A headless purpose Chrome always keeps the guard. |
| `chrome.restore_session` | It starts with `--restore-last-session`. |
| `spotlight.exclude_worktrees` | Default true. False skips the agent-worktree Spotlight check. |
| `mas.skip_ids` | `dotfiles-mas-upgrade` never upgrades these App Store ids. |
| `brew.skip` | Removed from the core Brewfile; the doctor skips their `tool.<name>` checks. |

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

## Migrating from the v1 overlay

**Breaking change (issue #145, step 11b).** These were removed:
`EXTRA_OVERLAY_ROOT`, `EXTRA_DOCTOR_DIR`, `EXTRA_BREWFILE`,
`EXTRA_VALIDATE_DIR`, `EXTRA_AGENTFILE`, the chezmoi keys
`extra_overlay_root` / `extra_doctor_dir` / `extra_brewfile`, the older
tooling-app plugin system, and the `DOTFILES_PLUGINS_V2` gate (plugin
commands always work now). A leftover setting stops `dotfiles doctor`,
`validate`, and `apply` with one line that names it.

On the machine that has the old overlay:

1. `dotfiles plugin migrate <overlay dir>` writes `dotfiles-plugin.yaml.draft`
   (doctor `modules/`, `validate/`, `brewfile/Brewfile`, `hooks/`,
   `vscode/settings.json`, and `Agentfile.yaml` as `agentbrew: .`) and lists
   the files it could not map. `oss-readiness.env` keeps working from the
   plugin root.
2. Review the draft, rename it to `dotfiles-plugin.yaml`, commit, and sign a
   tag: `git tag -s v1.0.0 -m v1.0.0`.
3. `dotfiles plugin add <git-url or path>@v1.0.0 --signer "<public key>"`
   (or `dotfiles plugin add --dev <dir>` while you iterate).
4. Unset the `EXTRA_*` variables and delete the `extra_*` keys from
   `~/.config/chezmoi/chezmoi.yaml`, then `dotfiles apply`.

## Files

| File | Role |
|---|---|
| `lib/plugin.sh` | Lock, manifest validation, verify, overlay lookup |
| `lib/plugin-signers.sh` | Shared allowed-signers file, signed-tag check |
| `lib/plugin-capabilities.sh` | Capability checks and helpers |
| `lib/plugin-extensions.sh` | Extension points, options, lint |
| `lib/plugin-sandbox-runner.sh` | Child-process runner for plugin checks |
| `bin/dotfiles-plugin` | `dotfiles plugin …` commands |
| `bin/dotfiles-mcp-launch` | Secrets-by-reference launcher |
| `bin/dotfiles-leak`, `lib/leak-allow.sh` | Human-only bypass |
| `modules/plugins/doctor.sh` | Verified, lint, and blocked-software checks |
