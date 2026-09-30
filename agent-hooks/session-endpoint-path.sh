#!/bin/bash
# sessionStart: inject dotfiles/bin into agent session env (belt-and-suspenders).
# Shell tool PATH is primarily fixed by prepend-endpoint-path.sh preToolUse hook.

set -euo pipefail

unset BASH_ENV ENV

_resolve_dotfiles_dir() {
  if [ -n "${DOTFILES_DIR:-}" ] && [ -d "${DOTFILES_DIR}/bin" ]; then
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

_hook_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_lib_root="${_dotfiles_dir:-}"
if [ -z "$_lib_root" ] || [ ! -f "$_lib_root/lib/dotfiles-endpoint-paths.sh" ]; then
  _lib_root="$_hook_root"
fi

if [ -f "$_lib_root/lib/dotfiles-endpoint-paths.sh" ]; then
  # shellcheck source=../lib/dotfiles-endpoint-paths.sh
  source "$_lib_root/lib/dotfiles-endpoint-paths.sh"
  if [ -n "$_dotfiles_dir" ]; then
    export DOTFILES_DIR="$_dotfiles_dir"
    dotfiles_prepend_endpoint_tool_paths "$_dotfiles_dir/bin"
  elif [ -d "$_hook_root/bin" ]; then
    dotfiles_prepend_endpoint_tool_paths "$_hook_root/bin"
  fi
fi

if [ -z "$_dotfiles_dir" ]; then
  printf '%s\n' '{}'
  exit 0
fi

_path_prefix="$(dotfiles_agent_path_prefix "$_dotfiles_dir" "$_home")"

# Fast sign + link before sessionStart invokes python3/jq (post-reboot unsigned window).
if [ -x "$_dotfiles_dir/bin/dotfiles-adhoc-sign-jq" ]; then
  DOTFILES_ADHOC_SIGN_QUIET=1 "$_dotfiles_dir/bin/dotfiles-adhoc-sign-jq" 2>/dev/null || true
  [ -x "$_dotfiles_dir/bin/dotfiles-link-jq-shim" ] && \
    "$_dotfiles_dir/bin/dotfiles-link-jq-shim" 2>/dev/null || true
fi
if [ -x "$_dotfiles_dir/bin/dotfiles-adhoc-sign-ggrep" ]; then
  DOTFILES_ADHOC_SIGN_QUIET=1 "$_dotfiles_dir/bin/dotfiles-adhoc-sign-ggrep" 2>/dev/null || true
  [ -x "$_dotfiles_dir/bin/dotfiles-link-grep-shim" ] && \
    "$_dotfiles_dir/bin/dotfiles-link-grep-shim" 2>/dev/null || true
fi
if [ -x "$_dotfiles_dir/bin/dotfiles-adhoc-sign-uv-pythons" ]; then
  DOTFILES_ADHOC_SIGN_QUIET=1 "$_dotfiles_dir/bin/dotfiles-adhoc-sign-uv-pythons" 2>/dev/null || true
  [ -x "$_dotfiles_dir/bin/dotfiles-link-python-shim" ] && \
    "$_dotfiles_dir/bin/dotfiles-link-python-shim" 2>/dev/null || true
fi

_py_cmd="$(dotfiles_resolve_python "$_dotfiles_dir" "$_home" python3 2>/dev/null || echo python3)"
"$_py_cmd" "$_lib_root/lib/dotfiles-agent-session-env.py" "$_dotfiles_dir" "$_home" "$_path_prefix"
