#!/bin/bash
# Shared tracked-file secret scanner for validate and security doctor.

DOTFILES_SECRET_PATTERNS="(API_KEY|SECRET_KEY|PRIVATE_KEY|ACCESS_TOKEN|AUTH_TOKEN|PASSWORD|CLIENT_SECRET)=['\"]?[A-Za-z0-9+/=_-]{8,}"

DOTFILES_BEARER_PATTERN='Bearer [A-Za-z0-9._~+/=-]{20,}'

# Backups and crash leftovers of ~/.claude.json keep whatever the live file
# once held, including hand-added literal tokens. The live file is excluded:
# agentbrew owns it and warns about hardcoded secrets on every sync.
dotfiles_agent_config_backups() {
  local f
  for f in "$HOME"/.claude.json.* "$HOME"/.config/agentbrew/backups/*/claude.json*; do
    [ -f "$f" ] && printf '%s\n' "$f"
  done
}

dotfiles_agent_config_bearer_leaks() {
  local f
  while IFS= read -r f; do
    grep -Eo "$DOTFILES_BEARER_PATTERN" "$f" 2>/dev/null | grep -vq '^Bearer REDACTED' && printf '%s\n' "$f"
  done < <(dotfiles_agent_config_backups)
  return 0
}

dotfiles_redact_agent_config_bearer_leaks() {
  local f
  while IFS= read -r f; do
    /usr/bin/perl -pi -e 's/Bearer (?!REDACTED)[A-Za-z0-9._~+\/=-]{20,}/Bearer REDACTED/g' "$f" || return 1
  done < <(dotfiles_agent_config_bearer_leaks)
}

dotfiles_secret_scan_is_fixture_path() {
  local rel="$1"

  case "$rel" in
    tests/audit_fixture.bats) return 0 ;;
  esac

  return 1
}

dotfiles_secret_scan_match_allowlisted() {
  local match_line="$1"

  case "$match_line" in
    *"# dotfiles-secret-allowlist:"?*) return 0 ;;
  esac

  return 1
}

dotfiles_scan_tracked_secrets() {
  local repo_dir="${1:-${DOTFILES_DIR:-.}}"
  local rel match_line last_reported=""

  # One batched grep over all tracked files: a grep per file cost about 50s
  # on a busy Mac. -I skips binary files; --null ends each file name with NUL;
  # /dev/null keeps grep off stdin when the file list is empty.
  while IFS= read -r -d '' rel && IFS= read -r match_line; do
    [ "$rel" = "$last_reported" ] && continue
    dotfiles_secret_scan_match_allowlisted "$match_line" && continue
    printf '%s\n' "$rel"
    last_reported="$rel"
  done < <(
    cd "$repo_dir" 2>/dev/null || exit 0
    git ls-files -z 2>/dev/null |
      while IFS= read -r -d '' rel; do
        [ -n "$rel" ] && [ -f "$rel" ] || continue
        dotfiles_secret_scan_is_fixture_path "$rel" && continue
        printf '%s\0' "$rel"
      done |
      xargs -0 grep -EnIH --null -- "$DOTFILES_SECRET_PATTERNS" /dev/null 2>/dev/null
  )
  return 0
}
