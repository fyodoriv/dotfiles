#!/bin/bash
# Ensure uv-managed python is available for pipx and venvs.
# endpoint agent flags any binary whose path contains Python.framework —
# both Homebrew and python.org pythons trigger this. uv-managed python
# lives at ~/.local/share/uv/python/ with no framework path.
#
# Also ensures Homebrew curl is installed (keg-only, needs PATH priority
# via home/zshrc — the PATH line is already there).
#
# This runs after brew bundle (which installs uv + curl) on every
# `dotfiles apply`. Idempotent — skips if already installed.
set -euo pipefail

# Ignore python.org / Homebrew framework installs during uv discovery (endpoint-safe).
export UV_PYTHON_PREFERENCE=only-managed

# ── uv python ────────────────────────────────────────────────────
if command -v uv &>/dev/null; then
  # Detect architecture for the right python build
  arch="$(uname -m)"
  case "$arch" in
    arm64)  platform="macos-aarch64-none" ;;
    x86_64) platform="macos-x86_64-none" ;;
    *)      platform="" ;;
  esac

  # Install python 3.13 if not already present
  if [ -n "$platform" ]; then
    target_dir="$HOME/.local/share/uv/python"
    if ! ls "$target_dir"/cpython-3.13*-"$platform" &>/dev/null; then
      echo "→ Installing uv python 3.13 ($arch)..."
      uv python install 3.13
      echo "✓ uv python 3.13 installed"
    else
      echo "✓ uv python 3.13 already installed ($arch)"
    fi
  fi

  # ── Ad-hoc sign uv pythons (endpoint agent) ─────────────────────
  # uv ships python-build-standalone binaries unsigned. endpoint agent flags
  # unsigned binaries — fires the policy dialog on every
  # python3.1x spawn. The shared bin/dotfiles-adhoc-sign-uv-pythons helper
  # ad-hoc signs them (`codesign --sign -` → Signature=adhoc, which endpoint agent
  # accepts as signed). It is the SINGLE source of truth: the topgrade
  # [post_commands] block calls the same script after `dotfiles upgrade`
  # (whose `uv python upgrade` re-extracts and re-unsigns pythons). Locate it
  # relative to this script when run from the repo, else via the known path
  # (chezmoi runs run_after_* scripts detached from the source tree) — same
  # dual-locate pattern as run_onchange_brew.sh.tmpl.
  _dotfiles_bin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../bin" 2>/dev/null && pwd || echo "")"
  if [ -x "$_dotfiles_bin_dir/dotfiles-adhoc-sign-uv-pythons" ]; then
    "$_dotfiles_bin_dir/dotfiles-adhoc-sign-uv-pythons"
  elif [ -x "$HOME/apps/tooling/dotfiles/bin/dotfiles-adhoc-sign-uv-pythons" ]; then
    "$HOME/apps/tooling/dotfiles/bin/dotfiles-adhoc-sign-uv-pythons"
  else
    echo "⚠ dotfiles-adhoc-sign-uv-pythons not found — uv pythons may trigger endpoint agent"
  fi
else
  echo "⚠ uv not found — skipping python setup (brew install uv first)"
fi

# ── Homebrew curl (keg-only) ─────────────────────────────────────
if command -v brew &>/dev/null; then
  if ! brew list curl &>/dev/null 2>&1; then
    echo "→ Installing Homebrew curl..."
    brew install curl
    echo "✓ Homebrew curl installed (keg-only — PATH priority via zshrc)"
  fi
fi

# ── Expose uv python on PATH for hardcoded callers ────────────────
# Homebrew python's real binary lives inside Python.framework/ which
# endpoint agent flags. Symlink uv python so GUI apps, LaunchAgents, and
# scripts with hardcoded paths get framework-free python.
#
# On native arm64 Apple Silicon, use ~/.local/bin (already on PATH) — NOT
# /usr/local/bin, which is the Intel/Rosetta Homebrew prefix and perpetuates
# x86 tool resolution + Rosetta warnings. On Intel / Rosetta shells, keep
# /usr/local/bin for legacy hardcoded callers.
if command -v uv &>/dev/null; then
  uv_python="$(uv python find 3.13 2>/dev/null || echo "")"
  if [ -n "$uv_python" ] && [ -x "$uv_python" ]; then
    uv_dir="$(dirname "$uv_python")"
    if [ "$(uname -m)" = "arm64" ] && [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" != "1" ]; then
      _py_link_dir="$HOME/.local/bin"
      # Legacy apply runs symlinked uv python into /usr/local/bin (Intel prefix).
      # On native arm64 that perpetuates Rosetta resolution and lets LaunchAgents
      # whose PATH is /usr/local/bin:… hit python3.13 before dotfiles shims.
      for _legacy in python python3 python3.13 pip3; do
        _legacy_path="/usr/local/bin/$_legacy"
        if [ -L "$_legacy_path" ] && readlink "$_legacy_path" | grep -q '.local/share/uv/python'; then
          rm -f "$_legacy_path" 2>/dev/null && echo "  ✓ removed legacy $_legacy_path (arm64 uses ~/.local/bin only)"
        fi
      done
      unset _legacy _legacy_path
    else
      _py_link_dir="/usr/local/bin"
    fi
    mkdir -p "$_py_link_dir"
    # Replace the key symlinks (owned by user, not root)
    for name in python python3 python3.13; do
      target="$_py_link_dir/$name"
      if [ -L "$target" ] || [ ! -e "$target" ]; then
        ln -sf "$uv_python" "$target" 2>/dev/null && echo "  ✓ $_py_link_dir/$name → $uv_python"
      fi
    done
    # pip3 if available
    uv_pip="$uv_dir/pip3.13"
    if [ -x "$uv_pip" ]; then
      ln -sf "$uv_pip" "$_py_link_dir/pip3" 2>/dev/null && echo "  ✓ $_py_link_dir/pip3 → $uv_pip"
    fi
    unset _py_link_dir
    # Refresh python3 shim cache so stale paths don't exec deleted uv builds
    mkdir -p "$HOME/.cache/dotfiles"
    echo "$uv_python" > "$HOME/.cache/dotfiles/uv-python3-path"
    # Unlink Homebrew python so it can't recreate framework symlinks
    brew unlink python@3.13 2>/dev/null || true
    brew unlink python@3.14 2>/dev/null || true
    # Replace bash python shims with symlinks to signed uv Mach-O (endpoint agent unsigned fix)
    if [ -x "$_dotfiles_bin_dir/dotfiles-link-python-shim" ]; then
      "$_dotfiles_bin_dir/dotfiles-link-python-shim"
    elif [ -x "$HOME/apps/tooling/dotfiles/bin/dotfiles-link-python-shim" ]; then
      "$HOME/apps/tooling/dotfiles/bin/dotfiles-link-python-shim"
    fi
  fi
fi

# ── pipx default python ─────────────────────────────────────────
# If pipx is installed and using a Python.framework python, warn.
# The operator should rebuild: pipx reinstall-all --python $(uv python find 3.13)
if command -v pipx &>/dev/null && [ -d "$HOME/.local/pipx/venvs" ]; then
  framework_count=0
  for cfg in "$HOME"/.local/pipx/venvs/*/pyvenv.cfg; do
    [ -f "$cfg" ] || continue
    if grep -q "Python.framework" "$cfg" 2>/dev/null; then
      framework_count=$((framework_count + 1))
    fi
  done
  if [ "$framework_count" -gt 0 ]; then
    echo "⚠ $framework_count pipx venv(s) use Python.framework (endpoint agent will flag them)"
    echo "  Fix: for each package, run:"
    echo "    pipx uninstall <pkg> && pipx install --python \$(uv python find 3.13) <pkg>"
  fi
fi

# ── uv: launchctl-wide only-managed python preference ────────────
# Propagate UV_PYTHON_PREFERENCE=only-managed to ALL processes spawned by
# launchd — including LaunchAgents (com.minsky.auto-merge, com.minsky.runany,
# etc.) that fire periodically and ignore ~/.zshenv. Without this, those
# agents go through `python3` → dotfiles shim → uv discovery which may
# probe a Python.framework binary and trigger the endpoint-agent popup.
#
# Combined with the zshenv export (covers interactive shells), this gives
# both shell-context and launchd-context coverage.
#
# Idempotent — `launchctl setenv` just overwrites the existing value.
launchctl setenv UV_PYTHON_PREFERENCE only-managed 2>/dev/null && \
  echo "✓ launchctl: UV_PYTHON_PREFERENCE=only-managed (covers LaunchAgents + GUI apps)"

# ── Check for framework Python install (operator action needed) ──
# The dotfiles symlinks redirect /usr/local/bin/python* to uv-managed, but
# /Library/Frameworks/Python.framework can still be invoked directly by
# any tool that hardcodes that path. Removal requires sudo and can't be
# automated from this script (chezmoi apply doesn't elevate). Surface the
# fix script for the operator.
if [ -d "/Library/Frameworks/Python.framework" ]; then
  echo "⚠ /Library/Frameworks/Python.framework exists — endpoint agent will keep blocking it."
  echo "  Fix (one-time, requires sudo): run in a non-agent terminal —"
  echo "    dotfiles-remove-framework-python"
fi
