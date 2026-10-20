#!/usr/bin/env bash
# Optional Agentfile layers that this Mac merges after the base and overlay.
# Shared by .chezmoiscripts/run_after_agentbrew-sync.sh and the agentbrew
# doctor check, so both build the same merge list.
#
# agentfile_optional_layers <dotfiles_dir>
#   Prints one path per line, in merge order:
#   1. config/agentfile-owner-rules.yaml when owner_machine is true
#      (chezmoi data, or DOTFILES_OWNER_MACHINE).
#   2. config/agentfile-no-cursor.yaml when use_cursor is false
#      (chezmoi data, or DOTFILES_USE_CURSOR).
agentfile_optional_layers() {
  local dir="$1"
  local owner use_cursor
  owner="${DOTFILES_OWNER_MACHINE:-$(chezmoi execute-template '{{ dig "owner_machine" true . }}' 2>/dev/null || echo true)}"
  if [ "$owner" = "true" ] && [ -f "$dir/config/agentfile-owner-rules.yaml" ]; then
    printf '%s\n' "$dir/config/agentfile-owner-rules.yaml"
  fi
  use_cursor="${DOTFILES_USE_CURSOR:-$(chezmoi execute-template '{{ dig "use_cursor" true . }}' 2>/dev/null || echo true)}"
  if [ "$use_cursor" = "false" ] && [ -f "$dir/config/agentfile-no-cursor.yaml" ]; then
    printf '%s\n' "$dir/config/agentfile-no-cursor.yaml"
  fi
}
