# Plan: Workspace folders doctor — iterate all declared workspaces

- **Task**: workspace-folder-doctor
- **Repo**: ~/apps/tooling/dotfiles
- **Author**: devin session 2026-06-12
- **Status**: implemented
- **Validated-by**: subagent_explore (plan-reviewer) on 2026-06-12

## Goal

`dotfiles doctor` (and an operator-facing `bin/dotfiles-workspace status`) become aware of every workspace folder on the machine — not just the repo it runs from. Discovery reads the shared tasks-md workspaces config when present and falls back to sentinel/structure scanning of `$WORKSPACE_SCAN_ROOTS` (default `~/apps`); the status command prints a per-workspace summary (repos, dirty lines, TASKS.md task counts) plus a cross-workspace rollup, and the new doctor module verifies discovery works and declared roots exist.

## Why

The operator keeps several named workspace folders under `~/apps/` (tooling, learning, docs, …) alongside many standalone sibling repos, and dotfiles has zero visibility into any of it: no check confirms declared workspaces exist, lists discovered repos, or flags drift. Multi-repo agents (minsky daemon, /next-task roaming) already make cross-repo decisions from this layout, so a host-level health view is the missing observability surface. The shared `~/.config/tasks-md/workspaces.{json,yaml}` config does **not** exist on this host yet (verified 2026-06-12), so per the task's Pivot this slice ships sentinel/fallback discovery first and defers cross-tool config integration.

## Scope (in)

- `lib/workspace-discovery.sh` (new, sourceable): `workspace_discover` prints `name<TAB>path` lines. Resolution order: (1) `~/.config/tasks-md/workspaces.json` via `jq` when present (object or `{name,path}` array shapes), (2) `~/.config/tasks-md/workspaces.yaml` minimal `name: path` line parse, (3) fallback scan of each colon-separated root in `$WORKSPACE_SCAN_ROOTS` (default `$HOME/apps`): an immediate child dir is a workspace when it contains a `.tasks-md-workspace` sentinel file OR ≥ 2 immediate-child `*/TASKS.md` files. Pure bash + glob loops (no `find` — repo shims redirect it; rule #1), `jq` only behind a `command -v` guard. Zero output + rc 0 when nothing is found.
- `bin/dotfiles-workspace` (new): `status [--workspace <name>]` + `--help`. For each discovered workspace: `=== Workspace: <name> (<root>) ===`; per immediate subdir with `.git`: `✓ <repo>  <dirty-line-count> dirty  +<ahead>` (ahead from `git rev-list --count @{u}..HEAD`, `-` when no upstream); per subdir with `TASKS.md`: unchecked `- [ ]` count and unblocked-P0/P1 estimate (unchecked minus `**Blocked**`/`**Blocked by**` lines — same heuristic the next-task roam scan uses; documented as an estimate); workspace `Total:` line; final `=== All workspaces: N workspaces, R repos, T tasks ===` rollup. `--workspace <name>` scopes to one; unknown name exits 2 with the discovered names listed.
- `modules/workspace/doctor.sh` (new, auto-discovered): `workspace.discovery_lib` (lib sources + function defined), `workspace.declared_roots_exist` (every config-declared path is a directory; vacuous pass when no config — fallback-discovered paths exist by construction), `workspace.status_runs` (`bin/dotfiles-workspace status` exits 0), `workspace.any_discovered` (advisory — warns when zero workspaces found, pointing at `WORKSPACE_SCAN_ROOTS` and the sentinel convention).
- `tests/workspace-doctor-discovery.bats` (new): N=0 (empty scan root → no output, rc 0); N=1 via sentinel; N=2 via the ≥2-TASKS.md heuristic + sentinel; a dir with one TASKS.md child is NOT a workspace; `workspaces.json` declared paths win over scanning; multi-root `WORKSPACE_SCAN_ROOTS`.
- `tests/workspace-doctor-status.bats` (new): fixture with 2 workspaces (one git repo with an upstream-less commit + one dirty file; one TASKS.md with 2 unchecked / 1 blocked) asserts the summary numbers and rollup line; `--workspace` scoping; unknown workspace exits 2; no-workspace host exits 0; `--help` exits 0; module structural checks (executable, no hardcoded `/Users/`, registers ≥ 4 checks).
- `docs/workspace.md` (new): concept doc — discovery order, sentinel convention, `WORKSPACE_SCAN_ROOTS`, status output legend, doctor checks, the deferred tasks-md config integration.
- Docs (rule #5 + `make verify-counts` gate): README and `docs/module-reference.md` gain the workspace module rows; keep module totals out of prose (`make count` prints live numbers).
- TASKS.md: remove this task's block; file the slice-2 follow-up (`workspace-doctor-config-integration`: consume the real tasks-md workspaces config once it ships, bootstrap-flag checks like `.minsky/repo.yaml` presence, doctor firing the full status output).

## Scope (out)

- Consuming a live `~/.config/tasks-md/workspaces.{json,yaml}` written by the `tasks` CLI — the foundation task (tasksmd `workspace-mode-nested-repos`) hasn't shipped the config on this host; the json/yaml readers land now but cross-tool behavior is verified in slice 2 (`workspace-doctor-config-integration`).
- "Repos that should be bootstrapped but aren't" flags (`.minsky/repo.yaml`, agentbrew `workspace-aware-sync` coupling) — slice 2.
- `home/zshrc` `WORKSPACE_SCAN_ROOTS` export — the default lives in the lib; documented in docs/workspace.md (the task marks the export "if useful"; it isn't needed for the default path).
- Behind-count (`@{u}..HEAD` reverse) and fetch-driven freshness — status reads local state only; no network.

## GET before IMPLEMENT

- Searched for an existing multi-workspace status tool: `tasks workspaces list` (tasks-md CLI) — not installed/configured on this host and the config file doesn't exist (`ls ~/.config/tasks-md/` → none, verified 2026-06-12); minsky's `show tasks` is single-host-scoped; agentbrew has no workspace iterator. The discovery lib is deliberately a thin, extractable adapter around the same config the `tasks` CLI will own — when the tasksmd foundation ships, slice 2 swaps scanning for the shared config without changing consumers (rule #0 WRAP-shaped).
- Reuses in-repo conventions: module auto-discovery (`modules/<name>/doctor.sh`, AGENTS.md rule #6), `check`/`check_advisory` helpers, env-override + fixture pattern from `modules/minsky/doctor.sh` + `tests/module-minsky.bats`.

## Implementation steps

<!-- Current status: specification-complete, implementation NOT yet started.
     This plan is validated pre-implementation per the next-task workflow. -->

### Step 1: Failing tests (red)

Add the two bats files against the not-yet-existing lib/bin/module. Verify: `bats tests/workspace-doctor-discovery.bats tests/workspace-doctor-status.bats` fails (files/functions missing).

### Step 2: Discovery lib + status command (green for discovery/status)

Add `lib/workspace-discovery.sh` and `bin/dotfiles-workspace`. Verify: `bats tests/workspace-doctor-discovery.bats tests/workspace-doctor-status.bats` exits 0 and `bin/dotfiles-workspace status` runs clean against the real host.

### Step 3: Doctor module (green for module checks)

Add `modules/workspace/doctor.sh` with the planned doctor checks; structural test cases go green. Verify: `bin/dotfiles-doctor --module workspace` exits 0 on this host.

### Step 4: Docs + counts + queue

`docs/workspace.md`, README count bumps + module mention, `docs/module-reference.md` rows, TASKS.md block removal + slice-2 follow-up task. Verify: `make verify-counts` exits 0 and `make check` exits 0.

## Risks and mitigations

- **Risk: README/docs drift trips `make verify-counts`.**
  - Mitigation: Step 4 re-runs the gate after doc edits; the gate itself is the deterministic check.
- **Risk: TASKS.md task-count heuristic over/under-counts (multi-line metadata, blocked semantics).**
  - Mitigation: counts are labeled an estimate in output + docs, use the same grep heuristic as the established roam scan, and tests pin exact fixture numbers so behavior changes are visible.
- **Risk: status command is slow on hosts with many repos across multiple workspace roots.**
  - Mitigation: only immediate child dirs of workspace roots are inspected (no recursion); per-repo git calls are local-state only (`status --short | wc -l`, `rev-list --count` with upstream guard); doctor's `status_runs` check inherits the module-runner timeout.
- **Risk: `workspaces.json` shape mismatch with the future tasks-md spec.**
  - Mitigation: reader accepts both object (`{"name": "path"}`) and array (`[{name,path}]`) shapes behind one function; slice-2 task pins the final spec once tasksmd ships it; fallback scanning keeps working regardless.
- **Risk: fixture git repos hit the host's global hooks/excludes (seen in local-ai-loop-reviewer.bats).**
  - Mitigation: fixtures set `core.hooksPath=/dev/null` + `core.excludesFile=/dev/null` like `tests/module-minsky.bats` and the reviewer tests.

## Acceptance criteria

1. `bats tests/workspace-doctor-discovery.bats` exits 0 — N=0/N=1/N=2 discovery cases, sentinel + ≥2-TASKS.md heuristics, config precedence, multi-root.
2. `bats tests/workspace-doctor-status.bats` exits 0 — a two-workspace fixture reports the exact per-workspace and rollup counts (task Measurement: "a fixture with two workspaces reports correct rollup counts").
3. `bin/dotfiles-workspace status` and `bin/dotfiles-doctor --module workspace` exit 0 on this host (real-host smoke).
4. `make verify-counts` exits 0 after the README/docs updates.
5. `make check` exits 0.

## Reviewer verdict

- **Verdict**: approved
- **Reviewer**: subagent_explore (plan-reviewer)
- **Date**: 2026-06-12
- **Concerns**:
- **Approval rationale** (only if approved):
  - The plan is specification-complete, well-scoped, and addresses the task's Acceptance and Measurement criteria. Discovery resolution order (json → yaml → sentinel/structure) is consistent with the task Details; test cases (N=0/1/2, config precedence, scoping, exact rollup numbers) are sufficient. Rule-0 compliance is demonstrated (GET research documented; slice-2 follow-up `workspace-doctor-config-integration` files the Replace/Relocate-shaped work), and the README/module-reference count gates are explicitly addressed.
