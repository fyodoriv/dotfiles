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
  problems="$(agentfile_local_layer_problems "$local_layer")"
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
agentfile_local_layer_problems() {
  local file="${1:-$(agentfile_local_layer_path)}" err top key kind
  [ -f "$file" ] || return 0
  if ! command -v yq >/dev/null 2>&1; then
    echo "error: yq is not installed, so this file cannot be checked"
    return 0
  fi
  if ! err="$(yq -o=json '.' "$file" 2>&1 >/dev/null)"; then
    echo "error: not valid YAML: $(printf '%s\n' "$err" | head -1)"
    return 0
  fi
  top="$(yq 'type' "$file" 2>/dev/null)"
  case "$top" in
    '!!map') ;;
    '!!null' | '') return 0 ;;
    *) echo "error: the top level must be keys such as mcp: and skills:, not a ${top#!!}"; return 0 ;;
  esac
  if [ "$(yq 'has("hooks")' "$file" 2>/dev/null)" = true ]; then
    echo "error: hooks: is not allowed here. A hook in this file would replace every shared hook with the same event and matcher (block-dangerous-git.sh and others). Remove hooks: from this file."
  fi
  for key in mcp skills sources commands agents excludeAgents memoryPacks; do
    kind="$(K="$key" yq '.[strenv(K)] | type' "$file" 2>/dev/null)"
    case "$kind" in
      '!!seq' | '!!null' | '') ;;
      *) echo "warning: $key: must be a list (one \"- item\" per line), not a ${kind#!!}; agentbrew ignores it" ;;
    esac
  done
}
