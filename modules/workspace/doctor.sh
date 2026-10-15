#!/bin/bash
# Doctor checks for multi-workspace visibility.
#
# The operator runs several workspace folders (parents of multiple repo
# checkouts, each with its own TASKS.md) plus dozens of standalone repos.
# Before this module, dotfiles had zero visibility into that layout — no
# check confirmed declared workspaces exist or that the host-level status
# command works. Discovery is shared with `bin/dotfiles-workspace` via
# `lib/workspace-discovery.sh`: tasks-md workspaces.json → workspaces.yaml
# → sentinel/structure scan of $WORKSPACE_SCAN_ROOTS (default ~/apps).
#
# Cross-tool note: the config is the one `tasks workspaces add` writes
# ($XDG_CONFIG_HOME/tasks-md/workspaces.json). When it exists it wins; the
# fallback scan covers hosts without one. See docs/workspace.md.
#
# Anchor: AGENTS.md rule #6 (new modules need modules/<name>/doctor.sh);
# surfaced by TASKS.md task `workspace-folder-doctor`.

_WORKSPACE_LIB="$DOTFILES_DIR/lib/workspace-discovery.sh"
_WORKSPACE_BIN="$DOTFILES_DIR/bin/dotfiles-workspace"

_workspace_lib_loads() {
  [ -f "$_WORKSPACE_LIB" ] || return 1
  # shellcheck source=../../lib/workspace-discovery.sh
  source "$_WORKSPACE_LIB" 2>/dev/null || return 1
  declare -F workspace_discover >/dev/null 2>&1
}

check "workspace.discovery_lib" \
  "workspace discovery lib loads (lib/workspace-discovery.sh)" \
  "_workspace_lib_loads" \
  ""

_workspace_has_config() {
  local cfg_dir; cfg_dir="$(workspace_config_dir)"
  [ -f "$cfg_dir/workspaces.json" ] || [ -f "$cfg_dir/workspaces.yaml" ]
}

_workspace_declared_roots_exist() {
  # Only meaningful when a tasks-md config declares workspaces; the
  # fallback scan can only ever discover directories that exist.
  _workspace_lib_loads || return 1
  _workspace_has_config || return 0
  local _name path
  while IFS=$'\t' read -r _name path; do
    [ -n "$path" ] || continue
    [ -d "$path" ] || return 1
  done < <(workspace_discover)
  return 0
}

check "workspace.declared_roots_exist" \
  "declared workspace roots exist on disk" \
  "_workspace_declared_roots_exist" \
  "edit ~/.config/tasks-md/workspaces.json (or .yaml) — fix or remove the missing path"

# Bootstrap flag: every repo (child dir with a TASKS.md) of a declared
# workspace is a git checkout. A plain copy cannot pull, push, or carry a
# worktree. Only declared workspaces count; the fallback scan is a guess.
_workspace_declared_repos_are_git() {
  _workspace_lib_loads || return 1
  _workspace_has_config || return 0
  local _name root dir
  while IFS=$'\t' read -r _name root; do
    [ -d "$root" ] || continue
    for dir in "$root"/*/; do
      dir="${dir%/}"
      [ -f "$dir/TASKS.md" ] || continue
      [ -e "$dir/.git" ] || return 1
    done
  done < <(workspace_discover)
  return 0
}

check_advisory "workspace.declared_repos_are_git" \
  "repos in declared workspaces are git checkouts" \
  "_workspace_declared_repos_are_git" \
  "re-clone the plain copy as a git checkout, or move it out of the workspace — run dotfiles-workspace status to find it"

_workspace_status_runs() {
  [ -x "$_WORKSPACE_BIN" ] || return 1
  "$_WORKSPACE_BIN" status >/dev/null 2>&1
}

check "workspace.status_runs" \
  "dotfiles-workspace status exits 0 (host-level rollup works)" \
  "_workspace_status_runs" \
  ""

_workspace_any_discovered() {
  _workspace_lib_loads || return 1
  [ -n "$(workspace_discover)" ]
}

check_advisory "workspace.any_discovered" \
  "at least one workspace discovered (sentinel .tasks-md-workspace, ≥2 child TASKS.md, or tasks-md config under \$WORKSPACE_SCAN_ROOTS)" \
  "_workspace_any_discovered" \
  "touch <workspace-root>/.tasks-md-workspace or set WORKSPACE_SCAN_ROOTS — see docs/workspace.md"
