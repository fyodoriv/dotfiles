#!/bin/bash
# Only the caller's temporary Brewfile changes. Metadata and deferred tokens
# belong to one preflight invocation; no Homebrew or app state is changed.
brew_defer_foreign_apps() (
  local manifest="$1" deferred="$2" metadata="" filtered="" candidate_rows="" token app owner current_uid seen="" candidate
  local -a casks
  casks=()
  command -v jq >/dev/null 2>&1 || return 0
  while IFS= read -r candidate; do
    [ -z "$candidate" ] || casks+=("$candidate")
  done < <(awk '/^[[:space:]]*cask "/ { line=$0; sub(/^[[:space:]]*cask "/,"",line); sub(/".*/,"",line); print line }' "$manifest")
  [ "${#casks[@]}" -gt 0 ] || return 0
  trap 'rm -f "$metadata" "$filtered" "$candidate_rows"' EXIT
  metadata="$(mktemp)" || return 1
  if ! HOMEBREW_NO_AUTO_UPDATE=1 brew info --json=v2 --cask "${casks[@]}" > "$metadata" 2>/dev/null \
      || ! jq -e '.casks | type == "array"' "$metadata" >/dev/null 2>&1; then
    echo "⚠ Cask metadata unavailable; running the bundle unchanged"
    return 0
  fi
  candidate_rows="$(mktemp)" || return 1
  if ! jq -r '
    .casks[] | select((.installed // "") == "") | .token as $token |
    .artifacts[]? | select(.app? != null) |
    select(.target != null) | .target as $app |
    select($app | startswith("/")) | [$token, $app] | @tsv' "$metadata" > "$candidate_rows" 2>/dev/null; then
    echo "⚠ Cask metadata could not be read; running the bundle unchanged"
    return 0
  fi
  current_uid="$(id -u)" || return 1
  while IFS=$'\t' read -r token app; do
    [ -n "$token" ] && [ -n "$app" ] || continue
    case " ${casks[*]} " in *" $token "*) ;; *) continue ;; esac
    case " $seen " in *" $token "*) continue ;; esac
    [ -d "$app" ] || continue
    owner="$(stat -f %u "$app" 2>/dev/null || stat -c %u "$app" 2>/dev/null)" || continue
    [[ "$owner" =~ ^[0-9]+$ ]] || continue
    [ "$owner" != "$current_uid" ] || continue
    filtered="$(mktemp)" || return 1
    awk -v entry="cask \"$token\"" '{ line=$0; sub(/^[[:space:]]*/,"",line); if (index(line,entry) != 1) print }' "$manifest" > "$filtered" || return 1
    mv "$filtered" "$manifest" || return 1
    printf '%s\n' "$token" >> "$deferred" || return 1
    seen="$seen $token"
    echo "⚠ Deferred $token: its existing app belongs to another account. Run brew install --cask $token in a terminal, or add it to brew_skip if Homebrew should not manage it."
  done < "$candidate_rows"
)
