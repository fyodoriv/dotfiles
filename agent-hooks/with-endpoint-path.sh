#!/bin/bash
# Run a hook command with endpoint-safe PATH (dotfiles shims first).
#
# Cursor runs each hooks.json command in an isolated subprocess — PATH set by
# sessionStart does not propagate. Wrap codeassist / audit hooks so jq, find,
# curl, perl resolve to adhoc-signed Mach-O shims instead of /usr/bin/* or
# unsigned Homebrew bottles.
#
# hooks.json example:
#   ~/.config/dotfiles/hooks/with-endpoint-path.sh \
#     ~/.cursor/codeassist/hooks-scripts/audit-logger.sh afterFileEdit

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
