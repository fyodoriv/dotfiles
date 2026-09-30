#!/bin/bash
# Prepend dotfiles/bin before Cursor agent Shell/Bash/Task tool commands.
#
# terminal.integrated.env.osx does NOT apply to agent Shell subshells — they run
# in a sandbox with PATH=/opt/homebrew/bin:/usr/bin:/bin (no dotfiles/bin).
# preToolUse updated_input runs after Cursor's PATH snapshot restore.

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
_dotfiles_dir="$(_resolve_dotfiles_dir || true)"
_home="${HOME:-}"

_lib_root="${_dotfiles_dir:-$(cd "$_hook_dir/.." && pwd)}"

if [ -z "$_dotfiles_dir" ]; then
  printf '%s\n' '{"permission": "allow"}'
  exit 0
fi

_path_prefix="$(dotfiles_agent_path_prefix "$_dotfiles_dir" "$_home")"

_emit_updated_input() {
  local command="$1" response_file response_json slash="/"
  response_file="$(/usr/bin/mktemp)"
  /usr/bin/plutil -create binary1 "$response_file"
  /usr/bin/plutil -insert permission -string allow "$response_file"
  /usr/bin/plutil -insert updated_input -dictionary "$response_file"
  /usr/bin/plutil -insert updated_input.command -string "$command" "$response_file"
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
    printf '%s\n' '{"permission": "allow"}'
    exit 0
    ;;
esac

cmd="$(printf '%s' "$input" \
  | /usr/bin/plutil -extract tool_input.command raw -o - -- - 2>/dev/null || true)"
if [ -z "${cmd//[[:space:]]/}" ]; then
  printf '%s\n' '{"permission": "allow"}'
  exit 0
fi

[ -n "$_path_prefix" ] \
  || _path_prefix="${_dotfiles_dir}/bin:${_home}/.local/bin"

# Hardcoded Apple paths still fire endpoint policy even when PATH is fixed.
# Rewrite them to managed shims. Longer names must come first.
_original_cmd="$cmd"
_shim="${_dotfiles_dir}/bin"
while IFS='|' read -r old new; do
  cmd="${cmd//$old/$new}"
done <<EOF
/usr/bin/python3.13|$_shim/python3.13
/usr/bin/python3|$_shim/python3
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
    printf '%s\n' '{"permission": "allow"}'
  fi
  exit 0
fi

_new_path="$_path_prefix"
[ -z "${PATH:-}" ] || _new_path="${_new_path}:${PATH}"
printf -v _quoted_path '%q' "$_new_path"
_emit_updated_input "PATH=${_quoted_path}; ${cmd}"
