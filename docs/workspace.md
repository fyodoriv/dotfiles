# Multi-workspace visibility

A **workspace** is a parent folder holding several repo checkouts that are
worked as a unit — e.g. `~/apps/tooling/` (dotfiles, agentbrew, minsky, …)
or another folder of related repos. dotfiles gives the host-level picture across all
of them: which repos are dirty or ahead, and how much TASKS.md work each
one carries.

## Commands

```bash
dotfiles-workspace status                    # every workspace
dotfiles-workspace status --workspace tooling # one workspace
```

Sample output:

```
=== Workspace: tooling (~/apps/tooling) ===
  ✓ agentbrew  0 dirty  +0
  agentbrew: 133 tasks (124 unblocked)
  ✗ minsky  (git status failed — bare or worktree-container checkout?)
  Total: 11 repos, 416 tasks, 292 unblocked
=== All workspaces: 2 workspaces, 14 repos, 686 tasks ===
```

- `✓ <repo>  N dirty  +M` — git checkout with N changed lines
  (`git status --short`) and M commits ahead of upstream (`-` when no
  upstream is configured). Local state only — never fetches.
- `✗ <repo>` — the dir has a `.git` but `git status` fails (bare or
  worktree-container checkout, e.g. an orchestrator-managed repo). One
  broken checkout never aborts the rollup.
- `<repo>: N tasks (K unblocked)` — TASKS.md estimate: unchecked `- [ ]`
  lines minus `**Blocked**` / `**Blocked by**` metadata lines. Same
  heuristic the cross-repo task picker uses; treat it as an estimate,
  not an exact queue depth.

## How workspaces are discovered

`lib/workspace-discovery.sh` resolves in order (first source wins):

1. `~/.config/tasks-md/workspaces.json` — the tasks-md CLI's shared
   config. Object (`{"tooling": "~/apps/tooling"}`) and array
   (`[{"name": "tooling", "path": "~/apps/tooling"}]`) shapes both work.
2. `~/.config/tasks-md/workspaces.yaml` — minimal `name: path` lines.
3. Fallback scan of `$WORKSPACE_SCAN_ROOTS` (colon-separated; default
   `~/apps`): an immediate child dir is a workspace when it contains a
   `.tasks-md-workspace` sentinel file **or** at least two
   immediate-child `*/TASKS.md` files.

Declare a folder explicitly with:

```bash
touch ~/apps/mystack/.tasks-md-workspace
```

## Doctor checks (`dotfiles doctor --module workspace`)

| Check | Meaning |
|---|---|
| `workspace.discovery_lib` | discovery lib sources and defines `workspace_discover` |
| `workspace.declared_roots_exist` | every config-declared workspace path is a directory (vacuous pass without a config) |
| `workspace.status_runs` | `dotfiles-workspace status` exits 0 |
| `workspace.any_discovered` | advisory — warns when zero workspaces are found |

## Cross-tool integration (slice 2)

The same `~/.config/tasks-md/workspaces.json` is designed to be consumed
by (a) the `tasks` CLI, (b) `agentbrew sync`, and (c) this doctor. The
config writer hasn't shipped on this machine yet, so the fallback scan is
authoritative today; once the tasks-md foundation lands, discovery swaps
to the shared config without changing consumers — tracked in TASKS.md as
`workspace-doctor-config-integration`.
