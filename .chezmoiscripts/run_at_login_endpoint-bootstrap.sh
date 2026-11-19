#!/bin/bash
# Fast login bootstrap: sign uv pythons + jq + curl + ggrep, link shims, publish ready sentinel.
#
# Runs at RunAtLoad via com.dotfiles.endpoint-bootstrap BEFORE other high-churn LaunchAgents. Closes post-reboot races where supervised
# loops exec jq, curl, or python3.13 before adhoc-sign-bottles / link-*-shim complete.
set -euo pipefail

# Endpoint hardening writes outside $HOME. .chezmoi.yaml.tmpl sets
# DOTFILES_ENDPOINT_HARDENING from endpoint_hardening (default: owner_machine);
# unset keeps the old behaviour. A managed endpoint (safe mode) always hardens.
if [ "${DOTFILES_ENDPOINT_HARDENING:-1}" = "0" ] && [ "${DOTFILES_MANAGED_ENDPOINT:-0}" != "1" ]; then
  echo "○ Skipping endpoint hardening (endpoint_hardening is false)"
  exit 0
fi

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
# On a first install Homebrew jq/curl/grep are not there yet (this script sorts
# before run_onchange_brew); run_after_endpoint-security links them later in
# the same apply.
for _tool in jq curl grep; do
  if [ -x "$_bin_dir/dotfiles-link-$_tool-shim" ]; then
    "$_bin_dir/dotfiles-link-$_tool-shim" ||
      echo "⚠ Homebrew $_tool not installed yet — run_after_endpoint-security links it"
  fi
done
if [ -x "$_bin_dir/dotfiles-link-python-shim" ]; then
  # On a first install uv python is not there yet; run_after_uv-python-setup
  # installs it and links the shim later in the same apply.
  "$_bin_dir/dotfiles-link-python-shim" ||
    echo "⚠ uv-managed python not installed yet — run_after_uv-python-setup links it"
fi

touch "$_ready_file"
echo "✓ endpoint-bootstrap: jq + curl + ggrep + uv python signed, shims linked, sentinel ready"
