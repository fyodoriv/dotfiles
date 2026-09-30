#!/bin/bash
# Fast login bootstrap: sign uv pythons + jq + curl + ggrep, link shims, publish ready sentinel.
#
# Runs at RunAtLoad via com.dotfiles.endpoint-bootstrap BEFORE minsky tick-loop
# and other high-churn LaunchAgents. Closes post-reboot races where supervised
# loops exec jq, curl, or python3.13 before adhoc-sign-bottles / link-*-shim complete.
set -euo pipefail

_resolve_dotfiles_bin() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd 2>/dev/null || true)"
  if [ -x "$script_dir/bin/dotfiles-adhoc-sign-uv-pythons" ]; then
    printf '%s/bin\n' "$script_dir"
    return 0
  fi
  for candidate in \
    "$HOME/apps/tooling/dotfiles" \
    "$HOME/apps/dotfiles" \
    "$HOME/dotfiles"; do
    if [ -x "$candidate/bin/dotfiles-adhoc-sign-uv-pythons" ]; then
      printf '%s/bin\n' "$candidate"
      return 0
    fi
  done
  return 1
}

_bin_dir="$(_resolve_dotfiles_bin || true)"
if [ -z "$_bin_dir" ]; then
  echo "⚠ dotfiles endpoint-bootstrap helpers not found — skipping login bootstrap"
  exit 0
fi

_ready_dir="${HOME}/.local/state/dotfiles"
_ready_file="$_ready_dir/endpoint-ready"
mkdir -p "$_ready_dir"
rm -f "$_ready_file"

export DOTFILES_ADHOC_SIGN_QUIET=1
"$_bin_dir/dotfiles-adhoc-sign-jq"
if [ -x "$_bin_dir/dotfiles-adhoc-sign-curl" ]; then
  "$_bin_dir/dotfiles-adhoc-sign-curl"
fi
if [ -x "$_bin_dir/dotfiles-adhoc-sign-ggrep" ]; then
  "$_bin_dir/dotfiles-adhoc-sign-ggrep"
fi
"$_bin_dir/dotfiles-adhoc-sign-uv-pythons"
if [ -x "$_bin_dir/dotfiles-link-jq-shim" ]; then
  "$_bin_dir/dotfiles-link-jq-shim"
fi
if [ -x "$_bin_dir/dotfiles-link-curl-shim" ]; then
  "$_bin_dir/dotfiles-link-curl-shim"
fi
if [ -x "$_bin_dir/dotfiles-link-grep-shim" ]; then
  "$_bin_dir/dotfiles-link-grep-shim"
fi
if [ -x "$_bin_dir/dotfiles-link-python-shim" ]; then
  "$_bin_dir/dotfiles-link-python-shim"
fi

touch "$_ready_file"
echo "✓ endpoint-bootstrap: jq + curl + ggrep + uv python signed, shims linked, sentinel ready"
