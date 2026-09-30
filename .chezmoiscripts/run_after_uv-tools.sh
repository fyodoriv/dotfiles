#!/bin/bash
# Install python-based CLI tools as uv tools instead of Homebrew formulae.
# The brew formulae (poetry, httpie, jrnl, pipx) pull python@3.x, whose
# binaries endpoint agents flag on every spawn. uv tools live
# under ~/.local/share/uv/tools with a signed uv-managed python — no admin
# path, no policy dialogs. See AGENTS.md rule #10 and the arm64 Homebrew
# migration (these were removed from run_onchange_brew.sh.tmpl).
#
# Runs after brew bundle (which installs uv) on every `dotfiles apply`.
# Idempotent — `uv tool install` is a no-op when the tool is already present.
set -euo pipefail

if ! command -v uv &>/dev/null; then
  echo "⚠ uv not found — skipping uv-tool installs (brew bundle should install uv first)"
  exit 0
fi

# httpie ships the `http`/`https` commands; jrnl, poetry, pipx ship eponymous
# executables. awscli is NOT here — AWS CLI v2 is not on PyPI; it is installed
# via the AWS user-dir pkg (see TASKS.md "user-dir-installers-for-aws-gcloud").
_allow_python_install=true
_endpoint_lib="${CHEZMOI_SOURCE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/lib/dotfiles-endpoint-paths.sh"
# shellcheck source=/dev/null
[ -f "$_endpoint_lib" ] && source "$_endpoint_lib"
if [ "$(uname -s)" = "Darwin" ] \
    && declare -F dotfiles_managed_endpoint >/dev/null \
    && dotfiles_managed_endpoint \
    && [ "${DOTFILES_ALLOW_PUBLISHER_NA_PYTHON:-0}" != "1" ]; then
  _allow_python_install=false
fi
for tool in poetry jrnl httpie pipx; do
  if uv tool list 2>/dev/null | grep -q "^${tool} "; then
    continue
  fi
  if ! $_allow_python_install; then
    echo "○ uv tool install ${tool} skipped (endpoint-policy safe mode)"
    continue
  fi
  echo "→ uv tool install ${tool}"
  uv tool install "$tool" || echo "⚠ uv tool install ${tool} failed — continuing"
done
unset _allow_python_install

echo "✓ uv-managed CLI tools up to date"
