#!/bin/bash
# Login items list for macos-apps.sh, from the login_apps setting
# (config/settings.yaml). Issue #336.
#
# Each entry is an app name in /Applications. A leading - removes that app
# from login items instead. Source order, first hit wins:
#   env:          DOTFILES_LOGIN_APPS (comma list; set but empty = none)
#   chezmoi data: login_apps (list)
#   default:      Ghostty

DOTFILES_LOGIN_APPS_DEFAULT="Ghostty"

# dotfiles_login_apps_list: print one entry per line, blanks dropped.
dotfiles_login_apps_list() {
  local list data
  if [ -n "${DOTFILES_LOGIN_APPS+x}" ]; then
    list="$DOTFILES_LOGIN_APPS"
  else
    list="$DOTFILES_LOGIN_APPS_DEFAULT"
    if command -v chezmoi >/dev/null 2>&1; then
      data="$(chezmoi execute-template '{{ $v := dig "login_apps" "__unset__" . }}{{ if kindIs "slice" $v }}{{ join "," $v }}{{ else }}{{ $v }}{{ end }}' 2>/dev/null || echo __unset__)"
      [ "$data" = "__unset__" ] || list="$data"
    fi
  fi
  # Keep only safe single-word names (same set `dotfiles config set` allows,
  # minus /), so no quote reaches the osascript strings in macos-apps.sh.
  printf '%s' "$list" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -E '^-?[A-Za-z0-9@._+]+$' || true
}

# dotfiles_login_apps_plan <entries>: turn entries (one per line) into
# tab-separated actions: "add<TAB>Name<TAB>/Applications/Name.app" or
# "remove<TAB>Name".
dotfiles_login_apps_plan() {
  local entry
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    case "$entry" in
      -*) printf 'remove\t%s\n' "${entry#-}" ;;
      *) printf 'add\t%s\t/Applications/%s.app\n' "$entry" "$entry" ;;
    esac
  done <<< "$1"
}
