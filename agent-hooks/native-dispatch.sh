#!/bin/bash
# Per-invocation native dispatch; the shell guard retains fallback authority.
[ "${DOTFILES_NATIVE_GUARD_BYPASS:-}" != 1 ] || return 0
_native_dir="${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/native/hook-status"
[ -L "$_native_dir/current" ] && [ -x /sbin/sha256 ] || return 0
_native_name="$(readlink "$_native_dir/current" 2>/dev/null)" || return 0
[[ "$_native_name" =~ ^hook-status-[0-9a-f]{64}$ ]] || return 0
_native_path="$_native_dir/$_native_name"
[ -f "$_native_path" ] && [ ! -L "$_native_path" ] && [ -x "$_native_path" ] || return 0
_native_hash="$(/sbin/sha256 -q "$_native_path" 2>/dev/null)" || return 0
[ "$_native_hash" = "${_native_name#hook-status-}" ] || return 0

_native_status=0
{ _native_receipt="$("$_native_path" --exec "$0" 3>&1 1>&4)" || _native_status=$?; } 4>&1
case "$_native_receipt" in
  A) [ "$_native_status" -eq 0 ] && exit 0 ;;
  F) exit "$_native_status" ;;
esac
printf '%s\n' 'BLOCKED: native guard could not complete safely.' >&2
exit 2
