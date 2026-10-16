#!/bin/bash
# Doctor checks for upgrade module — ensures software stays up to date.

LAST_UPGRADE_FILE="$HOME/.local/share/dotfiles/last-upgrade"
MAX_STALE_DAYS=14

# Skip the auto-upgrade checks entirely when the operator opted out via
# chezmoi data (`auto_upgrade: false`). The lifecycle script already
# refuses to install the LaunchAgent in that case
# (.chezmoiscripts/run_onchange_launchagents.sh.tmpl `should_skip_agent
# dotfiles-upgrade` branch), so the doctor flagging both checks as failed is a
# false negative.
_AUTO_UPGRADE_ENABLED="$(chezmoi execute-template '{{ dig "auto_upgrade" "false" . }}' 2>/dev/null || echo "false")"
if [ "$_AUTO_UPGRADE_ENABLED" = "true" ]; then
  # ── LaunchAgent loaded ──────────────────────────────────────────────
  check "upgrade.launchagent" "upgrade launchagent loaded" \
    "launchctl list com.dotfiles.dotfiles-upgrade 2>/dev/null | grep -q Label" \
    ""

  # ── Last upgrade was recent (within 14 days) ────────────────────────
  _upgrade_recent() {
    [ -f "$LAST_UPGRADE_FILE" ] || return 1
    local last_epoch now_epoch
    last_epoch=$(cat "$LAST_UPGRADE_FILE" 2>/dev/null) || return 1
    [[ "$last_epoch" =~ ^[0-9]+$ ]] || return 1
    now_epoch=$(date "+%s")
    [ $((now_epoch - last_epoch)) -lt $((MAX_STALE_DAYS * 86400)) ]
  }
  check "upgrade.recent" "last upgrade within ${MAX_STALE_DAYS} days (fix: dotfiles upgrade)" "_upgrade_recent" ""
fi

# ── Homebrew installed ──────────────────────────────────────────────
check "upgrade.brew" "brew installed (fix: https://brew.sh)" "command -v brew" ""

# ── Casks blocked by privilege management absent (managed Macs) ────
# Raycast install/upgrade needs a privilege elevation (admin). It is
# never in the dotfiles Brewfile; if present it was installed manually and
# topgrade's greedy_cask step will try to upgrade it every dotfiles upgrade.
if [ "$(chezmoi execute-template '{{ dig "is_enterprise" "false" . }}' 2>/dev/null || echo "false")" = "true" ]; then
  check "upgrade.no-raycast" "raycast not installed (blocked by privilege management — fix: brew uninstall --cask raycast)" \
    "! brew list --cask raycast &>/dev/null" ""
fi

# ── Non-uv poetry still runs ────────────────────────────────────────
# The official-installer poetry (~/.local/bin/poetry plus
# ~/Library/Application Support/pypoetry/venv) is pinned to the Python it
# was installed with. When that Python is removed, `poetry` and topgrade's
# poetry step fail on every upgrade, and run_after_uv-tools.sh skips
# `uv tool install poetry` because the file is "not uv-managed".
_poetry_bin="$(command -v poetry 2>/dev/null || true)"
if [ -n "$_poetry_bin" ]; then
  _poetry_uv_dir="$(uv tool dir 2>/dev/null || true)"
  _poetry_target="$(readlink "$_poetry_bin" 2>/dev/null || echo "$_poetry_bin")"
  if [ -z "$_poetry_uv_dir" ] || [[ "$_poetry_target" != "$_poetry_uv_dir"/* ]]; then
    check "upgrade.poetry_runs" \
      "non-uv poetry at $_poetry_bin runs (fix: mv '$_poetry_bin' '$_poetry_bin.bak' && mv ~/Library/Application\\ Support/pypoetry/venv ~/Library/Application\\ Support/pypoetry/venv.bak && uv tool install poetry)" \
      "'$_poetry_bin' --version" ""
  fi
fi
unset _poetry_bin _poetry_uv_dir _poetry_target
