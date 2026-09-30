#!/bin/bash
# First-run setup: install Homebrew and Xcode CLT if missing.
# chezmoi runs this exactly once (tracked by script name hash).
set -euo pipefail

# ── Xcode Command Line Tools ────────────────────────────────────
if ! xcode-select -p &>/dev/null; then
  echo "→ Installing Xcode Command Line Tools..."
  xcode-select --install
  echo ""
  echo "Xcode CLT installer opened. After it completes, re-run: chezmoi apply"
  exit 1
fi
echo "✓ Xcode Command Line Tools"

# ── Homebrew ────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  echo "→ Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Add brew to PATH for the rest of this script
  if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -f /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi
echo "✓ Homebrew $(brew --version | head -1)"

# ── Essential tools needed by other scripts ─────────────────────
if ! command -v chezmoi &>/dev/null; then
  brew install chezmoi
fi

# ── Git identity (gitconfig.local) ──────────────────────────────
# Resolve DOTFILES_DIR robustly — chezmoi may invoke this script from a
# tmpdir-staged copy where `dirname $0/..` would point to the tmpdir's
# parent, not the dotfiles checkout. The `||` fallback in the previous
# implementation never fired because `cd <tmpdir>/..` succeeds; the
# gitconfig.local.example copy then silently skipped. Same shape used by
# `run_after_agentbrew-sync.sh::_resolve_dotfiles_dir` — probe
# `dirname $0/..` first (works when run from the repo directly), fall
# back to `chezmoi source-path` (chezmoi is installed above this line),
# then check the two known checkout layouts. Marker file
# `gitconfig.local.example` confirms we landed in the right repo.
_resolve_dotfiles_dir() {
  local candidate
  candidate="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd || true)"
  [ -n "$candidate" ] && [ -f "$candidate/gitconfig.local.example" ] && { printf '%s' "$candidate"; return 0; }

  if command -v chezmoi &>/dev/null; then
    candidate="$(chezmoi source-path 2>/dev/null || true)"
    [ -n "$candidate" ] && [ -f "$candidate/gitconfig.local.example" ] && { printf '%s' "$candidate"; return 0; }
  fi

  for candidate in \
    "${DOTFILES_REPOS_DIR:-$HOME/apps}/dotfiles" \
    "${DOTFILES_REPOS_DIR:-$HOME/apps}/tooling/dotfiles"
  do
    [ -f "$candidate/gitconfig.local.example" ] && { printf '%s' "$candidate"; return 0; }
  done
  return 1
}
DOTFILES_DIR="$(_resolve_dotfiles_dir || true)"
if [ -z "$DOTFILES_DIR" ]; then
  echo "○ Could not resolve dotfiles repo path — skipping gitconfig.local setup. Run \`dotfiles apply\` after the checkout lands at \$DOTFILES_REPOS_DIR/{dotfiles,tooling/dotfiles}." >&2
  # Continue rather than exit — Homebrew + Xcode CLT setup above is more
  # critical than gitconfig.local. The next `dotfiles apply` will retry.
  DOTFILES_DIR=""
fi
GITCONFIG_LOCAL="$HOME/.gitconfig.local"
GITCONFIG_EXAMPLE="$DOTFILES_DIR/gitconfig.local.example"
if [ ! -f "$GITCONFIG_LOCAL" ] && [ -f "$GITCONFIG_EXAMPLE" ]; then
  echo ""
  echo "→ Setting up git identity (~/.gitconfig.local)..."
  cp "$GITCONFIG_EXAMPLE" "$GITCONFIG_LOCAL"
  git_name=""
  while [ -z "$git_name" ]; do
    printf "  Your name (required): "
    read -r git_name
  done
  git_email=""
  while [ -z "$git_email" ]; do
    printf "  Your email (required): "
    read -r git_email
  done
  # Escape special characters for sed replacement (handles / \ & |)
  _sed_escape() { printf '%s' "$1" | sed 's/[\\&|]/\\&/g'; }
  if [ -n "$git_name" ]; then
    sed -i.bak "s|Your Name|$(_sed_escape "$git_name")|" "$GITCONFIG_LOCAL" && rm -f "$GITCONFIG_LOCAL.bak"
  fi
  if [ -n "$git_email" ]; then
    sed -i.bak "s|your@email.com|$(_sed_escape "$git_email")|" "$GITCONFIG_LOCAL" && rm -f "$GITCONFIG_LOCAL.bak"
  fi
  echo "✓ Created ~/.gitconfig.local"
fi

echo "✓ Bootstrap complete"
