#!/bin/bash
# Prepend dotfiles/bin before agent Shell/Bash/Task tool commands.
#
# Agent Shell subshells can run in a sandbox with
# PATH=/opt/homebrew/bin:/usr/bin:/bin (no dotfiles/bin). preToolUse
# The input update runs after the agent's PATH snapshot restore.

set -euo pipefail

unset BASH_ENV ENV

_hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap-endpoint-path.sh
source "$_hook_dir/bootstrap-endpoint-path.sh"

_resolve_dotfiles_dir() {
  if [ -n "${DOTFILES_DIR:-}" ]; then
    printf '%s\n' "$DOTFILES_DIR"
    return 0
  fi
  local candidate home="${HOME:-}"
  for candidate in \
    "${home}/apps/tooling/dotfiles" \
    "${home}/apps/dotfiles" \
    "${home}/dotfiles"; do
    if [ -d "${candidate}/bin" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

input=$(cat)
_is_codex=false
_turn_id="$(printf '%s' "$input" \
  | /usr/bin/plutil -extract turn_id raw -o - -- - 2>/dev/null || true)"
[ -z "$_turn_id" ] || _is_codex=true
_is_claude=false
if ! $_is_codex; then
  _permission_mode="$(printf '%s' "$input" \
    | /usr/bin/plutil -extract permission_mode raw -o - -- - 2>/dev/null || true)"
  if [ -n "$_permission_mode" ]; then
    _event="$(printf '%s' "$input" \
      | /usr/bin/plutil -extract hook_event_name raw -o - -- - 2>/dev/null || true)"
    _transcript="$(printf '%s' "$input" \
      | /usr/bin/plutil -extract transcript_path raw -o - -- - 2>/dev/null || true)"
    [ "$_event" != "PreToolUse" ] || [ -z "$_transcript" ] || _is_claude=true
  fi
fi

_emit_no_update() {
  if $_is_codex; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  elif $_is_claude; then
    printf '%s\n' '{}'
  else
    printf '%s\n' '{"permission": "allow"}'
  fi
}

if $_is_claude && [ "$_permission_mode" = "auto" ]; then
  _emit_no_update
  exit 0
fi

_dotfiles_dir="$(_resolve_dotfiles_dir || true)"
_home="${HOME:-}"

_lib_root="${_dotfiles_dir:-$(cd "$_hook_dir/.." && pwd)}"

if [ -z "$_dotfiles_dir" ]; then
  _emit_no_update
  exit 0
fi

_path_prefix="$(dotfiles_agent_path_prefix "$_dotfiles_dir" "$_home")"

_emit_updated_input() {
  local command="$1" response_file response_json original_input slash="/"
  if $_is_claude; then
    original_input="$(printf '%s' "$input" | /usr/bin/plutil -extract tool_input json -o - -- -)"
  fi
  response_file="$(/usr/bin/mktemp)"
  /usr/bin/plutil -create binary1 "$response_file"
  if $_is_codex || $_is_claude; then
    /usr/bin/plutil -insert hookSpecificOutput -dictionary "$response_file"
    /usr/bin/plutil -insert hookSpecificOutput.hookEventName -string PreToolUse "$response_file"
    if $_is_claude; then
      /usr/bin/plutil -insert hookSpecificOutput.updatedInput -json "$original_input" "$response_file"
      /usr/bin/plutil -replace hookSpecificOutput.updatedInput.command -string "$command" "$response_file"
    else
      /usr/bin/plutil -insert hookSpecificOutput.permissionDecision -string allow "$response_file"
      /usr/bin/plutil -insert hookSpecificOutput.updatedInput -dictionary "$response_file"
      /usr/bin/plutil -insert hookSpecificOutput.updatedInput.command -string "$command" "$response_file"
    fi
  else
    /usr/bin/plutil -insert permission -string allow "$response_file"
    /usr/bin/plutil -insert updated_input -dictionary "$response_file"
    /usr/bin/plutil -insert updated_input.command -string "$command" "$response_file"
  fi
  response_json="$(/usr/bin/plutil -convert json -o - "$response_file")"
  /bin/rm -f "$response_file"
  # Foundation escapes "/" as "\/"; normalize it for stable hook output and
  # readable policy-guard classification without changing JSON semantics.
  printf '%s\n' "${response_json//\\\//$slash}"
}

tool="$(printf '%s' "$input" \
  | /usr/bin/plutil -extract tool_name raw -o - -- - 2>/dev/null || true)"
case "$tool" in
  Shell|Bash|Task) ;;
  *)
    _emit_no_update
    exit 0
    ;;
esac

cmd="$(printf '%s' "$input" \
  | /usr/bin/plutil -extract tool_input.command raw -o - -- - 2>/dev/null || true)"
if [ -z "${cmd//[[:space:]]/}" ]; then
  _emit_no_update
  exit 0
fi

[ -n "$_path_prefix" ] \
  || _path_prefix="${_dotfiles_dir}/bin:${_home}/.local/bin"

# Some explicit tool paths still need managed shims after PATH is set.
# Keep explicit Apple Python paths so the hook preserves the interpreter choice.
_original_cmd="$cmd"
_shim="${_dotfiles_dir}/bin"
while IFS='|' read -r old new; do
  cmd="${cmd//$old/$new}"
done <<EOF
/usr/bin/curl|$_shim/curl
/usr/bin/jq|$_shim/jq
/usr/bin/perl|$_shim/perl
/usr/bin/grep|$_shim/grep
/usr/bin/sed|$_shim/sed
/usr/bin/awk|$_shim/awk
/usr/bin/find|$_shim/find
/usr/bin/otool|$_shim/otool
EOF

if [[ "$cmd" == *dotfiles/bin* ]] \
    && { [[ "$cmd" == *"export PATH="* ]] || [[ "${cmd#"${cmd%%[![:space:]]*}"}" == PATH=* ]]; }; then
  if [ "$cmd" != "$_original_cmd" ]; then
    _emit_updated_input "$cmd"
  else
    _emit_no_update
  fi
  exit 0
fi

_new_path="$_path_prefix"
[ -z "${PATH:-}" ] || _new_path="${_new_path}:${PATH}"
printf -v _quoted_path '%q' "$_new_path"
_emit_updated_input "PATH=${_quoted_path}; ${cmd}"
