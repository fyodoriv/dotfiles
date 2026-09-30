#!/bin/bash
# Cache shell tool inits for fast zsh startup.
# Runs after every chezmoi apply to keep caches fresh.
set -euo pipefail

# Each tool's cache is rebuilt via a temp file + mv so a failing tool
# never overwrites a previously-good cache with an empty file. Without
# this pattern, `tool > "$cache"` truncates the cache to zero bytes
# before the tool runs, and a broken upgrade can leave new login shells
# unable to load the prompt or completion definitions.
cache_init() {
  local label="$1" cache="$2"
  shift 2
  local tmp
  tmp="$(mktemp "${cache}.XXXXXX")" || return 1
  if "$@" >"$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv "$tmp" "$cache"
    echo "✓ Cached ${label} init"
  else
    rm -f "$tmp"
    return 1
  fi
}

if ! mkdir -p "$HOME/.cache/zsh" "$HOME/.cache/node-compile" "$HOME/.notes"; then
  echo "✗ Could not create cache directories under $HOME/.cache" >&2
  exit 1
fi

# XDG user-binary dir — shim-style tools (minsky, etc.) install themselves
# by symlinking here, and zshrc unconditionally puts it on PATH.
if ! mkdir -p "$HOME/.local/bin"; then
  echo "✗ Could not create $HOME/.local/bin" >&2
  exit 1
fi

if command -v fzf &>/dev/null; then
  cache_init fzf "$HOME/.cache/zsh/fzf.zsh" fzf --zsh || true
fi

if command -v zoxide &>/dev/null; then
  cache_init zoxide "$HOME/.cache/zsh/zoxide.zsh" zoxide init zsh --cmd cd || true
fi

if command -v starship &>/dev/null; then
  cache_init starship "$HOME/.cache/zsh/starship.zsh" starship init zsh || true
fi

if command -v fnm &>/dev/null; then
  fnm_arch="$(uname -m | sed 's/x86_64/x64/')"
  cache_init fnm "$HOME/.cache/zsh/fnm.zsh" \
    fnm env --arch "$fnm_arch" --use-on-cd --corepack-enabled --version-file-strategy=recursive --shell zsh \
    || true
fi
