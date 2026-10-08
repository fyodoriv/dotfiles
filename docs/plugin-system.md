# Tooling-app Plugin System

**Status:** Draft (proposed 2026-05-15) · **Owner:** dotfiles + agentbrew · **Branch:** `feat/tooling-plugins` (proposed)

> **Update 2026-10-08:** Devin support was removed from dotfiles. The
> Devin-only (`.devin/skills/`) contribution path, `devin_present`
> detection, and US-4 below are historical design notes. `dotfiles plugin`
> no longer registers Devin-only skill sources.

> A tooling-app at `~/apps/tooling/<name>/` (minsky, …) can ship
> per-target plugin folders: `plugins/dotfiles/` and/or `plugins/agentbrew/`.
> The user, with `dotfiles` and `agentbrew` already installed, runs **one
> command** — `dotfiles plugin add ~/apps/tooling/<name>` — and the tool's
> contributions to `dotfiles` (doctor checks, brewfile fragment, validate
> scripts) and `agentbrew` (skills, MCP servers, rules) are wired in,
> surfaced by `dotfiles-doctor`, and kept fresh on every `dotfiles apply`
> / `agentbrew sync`. One command also uninstalls or heals the wire-up.
> **Plugins live in source repos as symlinks** — editing
> `minsky/plugins/dotfiles/doctor/minsky/doctor.sh` flows to the user's
> machine on next sync; no re-install needed. By default the install
> step also auto-runs the relevant downstream syncs so doctor checks
> turn green immediately; `--no-sync` overrides.

## Motivation

We have multiple tooling repos (`minsky`, `agentbrew-<org>`,
`dotfiles-<org>`, future ones) that all want to contribute the same
kinds of things to a shared machine: doctor checks, brewfile lines,
agent skills, MCP server entries, shared rules. Today each one solves
this differently:

| Repo | How it gets installed | Owner of the lifecycle |
|------|----------------------|------------------------|
| `dotfiles-<org>` | `EXTRA_OVERLAY_ROOT` env var → chezmoi lifecycle picks it up | dotfiles lifecycle script |
| `agentbrew-<org>` | `agentbrew team set <git-url>` clones, caches, layers catalog | agentbrew CLI |
| `minsky` | `install.sh` symlinks `skill-plugins/` into agent dirs, deps install | minsky's own script |


Three mechanisms, three lifecycles, three uninstall paths, zero shared
doctor coverage. A new contributor can't predict which command sets
up which integration; an existing user can't easily uninstall just
minsky without touching the rest.

This spec defines **one** plugin contract that any tooling-app can
satisfy, and **one** lifecycle (`add` / `remove` / `heal` / `list`)
that the user runs from any side.

Secondary motivation: **Devin should be optional**. Today every tool
forces `.devin/` skills or `~/.config/devin/` configuration regardless
of whether Devin is installed. The plugin system auto-detects the
Devin CLI and skips Devin-only contributions when it's absent.

## User Stories

These are the tests. Each is a `bats` file under `tests/plugin/`.

### US-1 — Install a plugin from a tooling repo

> *As a user who already runs `dotfiles` + `agentbrew`,
> when I run `dotfiles plugin add ~/apps/experiments/minsky`,
> then minsky's `plugin/` contributions are symlinked into the right
> locations under `~/.config/dotfiles/plugins/`, `~/.config/agentbrew/`,
> and `~/.*/skills/`,
> and `dotfiles-doctor` shows minsky-specific checks (`minsky.*`) all passing,
> and `agentbrew status` shows minsky-provided MCP servers + skills registered.*

`tests/plugin/install.bats` (proposed):
- `dotfiles plugin add` on a fixture repo with a valid `plugin/manifest.yaml` creates expected symlinks
- doctor module symlinked under `~/.config/dotfiles/plugins/<name>/modules/<name>/doctor.sh`
- agentbrew skill source registered in `state.yaml`
- agentbrew sync runs once at the end, MCP entries land in claude.json (via mcpm) and devin config (if Devin detected)
- `dotfiles plugin list` shows `<name>: installed` with the source path

### US-2 — Uninstall a plugin

> *As a user with minsky installed via the plugin system,
> when I run `dotfiles plugin remove minsky`,
> then every symlink the install step created is removed,
> and minsky's catalog entries are removed from `state.yaml`,
> and `dotfiles-doctor` no longer shows minsky checks,
> and `agentbrew status` no longer lists minsky MCPs/skills,
> and the source repo at `~/apps/experiments/minsky` is left untouched.*

`tests/plugin/uninstall.bats` (proposed):
- After install, run remove
- Verify every symlink/state entry created during install is gone
- Verify source repo is untouched (file count + content hashes match pre-install)
- Verify `dotfiles plugin list` no longer lists the plugin

### US-3 — Heal a broken plugin

> *As a user whose plugin install got partially broken (e.g. a symlink
> was deleted, a doctor module got out of date, a state.yaml entry was
> wiped by an out-of-band sync),
> when I run `dotfiles plugin heal minsky` (or just re-run `dotfiles plugin add`),
> then every missing/incorrect symlink is restored,
> and missing catalog entries are re-added,
> and `dotfiles-doctor` passes again.*

`tests/plugin/heal.bats` (proposed):
- After install, delete a doctor symlink + remove a state.yaml entry
- Run `dotfiles plugin heal <name>`
- Verify symlink restored + state entry back
- Re-run is a no-op (`heal` is idempotent — `0 fixed` on the second call)

### US-4 — Optional Devin setup

> *As a user who doesn't use Devin (Devin CLI not installed),
> when `dotfiles apply` runs,
> then nothing under `~/.config/devin/` is touched,
> and `agentbrew sync` skips Devin in the carve-out list,
> and `dotfiles-doctor` skips Devin-related checks rather than failing,
> and installing a plugin that contributes Devin-only content (e.g.
> Devin-specific content) silently skips the Devin portion.*

`tests/plugin/optional-devin.bats` (proposed):
- Mock `command -v devin` → not found
- Run `dotfiles apply` (or just the agentbrew sync portion) — assert no writes to `~/.config/devin/`
- Run `dotfiles-doctor` — Devin-related checks show ⊘ (skipped), not ✗ (failed)
- Install a fixture plugin whose `manifest.yaml` declares a `.devin/skills/` source — assert the install message says "Devin-only contributions skipped (Devin CLI not installed)"

## Design

### Plugin layout — target-explicit + convention hybrid

A plugin's contributions live under `<tool-repo>/plugins/<target>/`,
one folder per host tool. Each folder has its **own** `manifest.yaml`
so the contributions to dotfiles and the contributions to agentbrew
are independently scoped, installable, and uninstallable. You can ship
just one of them.

```
<tool-repo>/
└── plugins/
    ├── dotfiles/                      ← contributions to dotfiles (optional folder)
    │   ├── manifest.yaml              ← REQUIRED if folder present. name, version, opt-outs.
    │   ├── doctor/<module>/doctor.sh  ← each subfolder = a dotfiles doctor module
    │   ├── validate/*.sh              ← each `*.sh` = a dotfiles validate script
    │   ├── brewfile-fragment          ← appended to the dotfiles Brewfile
    │   ├── shell-fragment.sh          ← sourced from zshrc.ai-tools
    │   └── .devin/                    ← anything Devin-only — skipped when Devin CLI is absent
    │       └── skills/
    │
    └── agentbrew/                     ← contributions to agentbrew (optional folder)
        ├── manifest.yaml              ← REQUIRED if folder present.
        ├── skills/                    ← agentbrew skillSourceDirs entry
        ├── mcp/*.yaml                 ← agentbrew catalog overlay entries (same shape as catalog.yaml)
        ├── agentfile-fragment.yaml    ← MCP / skill names to add to global Agentfile
        ├── rules-fragment.md          ← markdown appended to shared-rules.md, marker-bounded
        └── .devin/                    ← Devin-only — skipped when CLI absent
            └── skills/
```

Why target-explicit instead of one generic `plugin/`:
- A tool can ship just dotfiles contributions (no agentbrew) without
  having an empty `agentbrew/` folder confuse the install step.
- Independent opt-outs: `dotfiles plugin add --skip-agentbrew <path>`
  ignores the `plugins/agentbrew/` folder entirely.
- Each manifest scopes to its own target. No "is this skill folder for
  agentbrew or dotfiles?" ambiguity.
- Discovery is `[ -d plugins/dotfiles ]` / `[ -d plugins/agentbrew ]`
  — trivial.

The presence of a subfolder under `plugins/<target>/` is the contract
for *what* gets contributed. If `plugins/dotfiles/doctor/` exists, its
modules get wired up; if not, that contribution type is absent. The
per-target manifest covers metadata + opt-outs (e.g. "skip the
brewfile fragment on Linux").

### `manifest.yaml` schema (per target)

`plugins/dotfiles/manifest.yaml`:

```yaml
schemaVersion: 1
name: minsky                          # MUST match the tool repo directory name
version: "1.0.0"                     # Plugin contract semver (bump on breaking changes)
description: "Minsky's dotfiles contributions — doctor checks + shell fragment"

# OPTIONAL: hook scripts that run during the lifecycle. Each receives
# the plugin folder (plugins/dotfiles) as $1 and the install-state dir as $2.
hooks:
  preInstall:  ./hooks/pre-install
  postInstall: ./hooks/post-install
  preRemove:   ./hooks/pre-remove
  postRemove:  ./hooks/post-remove

# OPTIONAL: per-contribution gates. Defaults to `auto` (discover by folder presence).
# Set to `false` to opt out of a contribution type even if its folder exists.
contributions:
  doctor:    auto
  validate:  auto
  brewfile:  auto
  shell:     auto
  devin:     auto                    # `auto` here = active only when Devin CLI present
```

`plugins/agentbrew/manifest.yaml`:

```yaml
schemaVersion: 1
name: minsky
version: "1.0.0"
description: "Minsky's agentbrew contributions — orchestrator skills + MCP servers"

contributions:
  skills:    auto
  mcp:       auto
  agentfile: auto
  rules:     auto
  devin:     auto
```

The two manifests are independent on purpose. A tool can ship one or
both. They share the `name` (which identifies the plugin) and the
`version` (when both are present, they should match — a check during
install warns if they diverge).

### Lifecycle commands

The CLI surface is intentionally small:

```
dotfiles plugin add <path>          install (idempotent)
dotfiles plugin remove <name>       uninstall
dotfiles plugin heal <name>         restore drift
dotfiles plugin list                show installed plugins + status
dotfiles plugin status <name>       per-plugin health (used by doctor)
```

All commands are also exposed under `agentbrew plugin` as an alias —
the same helper backs both so users discover from either side. Sister
tools (minsky, etc.) may also ship a thin wrapper:

```
minsky plugin install   →  exec dotfiles plugin add "$MINSKY_ROOT"
minsky plugin uninstall →  exec dotfiles plugin remove minsky
minsky plugin heal      →  exec dotfiles plugin heal minsky
```

### Auto-sync — defaults that make `add`/`remove`/`heal` feel one-shot

**Goal: the user runs one command and the loop closes — doctor turns
green, claude.json has the new MCP, `dotfiles-doctor` runs clean.**
Auto-run behavior:

| Command | Auto-runs after the core action | Override |
|---------|--------------------------------|----------|
| `dotfiles plugin add <path>` | `dotfiles apply` (overlay + agentbrew sync via lifecycle) + `dotfiles-doctor` on the new plugin's modules | `--no-sync` (skip both), `--no-doctor` (skip just doctor) |
| `dotfiles plugin remove <name>` | `dotfiles apply` + `dotfiles-doctor` (verifies cleanup) | `--no-sync` |
| `dotfiles plugin heal <name>` | `dotfiles-doctor` only (sync already happens elsewhere) | `--no-doctor` |
| `dotfiles plugin list` | nothing | n/a |
| `dotfiles plugin status` | nothing (it IS the report) | n/a |

Symmetrically across the existing CLI:
- `agentbrew sync` defaults to *also* layering all detected plugins'
  `plugins/agentbrew/` contributions (no separate `agentbrew plugin
  sync` needed). Override: `--no-plugins`.
- `dotfiles apply` defaults to running through all installed plugins.
  Override: `--no-plugins`.
- `dotfiles-doctor` defaults to running plugin-contributed doctor
  modules alongside core modules. Override: `--no-plugins`.

Rationale: today's UX requires the user to remember `dotfiles apply
&& agentbrew sync && dotfiles-doctor` after any change. With the
plugin system in place, one command per lifecycle event closes the
loop, and overrides exist for the operator who wants to inspect
intermediate state.

### Install: what symlinks land where

For each detected subfolder under `<plugin>/plugins/<target>/`, the install
step creates a symlink (or a state.yaml entry) under a plugin-scoped path
in the user's home so we can remove cleanly:

| Plugin path | Symlinked / written to | Notes |
|-------------|------------------------|-------|
| `plugins/dotfiles/doctor/<m>/doctor.sh` | `~/.config/dotfiles/plugins/<name>/modules/<m>/doctor.sh` | `dotfiles-doctor` auto-discovers `~/.config/dotfiles/plugins/*/modules/*/doctor.sh` |
| `plugins/dotfiles/validate/*.sh` | `~/.config/dotfiles/plugins/<name>/validate/*.sh` | `dotfiles-validate` ditto |
| `plugins/dotfiles/brewfile-fragment` | concat'd to `~/.local/share/dotfiles/plugins/<name>.Brewfile` | dotfiles brew lifecycle layers in these fragments |
| `plugins/dotfiles/shell-fragment.sh` | sourced from `zshrc.ai-tools` via `for f in ~/.config/dotfiles/plugins/*/shell-fragment.sh; do source "$f"; done` | shell startup contributions |
| `plugins/dotfiles/.devin/skills/*` | skipped if `command -v devin` fails | per US-4 |
| `plugins/agentbrew/skills/` | (state.yaml `skillSourceDirs` entry) | agentbrew already supports this |
| `plugins/agentbrew/mcp/*.yaml` | (state.yaml `pluginCatalogOverlays` entry — new) | new agentbrew API: list of additional catalog files to layer |
| `plugins/agentbrew/agentfile-fragment.yaml` | merged into the global Agentfile during plugin sync | new agentbrew API; tracked in install-state for clean removal |
| `plugins/agentbrew/rules-fragment.md` | appended to shared-rules.md inside `<!-- plugin:<name>:start --> … <!-- plugin:<name>:end -->` markers | replaceable, marker-bounded |
| `plugins/agentbrew/.devin/skills/*` | skipped if `command -v devin` fails | per US-4 |

### Install state — what we track to remove cleanly

Each install creates `~/.config/dotfiles/plugins/<name>/install-state.json`:

```json
{
  "name": "minsky",
  "sourcePath": "/Users/.../apps/experiments/minsky",
  "manifestSha": "abc123...",
  "installedAt": "2026-05-15T11:30:00Z",
  "symlinks": [
    "~/.config/dotfiles/plugins/minsky/modules/minsky/doctor.sh",
    "~/.config/dotfiles/plugins/minsky/validate/no-tmux-leak.sh"
  ],
  "stateYamlEntries": {
    "skillSourceDirs": ["minsky-skills"],
    "catalogOverlayPaths": ["/path/to/minsky/plugin/mcp/"]
  },
  "rulesMarkerLines": [1234, 1267],
  "devinSkipped": true
}
```

`remove` reads this and reverses everything. `heal` re-runs install,
which is idempotent on existing symlinks and re-creates anything missing.

### Doctor integration

Two layers of checks land automatically:

1. **Per-plugin contributed checks** — whatever ships in `plugin/doctor/<m>/doctor.sh`.
   Surfaced as `<m>.*` checks (e.g. `minsky.orchestrator_running`).
2. **Plugin-system checks** — one per installed plugin, ships in
   `dotfiles/modules/plugins/doctor.sh`. Verifies every install-state
   symlink resolves + the manifest hash hasn't drifted from the source.
   Repair = `dotfiles plugin heal <name>`.

### Optional Devin (US-4) — auto-detect

The current dotfiles ownership table assumes Devin is always present.
With this change:

- Agentbrew's `mcp-sync.ts` reads `command -v devin` once at startup.
  Devin is added to the carve-out list only when present.
- `dotfiles-doctor` modules under `modules/devin/` (if any) gate on
  `command -v devin` and short-circuit to `skip` when absent.
- `home/zshrc.ai-tools` already gates `DEVIN_MODEL` exports behind
  `use_ai_tools` — extends to gate the export behind Devin presence
  too.
- Plugin manifests with `.devin/` content are auto-skipped (per US-4).

The detection is a one-liner — `command -v devin >/dev/null` — and
caches the result for the duration of a single `dotfiles apply` /
`agentbrew sync` invocation so multiple checks don't shell out
repeatedly.

## Non-goals

- **Cross-machine plugin registry.** Plugins are discovered from local
  source repos (`<tool-repo>/plugin/`). No central marketplace, no
  `dotfiles plugin search`. organization-internal sharing happens via the
  existing GHE remote + clone.
- **Version negotiation between plugin and host.** `schemaVersion: 1`
  is checked; mismatch errors out. No semver compatibility logic. Bump
  schema version when the contract changes, file a migration note.
- **Plugins contributing to other plugins.** A plugin extends `dotfiles`
  and `agentbrew`. It does not extend `minsky` to add a sub-plugin.
- **Web-installable plugins.** Sources are local paths; if a user wants
  a remote plugin they `git clone` first. (Mirrors how `agentbrew team
  set <url>` already works — that pattern stays for catalog overlays.)
- **Replacing the existing `EXTRA_OVERLAY_ROOT` mechanism.** That
  remains the single-machine-level org overlay. The plugin system is
  additive: per-tool, multiple plugins, run from any source.

## Migration plan

Phase 1 — land the mechanism (this RFC):
1. `dotfiles plugin add|remove|heal|list|status` ships in `dotfiles/bin/`
2. `plugin/manifest.yaml` schema documented; example plugin under
   `dotfiles/tests/fixtures/example-plugin/`
3. Bats test suite under `dotfiles/tests/plugin/` covers all 4 user stories
4. `agentbrew plugin <cmd>` alias added (calls the dotfiles helper)
5. `dotfiles-doctor` gains a `plugins/` module verifying install-state hashes

Phase 2 — migrate `minsky`:
6. Create `minsky/plugins/dotfiles/` (manifest + doctor module) and
   `minsky/plugins/agentbrew/` (manifest + skills + mcp + agentfile-fragment)
7. Minsky's existing `skill-plugins/orchestrator/` becomes
   `minsky/plugins/agentbrew/skills/orchestrator/` (preserve git history
   via `git mv`)
8. Minsky's `install.sh` becomes a thin wrapper: `dotfiles plugin add "$MINSKY_DIR"`
9. Any minsky-related doctor checks currently in dotfiles/dotfiles-<org>
   move into `minsky/plugins/dotfiles/doctor/minsky/`

Phase 3 — Devin opt-out:
10. Agentbrew + dotfiles auto-detect Devin (per US-4)
11. Doctor checks for Devin gate on detection
12. Update the dotfiles `Ownership Boundary` table in AGENTS.md to note
    `~/.config/devin/` is owned by agentbrew only when Devin is detected

## Settled policy decisions

(These were open during initial drafting; decisions made 2026-05-15.)

- **Plugin install logs** → `~/.local/share/dotfiles/logs/plugins/<name>.log`
  (subfolder per plugin under the existing `logs/` directory; predictable
  for tailing, clean when N plugins are installed). The `add` / `remove` /
  `heal` commands write structured entries with timestamps.
- **Auto-sync** → `dotfiles plugin add` / `remove` auto-run `dotfiles
  apply` + `dotfiles-doctor` by default. `--no-sync` skips both;
  `--no-doctor` skips just doctor. `heal` runs only doctor by default
  (sync already happens via the lifecycle elsewhere). Captured in the
  Auto-sync table above.
- **MCP name conflicts** → install **refuses and fails loud** when a
  plugin's `mcp/<name>.yaml` collides with an already-registered MCP
  server (from the catalog, another plugin, or a state.yaml entry).
  The error message names both the existing source and the conflicting
  plugin, and tells the operator to rename one before re-installing.
  Rationale: silent last-wins makes audit trails fragile and lets a
  forgotten plugin override a deliberately-configured server. Forcing
  a rename keeps the surface honest.

## Test plan summary

| Bats file | Covers user story | Key assertions |
|-----------|------------------|----------------|
| `tests/plugin/install.bats` | US-1 | symlinks land, state.yaml updated, doctor green, sync ran |
| `tests/plugin/uninstall.bats` | US-2 | install-state inverse runs, source untouched, list empty |
| `tests/plugin/heal.bats` | US-3 | partial breakage detected, repaired idempotently |
| `tests/plugin/manifest-validation.bats` | (cross-cutting) | bad schemaVersion / missing name / bad path errors cleanly |
| `tests/plugin/conflict-mcp.bats` | (open question) | two plugins with same MCP name → warn + last-wins |

## References

- Industry research: see commit message / scratch (VS Code `contributes`,
  GitHub Actions `action.yml`, asdf `bin/` convention, Neovim lazy.nvim
  spec, Homebrew taps, Helm Chart.yaml, Oh My Zsh `.plugin.zsh`)
- Existing primitives reused: `EXTRA_DOCTOR_DIR`, `EXTRA_AGENTFILE`,
  `agentbrew` `skillSourceDirs`, `agentbrew team set`
- Existing ownership boundary: dotfiles `AGENTS.md`, agentbrew `AGENTS.md`
