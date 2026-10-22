#!/usr/bin/env bash
# Optional Agentfile layers that this Mac merges after the base and overlay.
# Shared by .chezmoiscripts/run_after_agentbrew-sync.sh and the agentbrew
# doctor check, so both build the same merge list.
#
# agentfile_optional_layers <dotfiles_dir>
#   Prints one path per line, in merge order:
#   1. config/agentfile-owner-rules.yaml when owner_machine is true
#      (chezmoi data, or DOTFILES_OWNER_MACHINE).
#   2. This Mac's local Agentfile (agentfile_local_layer_path) when it
#      exists and agentfile_local_layer_problems finds no error. It is
#      untracked, so an extra MCP server on one Mac needs no change to the
#      shared Agentfile.yaml (issue #259). Each problem goes to stderr; an
#      error skips only this layer.
agentfile_optional_layers() {
  local dir="$1"
  local owner local_layer problems
  owner="${DOTFILES_OWNER_MACHINE:-$(chezmoi execute-template '{{ dig "owner_machine" true . }}' 2>/dev/null || echo true)}"
  if [ "$owner" = "true" ] && [ -f "$dir/config/agentfile-owner-rules.yaml" ]; then
    printf '%s\n' "$dir/config/agentfile-owner-rules.yaml"
  fi
  local_layer="$(agentfile_local_layer_path)"
  [ -f "$local_layer" ] || return 0
  problems="$(agentfile_local_layer_problems "$local_layer" | grep -v '^note: ' || true)"
  if printf '%s\n' "$problems" | grep -q '^error: '; then
    printf '⚠ Skipping %s (the other layers still sync):\n' "$local_layer" >&2
    printf '%s\n' "$problems" | sed 's/^/    /' >&2
    return 0
  fi
  if [ -n "$problems" ]; then
    printf '⚠ %s:\n' "$local_layer" >&2
    printf '%s\n' "$problems" | sed 's/^/    /' >&2
  fi
  printf '%s\n' "$local_layer"
}

# Prints the path of this Mac's local Agentfile layer. lib/apply-state.sh
# hashes the same path, so `dotfiles apply --if-changed` sees an edit.
agentfile_local_layer_path() {
  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/Agentfile.local.yaml"
}

# agentfile_local_layer_problems [<file>]: prints one problem per line,
# "error: …" (the layer is skipped) or "warning: …" (agentbrew ignores that
# key). Prints nothing when the file is fine or absent.
#
# hooks: is an error. agentbrew's merge lets a later layer's hook replace
# every earlier hook with the same event, matcher, and agents, so one local
# Bash hook would drop the shared block-dangerous-git.sh hook. A local layer
# must never remove a shared safety hook, so it may hold no hooks at all.
#
# The authority is agentbrew itself: the file is merged alone with
# `agentbrew agentfile merge` (AGENTFILE_AGENTBREW_CMD, default agentbrew).
# A file it cannot read, or whose merge result has hooks (also ones that
# arrive through a YAML merge key), is an error. mikefarah yq, when present,
# adds clearer messages and the list-key warnings. A check that cannot run
# (no temp file) is an error too, so the layer is skipped, never trusted.
# Without a merge-capable agentbrew it prints "note: checked with yq only";
# a note is not a problem.
agentfile_local_layer_problems() {
  local file="${1:-$(agentfile_local_layer_path)}"
  [ -f "$file" ] || return 0
  { _agentfile_local_agentbrew_check "$file"; _agentfile_local_yq_check "$file"; } | awk '!seen[$0]++'
}

# Merges the file alone with agentbrew.
_agentfile_local_agentbrew_check() {
  local file="$1" ab="${AGENTFILE_AGENTBREW_CMD:-agentbrew}" out err
  # shellcheck disable=SC2086 # the command may be "node <path>/cli.js"
  if ! $ab agentfile merge --help 2>&1 | grep -q 'agentfile merge'; then
    echo "note: checked with yq only (no agentbrew here can merge Agentfiles)"
    return 0
  fi
  if ! out="$(_agentfile_local_tmp)"; then
    echo "error: cannot check this file: no temp file in ${TMPDIR:-/tmp} or ${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
    return 0
  fi
  # shellcheck disable=SC2086
  if ! err="$($ab agentfile merge "$file" --output "$out" 2>&1)"; then
    echo "error: agentbrew cannot read it: $(_agentfile_error_line "$err")"
  elif grep -q '^hooks:' "$out"; then
    _agentfile_local_hooks_error
  fi
  rm -f "$out"
}

# Prints a new temp file: in TMPDIR, else in the user cache folder.
_agentfile_local_tmp() {
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
  mktemp "${TMPDIR:-/tmp}/dotfiles-local-agentfile.XXXXXX" 2>/dev/null && return 0
  mkdir -p "$cache" 2>/dev/null && mktemp "$cache/local-agentfile.XXXXXX" 2>/dev/null
}

# _agentfile_error_line <agentbrew output>: its first "Error:" line, without
# color codes (agentbrew may print a status line first).
_agentfile_error_line() {
  local plain
  plain="$(printf '%s\n' "$1" | sed $'s/\x1b\\[[0-9;]*m//g')"
  printf '%s\n' "$plain" | grep -m1 -E '^[[:space:]]*Error:' || printf '%s\n' "$plain" | tail -1
}

_agentfile_local_hooks_error() {
  echo "error: hooks: is not allowed here. A hook in this file would replace every shared hook with the same event and matcher (block-dangerous-git.sh and others). Remove hooks: from this file."
}

# Clearer messages and warnings with mikefarah yq; silent without it.
_agentfile_local_yq_check() {
  local file="$1" err top key kind flat
  yq --version 2>&1 | grep -q mikefarah || return 0
  if ! err="$(yq -o=json '.' "$file" 2>&1 >/dev/null)"; then
    echo "error: not valid YAML: $(printf '%s\n' "$err" | grep -v 'level=WARN' | head -1)"
    return 0
  fi
  top="$(yq 'type' "$file" 2>/dev/null)"
  if [ "$(printf '%s\n' "$top" | wc -l | tr -d ' ')" -gt 1 ]; then
    echo "error: the file holds more than one YAML document (a --- line); keep one"
    return 0
  fi
  case "$top" in
    '!!map') ;;
    '!!null' | '') return 0 ;;
    *) echo "error: the top level must be keys such as mcp: and skills:, not a ${top#!!}"; return 0 ;;
  esac
  # explode() resolves YAML anchors and merge keys, as agentbrew does. Do it
  # once, keep the result in memory, and ask that copy.
  # yq may print a level=WARN line on stderr; keep stderr out of the copy.
  if ! flat="$(yq -o=json 'explode(.)' "$file" 2>/dev/null)"; then
    echo "error: cannot check this file: $(yq -o=json 'explode(.)' "$file" 2>&1 >/dev/null | grep -v 'level=WARN' | head -1)"
    return 0
  fi
  if [ "$(_agentfile_flat_q 'has("hooks")')" = true ]; then
    _agentfile_local_hooks_error
  fi
  for key in mcp skills sources commands agents excludeAgents memoryPacks; do
    kind="$(K="$key" _agentfile_flat_q '.[strenv(K)] | type')"
    case "$kind" in
      '!!seq' | '!!null' | '') ;;
      *) echo "warning: $key: must be a list (one \"- item\" per line), not a ${kind#!!}; agentbrew ignores it" ;;
    esac
  done
  kind="$(_agentfile_flat_q '.rules | type')"
  case "$kind" in
    '!!str' | '!!null' | '') ;;
    *) echo "warning: rules: must be text, not a ${kind#!!}; agentbrew ignores it" ;;
  esac
  _agentfile_flat_q 'keys | .[]' | while IFS= read -r key; do
    case "$key" in
      mcp | skills | sources | commands | agents | rules | hooks | recommended | excludeAgents | \
        defaultModel | defaultEffort | modelOverrides | task_backend | repo | project | memory | memoryPacks) ;;
      *) echo "warning: $key: agentbrew's merge does not use this key; it is ignored" ;;
    esac
  done
}

# _agentfile_flat_q <expression>: runs a yq expression on $flat (the
# exploded JSON copy in _agentfile_local_yq_check).
_agentfile_flat_q() {
  printf '%s\n' "$flat" | yq -p=json "$1" 2>/dev/null
}

# agentfile_plugin_layers <base Agentfile>: reads "name<TAB>Agentfile" lines
# for company plugins (plugin_agentfile_pairs, lock order) on stdin and
# prints the Agentfiles to merge, one per line.
#
# A plugin may add agent hooks, but never drop, replace, or weaken a shared
# one. agentbrew's merge lets a later hook replace every earlier hook with
# the same event, matcher, and agents, so this asks agentbrew itself: it
# merges the earlier layers (the base, then each plugin kept so far) with
# and without the plugin. If a hook entry of the earlier merge (compared
# whole: command, if, async, timeout, and every other field) is missing
# from the later one, that plugin's Agentfile is skipped, and stderr names
# the plugin and each hook it would remove. A plugin Agentfile agentbrew
# cannot read, or a check that cannot run, skips it too.
#
# Without an agentbrew that can merge (AGENTFILE_AGENTBREW_CMD, default
# agentbrew), the sync syncs each Agentfile on its own, and agentbrew then
# sets the hooks to that file's list, so a plugin Agentfile with hooks: is
# skipped. Without mikefarah yq nothing can be checked: every Agentfile is
# skipped.
agentfile_plugin_layers() {
  local base="$1" ab="${AGENTFILE_AGENTBREW_CMD:-agentbrew}" name file before after err dropped
  local -a earlier=()
  [ -f "$base" ] && earlier=("$base")
  if ! yq --version 2>&1 | grep -q mikefarah; then
    while IFS=$'\t' read -r name file; do
      [ -z "$file" ] || printf '⚠ Skipping the Agentfile of plugin %s: cannot check its hooks without mikefarah yq\n' "$name" >&2
    done
    return 0
  fi
  # shellcheck disable=SC2086 # the command may be "node <path>/cli.js"
  if ! $ab agentfile merge --help 2>&1 | grep -q 'agentfile merge'; then
    while IFS=$'\t' read -r name file; do
      [ -n "$file" ] || continue
      if [ "$(yq 'explode(.) | has("hooks")' "$file" 2>/dev/null)" != false ]; then
        printf '⚠ Skipping the Agentfile of plugin %s (%s): it has hooks:, and without agentfile merge they would replace every shared hook\n' "$name" "$file" >&2
        continue
      fi
      printf '%s\n' "$file"
    done
    return 0
  fi
  if ! before="$(_agentfile_local_tmp)" || ! after="$(_agentfile_local_tmp)"; then
    rm -f "${before:-}"
    while IFS=$'\t' read -r name file; do
      [ -z "$file" ] || printf '⚠ Skipping the Agentfile of plugin %s: cannot check it (no temp file)\n' "$name" >&2
    done
    return 0
  fi
  # The merge of the earlier layers; after each kept plugin, its merge.
  : > "$before"
  if [ "${#earlier[@]}" -gt 0 ]; then
    # shellcheck disable=SC2086
    if ! err="$($ab agentfile merge "${earlier[@]}" --output "$before" 2>&1)"; then
      while IFS=$'\t' read -r name file; do
        [ -z "$file" ] || printf '⚠ Skipping the Agentfile of plugin %s: cannot check it: %s\n' "$name" "$(_agentfile_error_line "$err")" >&2
      done
      rm -f "$before" "$after"
      return 0
    fi
  fi
  while IFS=$'\t' read -r name file; do
    [ -n "$file" ] || continue
    # shellcheck disable=SC2086
    if ! err="$($ab agentfile merge ${earlier[@]+"${earlier[@]}"} "$file" --output "$after" 2>&1)"; then
      printf '⚠ Skipping the Agentfile of plugin %s (%s): agentbrew cannot read it: %s\n' \
        "$name" "$file" "$(_agentfile_error_line "$err")" >&2
      continue
    fi
    dropped="$(LC_ALL=C comm -23 <(_agentfile_hook_entries "$before") <(_agentfile_hook_entries "$after"))"
    if [ -n "$dropped" ]; then
      printf '⚠ Skipping the Agentfile of plugin %s (%s): its hooks would replace these shared hooks (same event, matcher, and agents):\n' "$name" "$file" >&2
      printf '%s\n' "$dropped" | yq -p=json -r '.event + " " + .matcher + " " + (.command // .prompt // "")' 2>/dev/null |
        grep -v '^---$' | sed 's/^/    /' >&2
      continue
    fi
    printf '%s\n' "$file"
    earlier+=("$file")
    cp "$after" "$before"
  done
  rm -f "$before" "$after"
}

# _agentfile_hook_entries <merged Agentfile>: each hook entry as one line of
# sorted-key JSON (matcher "*" when unset), sorted, for a whole-entry compare.
_agentfile_hook_entries() {
  [ -s "$1" ] || return 0
  yq -o=json -I=0 '(.hooks // [])[] | .matcher = (.matcher // "*") | sort_keys(..)' "$1" 2>/dev/null | LC_ALL=C sort -u
}
