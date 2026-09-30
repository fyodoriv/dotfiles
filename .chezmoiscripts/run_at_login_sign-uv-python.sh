#!/bin/bash
# Back-compat wrapper — superseded by run_at_login_endpoint-bootstrap.sh.
set -euo pipefail

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
