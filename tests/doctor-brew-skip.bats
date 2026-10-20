#!/usr/bin/env bats
# #236: a tool.<name> doctor check is skipped when <name> is in brew_skip
# (chezmoi data, or the brew.skip core option). DOTFILES_BREW_SKIP overrides
# both, like the other DOTFILES_* doctor seams.

REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  TEST_DIR="$(mktemp -d)"
  mkdir -p "$TEST_DIR/extra/brewskipmod"
  cat > "$TEST_DIR/extra/brewskipmod/doctor.sh" <<'DOCTOR'
check "tool.fakecask" "fakecask installed" "false" ""
check "brewskipmod.other" "other check" "false" ""
DOCTOR
  export DOTFILES_DOCTOR_FIXTURE_DIR="$TEST_DIR/extra"
}

teardown() { rm -rf "$TEST_DIR"; }

status_of() {
  printf '%s' "$output" | jq -r --arg id "$1" '.[] | select(.id == $id) | .status'
}

@test "brew-skip: tool.<name> is skipped when brew_skip lists the name" {
  export DOTFILES_BREW_SKIP="other fakecask"
  run "$REPO_ROOT/bin/dotfiles-doctor" --module brewskipmod --json
  [ "$(status_of tool.fakecask)" = skip ]
  [ "$(status_of brewskipmod.other)" = fail ]
}

@test "brew-skip: tool.<name> still runs when brew_skip does not list it" {
  export DOTFILES_BREW_SKIP="other"
  run "$REPO_ROOT/bin/dotfiles-doctor" --module brewskipmod --json
  [ "$(status_of tool.fakecask)" = fail ]
}
