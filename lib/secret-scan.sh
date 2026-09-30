#!/bin/bash
# Shared tracked-file secret scanner for validate and security doctor.

DOTFILES_SECRET_PATTERNS="(API_KEY|SECRET_KEY|PRIVATE_KEY|ACCESS_TOKEN|AUTH_TOKEN|PASSWORD|CLIENT_SECRET)=['\"]?[A-Za-z0-9+/=_-]{8,}"

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
  local rel tracked_file match_line found

  while IFS= read -r -d '' rel; do
    [ -n "$rel" ] || continue
    tracked_file="$repo_dir/$rel"
    [ -f "$tracked_file" ] || continue
    dotfiles_secret_scan_is_fixture_path "$rel" && continue
    # Let grep decide binary-vs-text; file(1) can misclassify key-like fixtures.
    grep -Iq . "$tracked_file" 2>/dev/null || continue

    found=0
    while IFS= read -r match_line; do
      dotfiles_secret_scan_match_allowlisted "$match_line" && continue
      found=1
      break
    done < <(grep -EnI "$DOTFILES_SECRET_PATTERNS" "$tracked_file" 2>/dev/null)

    [ "$found" -eq 1 ] && printf '%s\n' "$rel"
  done < <(git -C "$repo_dir" ls-files -z 2>/dev/null)
  return 0
}
