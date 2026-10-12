#!/usr/bin/env bats
# A [user] section in the chezmoi-managed ~/.gitconfig is drift. chezmoi asks to
# overwrite it, and that prompt fails with "could not open a new TTY" when
# there is no terminal. Identity belongs in ~/.gitconfig.local.
# All emails below are placeholders. Every HOME is a tmpdir.

REPO="$BATS_TEST_DIRNAME/.."

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  unset BASH_ENV DOTFILES_REPOS_DIR DOTFILES_DIR DOTFILES_IS_AGENT \
    CHEZMOI_SOURCE_DIR CHEZMOI_WORKING_TREE
  export GIT_CONFIG_GLOBAL="$TEST_DIR/unused-global"
  export GIT_CONFIG_NOSYSTEM=1

  # Minimal chezmoi source: a static gitconfig plus the real migrate script.
  SRC="$TEST_DIR/src"
  mkdir -p "$SRC/.chezmoiscripts" "$SRC/lib" "$TEST_DIR/cfg"
  printf '[include]\n\tpath = ~/.gitconfig.local\n[pull]\n\trebase = true\n' > "$SRC/dot_gitconfig"
  cp "$REPO/lib/gitconfig-user-migrate.sh" "$SRC/lib/"
  cp "$REPO/.chezmoiscripts/run_before_10-gitconfig-user-migrate.sh" "$SRC/.chezmoiscripts/"
  printf 'sourceDir: %s\n' "$SRC" > "$TEST_DIR/cfg/chezmoi.yaml"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Headless apply: setsid drops the controlling terminal, as a LaunchAgent has.
headless_apply() {
  setsid_cmd=""
  command -v setsid >/dev/null 2>&1 && setsid_cmd="setsid"
  $setsid_cmd chezmoi apply --no-tty --config "$TEST_DIR/cfg/chezmoi.yaml" \
    --source "$SRC" --destination "$HOME" --persistent-state "$TEST_DIR/state.boltdb" \
    </dev/null 2>&1
}

@test "apply fails on untracked [user] email without migration (baseline)" {
  run headless_apply
  [ "$status" -eq 0 ]
  printf '[user]\n\temail = me@example.com\n' >> "$HOME/.gitconfig"
  rm "$SRC/.chezmoiscripts/run_before_10-gitconfig-user-migrate.sh"
  run headless_apply
  [ "$status" -ne 0 ]
}

@test "apply exits 0 and keeps the email in .gitconfig.local" {
  run headless_apply
  [ "$status" -eq 0 ]
  printf '[user]\n\tname = Test User\n\temail = me@example.com\n' >> "$HOME/.gitconfig"
  run headless_apply
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(git config -f "$HOME/.gitconfig.local" user.email)" = "me@example.com" ]
  [ "$(git config -f "$HOME/.gitconfig.local" user.name)" = "Test User" ]
  ! grep -q '^\[user\]' "$HOME/.gitconfig"
  # Effective identity through the include is unchanged.
  [ "$(git config --file "$HOME/.gitconfig" --includes user.email)" = "me@example.com" ]
}

@test "migration keeps existing local keys and backs up conflicting values" {
  run headless_apply
  [ "$status" -eq 0 ]
  printf '[user]\n\temail = old@example.com\n' >> "$HOME/.gitconfig"
  printf '[user]\n\temail = keep@example.com\n' > "$HOME/.gitconfig.local"
  run headless_apply
  [ "$status" -eq 0 ]
  [ "$(git config -f "$HOME/.gitconfig.local" user.email)" = "keep@example.com" ]
  grep -q 'old@example.com' "$HOME/.gitconfig.user-backup"
  [ "$(stat -f %Lp "$HOME/.gitconfig.user-backup" 2>/dev/null || stat -c %a "$HOME/.gitconfig.user-backup")" = "600" ]
}

@test "migration does not print the email" {
  run headless_apply
  printf '[user]\n\temail = secret-token@example.com\n' >> "$HOME/.gitconfig"
  run headless_apply
  [ "$status" -eq 0 ]
  [[ "$output" != *"secret-token"* ]]
}

@test "migration is a no-op when the managed file has no [user]" {
  source "$REPO/lib/gitconfig-user-migrate.sh"
  printf '[pull]\n\trebase = true\n' > "$HOME/.gitconfig"
  run gitconfig_user_migrate
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$HOME/.gitconfig.local" ]
}

# ── doctor ───────────────────────────────────────────────────────────

doctor_env() {
  DOTFILES_DIR="$REPO"
  OVERRIDES_FILE="$TEST_DIR/.overrides"; touch "$OVERRIDES_FILE"
  FIX_MODE="${1:-false}"; LIST_MODE=false
  pass_count=0; fail_count=0; fix_count=0; skip_count=0; fail_messages=()
  pass() { pass_count=$((pass_count + 1)); }
  fail() { fail_count=$((fail_count + 1)); fail_messages+=("$1"); }
  fixed() { fix_count=$((fix_count + 1)); }
  skipped() { skip_count=$((skip_count + 1)); }
  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }
  check() {
    local id="$1" desc="$2" t="$3" f="$4"
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if eval "$t" >/dev/null 2>&1; then pass "$desc"; return; fi
    if [ "$FIX_MODE" = true ] && [ -n "$f" ] && eval "$f" >/dev/null 2>&1; then fixed "$desc"; return; fi
    fail "$id"
  }
  check_managed() { :; }
  check_symlink() { :; }
  chezmoi() { return 1; }
}

@test "doctor: git.gitconfig_no_user fails when [user] drift is present" {
  doctor_env
  printf '[user]\n\temail = me@example.com\n' > "$HOME/.gitconfig"
  source "$REPO/modules/git/doctor.sh"
  [[ " ${fail_messages[*]} " == *" git.gitconfig_no_user "* ]]
}

@test "doctor: git.gitconfig_no_user passes on a clean managed file" {
  doctor_env
  printf '[pull]\n\trebase = true\n' > "$HOME/.gitconfig"
  source "$REPO/modules/git/doctor.sh"
  [[ " ${fail_messages[*]} " != *" git.gitconfig_no_user "* ]]
}

@test "doctor: --fix migrates the drift" {
  doctor_env true
  printf '[user]\n\temail = me@example.com\n' > "$HOME/.gitconfig"
  source "$REPO/modules/git/doctor.sh"
  [ "$(git config -f "$HOME/.gitconfig.local" user.email)" = "me@example.com" ]
  ! grep -q '^\[user\]' "$HOME/.gitconfig"
}
