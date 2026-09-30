#!/bin/bash
# Re-sign Homebrew bottles and uv pythons on every chezmoi apply.
#
# endpoint agent flags unsigned Mach-O binaries (unsigned). brew install
# and brew upgrade re-extract unsigned bottles; this script closes drift between
# brew bundle changes and weekly topgrade runs.
set -euo pipefail

_resolve_dotfiles_bin_dir() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd 2>/dev/null || true)"
  if [ -x "$script_dir/bin/dotfiles-adhoc-sign-bottles" ]; then
    printf '%s/bin\n' "$script_dir"
    return 0
  fi
  # chezmoi runs this from a temp copy; its source dir is the applied checkout.
  for candidate in \
    "${CHEZMOI_SOURCE_DIR:-}" \
    "${DOTFILES_DIR:-}" \
    "$HOME/apps/tooling/dotfiles" \
    "$HOME/apps/dotfiles" \
    "$HOME/dotfiles"; do
    [ -n "$candidate" ] || continue
    if [ -x "$candidate/bin/dotfiles-adhoc-sign-bottles" ]; then
      printf '%s/bin\n' "$candidate"
      return 0
    fi
  done
  return 1
}

_bin_dir="$(_resolve_dotfiles_bin_dir || true)"
if [ -z "$_bin_dir" ]; then
  echo "⚠ dotfiles endpoint-security helpers not found — skipping ad-hoc re-sign"
  exit 0
fi

export DOTFILES_ADHOC_SIGN_QUIET=1
# Fast jq + curl sign + link FIRST — closes post-reboot race with minsky daemon/tick-loop.
"$_bin_dir/dotfiles-adhoc-sign-jq"
if [ -x "$_bin_dir/dotfiles-adhoc-sign-curl" ]; then
  "$_bin_dir/dotfiles-adhoc-sign-curl"
fi
if [ -x "$_bin_dir/dotfiles-adhoc-sign-ggrep" ]; then
  "$_bin_dir/dotfiles-adhoc-sign-ggrep"
fi
if [ -x "$_bin_dir/dotfiles-link-jq-shim" ]; then
  "$_bin_dir/dotfiles-link-jq-shim"
fi
if [ -x "$_bin_dir/dotfiles-link-curl-shim" ]; then
  "$_bin_dir/dotfiles-link-curl-shim"
fi
# Sign uv pythons + refresh python shims before LaunchAgents test-execute python3.13.
"$_bin_dir/dotfiles-adhoc-sign-uv-pythons"
if [ -x "$_bin_dir/dotfiles-link-python-shim" ]; then
  "$_bin_dir/dotfiles-link-python-shim"
fi
"$_bin_dir/dotfiles-adhoc-sign-bottles"
if [ -x "$_bin_dir/dotfiles-link-grep-shim" ]; then
  "$_bin_dir/dotfiles-link-grep-shim"
fi
if [ -x "$_bin_dir/dotfiles-link-sed-shim" ]; then
  "$_bin_dir/dotfiles-link-sed-shim"
fi
if [ -x "$_bin_dir/dotfiles-link-awk-shim" ]; then
  "$_bin_dir/dotfiles-link-awk-shim"
fi
if [ -x "$_bin_dir/dotfiles-link-find-shim" ]; then
  "$_bin_dir/dotfiles-link-find-shim"
fi
if [ -x "$_bin_dir/dotfiles-link-otool-shim" ]; then
  "$_bin_dir/dotfiles-link-otool-shim"
fi
if [ -x "$_bin_dir/dotfiles-link-perl-shim" ]; then
  "$_bin_dir/dotfiles-link-perl-shim"
fi
if [ -x "$_bin_dir/dotfiles-link-git-shim" ]; then
  "$_bin_dir/dotfiles-link-git-shim"
fi
if [ -x "$_bin_dir/dotfiles-link-homebrew-gnu-sandbox-aliases" ]; then
  "$_bin_dir/dotfiles-link-homebrew-gnu-sandbox-aliases"
fi
if [ -x "$_bin_dir/dotfiles-fix-launchagent-endpoint-path" ]; then
  "$_bin_dir/dotfiles-fix-launchagent-endpoint-path"
fi
if [ -x "$_bin_dir/dotfiles-ensure-gui-path" ]; then
  "$_bin_dir/dotfiles-ensure-gui-path" || true
fi
"$_bin_dir/dotfiles-adhoc-sign-endpoint-shims"
echo "✓ Endpoint-security tool signatures refreshed (Homebrew bottles + uv pythons + curl/jq/python/grep/sed/awk/find/otool/perl/git symlinks + endpoint shims + LaunchAgent PATH + gui-path)"
