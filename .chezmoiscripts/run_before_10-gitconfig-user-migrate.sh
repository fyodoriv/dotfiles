#!/bin/bash
# Keep identity out of the chezmoi-managed ~/.gitconfig so apply never prompts.
# A [user] section there is drift; chezmoi would ask to overwrite it, and the
# prompt fails without a TTY. Move it to ~/.gitconfig.local first.
# Never fails the apply: a git error here only means the drift stays.
set -uo pipefail

src="${CHEZMOI_SOURCE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/gitconfig-user-migrate.sh
source "$src/lib/gitconfig-user-migrate.sh" || exit 0
gitconfig_user_migrate || echo "gitconfig: [user] migration failed; leaving ~/.gitconfig as is" >&2
exit 0
