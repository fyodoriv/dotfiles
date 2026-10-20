#!/bin/bash
# Run a hook command with endpoint-safe PATH (dotfiles shims first).
#
# Agents can run each hook command in an isolated subprocess — PATH set by
# SessionStart does not propagate. Wrap external hooks so jq, find, curl,
# perl resolve to adhoc-signed Mach-O shims instead of /usr/bin/* or
# unsigned Homebrew bottles.
#
# Example:
#   ~/.config/dotfiles/hooks/with-endpoint-path.sh <hook-command> [args...]

set -euo pipefail

unset BASH_ENV ENV

_hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bootstrap-endpoint-path.sh
source "$_hook_dir/bootstrap-endpoint-path.sh"

if [ "$#" -lt 1 ]; then
  echo "usage: with-endpoint-path.sh <command> [args...]" >&2
  exit 1
fi

exec "$@"
