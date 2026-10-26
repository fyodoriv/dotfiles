#!/usr/bin/env bats
# Tests for lib/login-apps.sh: the login_apps setting (issue #336).

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  # shellcheck source=../lib/login-apps.sh
  source "$REPO_ROOT/lib/login-apps.sh"
  unset DOTFILES_LOGIN_APPS
  YQ="$(command -v yq || true)"
  # No chezmoi on PATH: the table default applies.
  export PATH="/usr/bin:/bin"
}

@test "default list keeps Ghostty as the only login app" {
  run dotfiles_login_apps_list
  [ "$status" -eq 0 ]
  [ "$output" = "Ghostty" ]
  run dotfiles_login_apps_plan "Ghostty"
  [ "$output" = "$(printf 'add\tGhostty\t/Applications/Ghostty.app')" ]
}

@test "env list adds another app without editing core" {
  DOTFILES_LOGIN_APPS="Ghostty,Claude" run dotfiles_login_apps_list
  [ "$output" = "$(printf 'Ghostty\nClaude')" ]
  run dotfiles_login_apps_plan "$output"
  [ "${lines[1]}" = "$(printf 'add\tClaude\t/Applications/Claude.app')" ]
}

@test "a leading - removes an app from login items" {
  run dotfiles_login_apps_plan "$(printf -- '-Ghostty\nClaude')"
  [ "${lines[0]}" = "$(printf 'remove\tGhostty')" ]
  [ "${lines[1]}" = "$(printf 'add\tClaude\t/Applications/Claude.app')" ]
}

@test "set but empty env means no login apps" {
  DOTFILES_LOGIN_APPS="" run dotfiles_login_apps_list
  [ -z "$output" ]
}

@test "macos-apps.sh reads the list from lib/login-apps.sh, not a hard-coded array" {
  grep -q 'lib/login-apps.sh' "$REPO_ROOT/macos-apps.sh"
  run grep -q '"Ghostty:/Applications/Ghostty.app"' "$REPO_ROOT/macos-apps.sh"
  [ "$status" -ne 0 ]
}

@test "settings table has login_apps with the Ghostty default" {
  [ -n "$YQ" ] || skip "yq not installed"
  run "$YQ" -r '.settings.login_apps.default' "$REPO_ROOT/config/settings.yaml"
  [ "$output" = "Ghostty" ]
}

@test "unsafe names from the env are dropped" {
  DOTFILES_LOGIN_APPS='Claude,Bad"Name,a/b' run dotfiles_login_apps_list
  [ "$output" = "Claude" ]
}

@test "dotfiles config set accepts a removal entry" {
  [ -n "$YQ" ] || skip "yq not installed"
  export PATH="$(dirname "$YQ"):/usr/bin:/bin"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/cfg"
  mkdir -p "$XDG_CONFIG_HOME/chezmoi"
  printf 'data: {}\n' > "$XDG_CONFIG_HOME/chezmoi/chezmoi.yaml"
  run bash "$REPO_ROOT/bin/dotfiles-config" set login_apps -Ghostty,Claude
  [ "$status" -eq 0 ]
  run "$YQ" -r '.data.login_apps | join(",")' "$XDG_CONFIG_HOME/chezmoi/chezmoi.yaml"
  [ "$output" = "-Ghostty,Claude" ]
}
