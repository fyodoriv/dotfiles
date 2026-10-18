#!/bin/bash
# Back-compat wrapper — superseded by run_at_login_endpoint-bootstrap.sh.
set -euo pipefail

# Endpoint hardening writes outside $HOME. .chezmoi.yaml.tmpl sets
# DOTFILES_ENDPOINT_HARDENING from endpoint_hardening (default: owner_machine);
# unset keeps the old behaviour. A managed endpoint (safe mode) always hardens.
if [ "${DOTFILES_ENDPOINT_HARDENING:-1}" = "0" ] && [ "${DOTFILES_MANAGED_ENDPOINT:-0}" != "1" ]; then
  echo "○ Skipping endpoint hardening (endpoint_hardening is false)"
  exit 0
fi

_resolve_bootstrap() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null || true)"
  if [ -x "$script_dir/run_at_login_endpoint-bootstrap.sh" ]; then
    printf '%s/run_at_login_endpoint-bootstrap.sh\n' "$script_dir"
    return 0
  fi
  for candidate in \
    "$HOME/apps/tooling/dotfiles" \
    "$HOME/apps/dotfiles" \
    "$HOME/dotfiles"; do
    if [ -x "$candidate/.chezmoiscripts/run_at_login_endpoint-bootstrap.sh" ]; then
      printf '%s/.chezmoiscripts/run_at_login_endpoint-bootstrap.sh\n' "$candidate"
      return 0
    fi
  done
  return 1
}

_bootstrap="$(_resolve_bootstrap || true)"
if [ -z "$_bootstrap" ]; then
  echo "⚠ run_at_login_endpoint-bootstrap.sh not found — skipping login sign" >&2
  exit 0
fi
exec "$_bootstrap" "$@"
