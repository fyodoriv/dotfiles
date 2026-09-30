#!/usr/bin/env bats
# Guards that keep $HOME pointed at chezmoi's source checkout (the applied
# checkout), not at a development checkout of this repo.

GUARD="$BATS_TEST_DIRNAME/../.chezmoiscripts/run_before_00-refuse-foreign-source.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  mkdir -p "$TEST_DIR/applied" "$TEST_DIR/dev" "$TEST_DIR/fakebin"
  CONFIG="$TEST_DIR/chezmoi.yaml"
  printf 'sourceDir: "%s"\n' "$TEST_DIR/applied" > "$CONFIG"
}

teardown() {
  rm -rf "$TEST_DIR"
}

run_guard() {
  CHEZMOI_CONFIG_FILE="$CONFIG" CHEZMOI_SOURCE_DIR="$1" run bash "$GUARD"
}

@test "source guard allows an apply from the configured source" {
  run_guard "$TEST_DIR/applied"
  [ "$status" -eq 0 ]
}

@test "source guard allows the configured source reached through a symlink" {
  ln -s "$TEST_DIR/applied" "$TEST_DIR/applied-link"
  run_guard "$TEST_DIR/applied-link"
  [ "$status" -eq 0 ]
}

@test "source guard refuses an apply from another checkout" {
  run_guard "$TEST_DIR/dev"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to apply from $TEST_DIR/dev"* ]]
  [[ "$output" == *"configured source is $TEST_DIR/applied"* ]]
}

@test "source guard allows a deliberate switch" {
  DOTFILES_ALLOW_SOURCE_SWITCH=1 run_guard "$TEST_DIR/dev"
  [ "$status" -eq 0 ]
}

@test "source guard allows a first apply before chezmoi has a config" {
  rm -f "$CONFIG"
  run_guard "$TEST_DIR/dev"
  [ "$status" -eq 0 ]
}

@test "real chezmoi stops a foreign-source apply before changing files" {
  command -v chezmoi >/dev/null || skip "chezmoi not installed"
  local home="$TEST_DIR/home"
  mkdir -p "$home" "$TEST_DIR/dev/.chezmoiscripts"
  cp "$GUARD" "$TEST_DIR/dev/.chezmoiscripts/"
  echo "from dev" > "$TEST_DIR/dev/dot_marker"
  run env -u DOTFILES_ALLOW_SOURCE_SWITCH chezmoi apply --no-tty \
    --config "$CONFIG" --destination "$home" --source "$TEST_DIR/dev" \
    --persistent-state "$TEST_DIR/state.boltdb"
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to apply from"* ]]
  [ ! -e "$home/.marker" ]
}

@test "dotfiles_link_root prefers chezmoi's source over the running checkout" {
  cat > "$TEST_DIR/fakebin/chezmoi" <<FAKE
#!/bin/bash
[ "\$1" = "source-path" ] && printf '%s\n' "$TEST_DIR/applied"
FAKE
  chmod +x "$TEST_DIR/fakebin/chezmoi"
  source "$BATS_TEST_DIRNAME/../lib/dotfiles-source-dir.sh"
  PATH="$TEST_DIR/fakebin:$PATH" run dotfiles_link_root "$TEST_DIR/dev"
  [ "$status" -eq 0 ]
  [ "$output" = "$(cd "$TEST_DIR/applied" && pwd -P)" ]
}

@test "dotfiles_link_root falls back to the running checkout without a chezmoi source" {
  cat > "$TEST_DIR/fakebin/chezmoi" <<FAKE
#!/bin/bash
[ "\$1" = "source-path" ] && printf '%s\n' "$TEST_DIR/missing"
FAKE
  chmod +x "$TEST_DIR/fakebin/chezmoi"
  source "$BATS_TEST_DIRNAME/../lib/dotfiles-source-dir.sh"
  PATH="$TEST_DIR/fakebin:$PATH" run dotfiles_link_root "$TEST_DIR/dev"
  [ "$output" = "$TEST_DIR/dev" ]
}

@test "dotfiles_is_applied_checkout permits only chezmoi's configured source" {
  cat > "$TEST_DIR/fakebin/chezmoi" <<FAKE
#!/bin/bash
[ "\$1" = "source-path" ] && printf '%s\n' "$TEST_DIR/applied"
FAKE
  chmod +x "$TEST_DIR/fakebin/chezmoi"
  source "$BATS_TEST_DIRNAME/../lib/dotfiles-source-dir.sh"
  PATH="$TEST_DIR/fakebin:$PATH" run dotfiles_is_applied_checkout "$TEST_DIR/applied"
  [ "$status" -eq 0 ]
  PATH="$TEST_DIR/fakebin:$PATH" run dotfiles_is_applied_checkout "$TEST_DIR/dev"
  [ "$status" -eq 1 ]
}

@test "dotfiles_link_target moves running-checkout targets to the link root" {
  source "$BATS_TEST_DIRNAME/../lib/dotfiles-source-dir.sh"
  run dotfiles_link_target "$TEST_DIR/dev" "$TEST_DIR/applied" "$TEST_DIR/dev/home/zshrc"
  [ "$output" = "$TEST_DIR/applied/home/zshrc" ]
  run dotfiles_link_target "$TEST_DIR/dev" "$TEST_DIR/applied" "/opt/homebrew/bin/gawk"
  [ "$output" = "/opt/homebrew/bin/gawk" ]
  run dotfiles_link_target "$TEST_DIR/dev" "$TEST_DIR/applied" "$TEST_DIR/dev-other/home/zshrc"
  [ "$output" = "$TEST_DIR/dev-other/home/zshrc" ]
}

@test "doctor symlink and hooksPath heals use the link root" {
  grep -q 'DOTFILES_LINK_DIR="$(dotfiles_link_root "$DOTFILES_DIR")"' \
    "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor"
  grep -q 'src="$(dotfiles_link_target "$DOTFILES_DIR"' \
    "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor"
  grep -q '${DOTFILES_LINK_DIR:-$DOTFILES_DIR}/git-hooks' \
    "$BATS_TEST_DIRNAME/../modules/git/doctor.sh"
}

@test "doctor --fix only permits the applied chezmoi source checkout" {
  grep -q 'dotfiles_is_applied_checkout "$DOTFILES_DIR"' \
    "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor"
  grep -q 'report-only outside the applied checkout' \
    "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor"
}

@test "doctor --fix from a development checkout reports without changing host state" {
  local home="$TEST_DIR/home"
  mkdir -p "$home/.ssh"
  chmod 755 "$home/.ssh"
  cat > "$TEST_DIR/fakebin/chezmoi" <<FAKE
#!/bin/bash
case "\${1:-}" in
  source-path) printf '%s\n' "$TEST_DIR/applied" ;;
  execute-template) printf 'false\n' ;;
esac
FAKE
  chmod +x "$TEST_DIR/fakebin/chezmoi"

  run env HOME="$home" PATH="$TEST_DIR/fakebin:$PATH" DOTFILES_DOCTOR_NOTIFY=0 \
    "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" --fix --module security --quiet
  [ "$status" -ne 0 ]
  [ "$(stat -f '%Lp' "$home/.ssh")" = "755" ]
  [[ "$output" == *"report-only outside the applied checkout"* ]]
}

load_chezmoi_module() {
  STATUS_OUT="$TEST_DIR/status.txt"
  : > "$STATUS_OUT"
  cat > "$TEST_DIR/fakebin/chezmoi" <<FAKE
#!/bin/bash
case "\$*" in
  "status --include=symlinks --path-style=absolute") cat "$STATUS_OUT" ;;
  *) exit 0 ;;
esac
FAKE
  chmod +x "$TEST_DIR/fakebin/chezmoi"
  export PATH="$TEST_DIR/fakebin:$PATH"
  check() { :; }
  check_advisory() { :; }
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
  source "$BATS_TEST_DIRNAME/../modules/chezmoi/doctor.sh"
}

@test "doctor symlink drift check passes when managed symlinks match" {
  load_chezmoi_module
  run _chezmoi_drifted_managed_symlinks
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "doctor symlink drift check lists symlinks repointed at another checkout" {
  load_chezmoi_module
  printf ' M %s\n' "$HOME/.zshrc" "$HOME/.zshenv" > "$STATUS_OUT"
  run _chezmoi_drifted_managed_symlinks
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "$HOME/.zshrc" ]
  [ "${lines[1]}" = "$HOME/.zshenv" ]
}

@test "ship-it block fast-forwards the applied checkout and applies from it" {
  local ref="$BATS_TEST_DIRNAME/../docs/ship-it-reference.md"
  grep -q 'DOTFILES_APPLIED="$(chezmoi source-path)"' "$ref"
  grep -q '"$DOTFILES_APPLIED/bin/dotfiles-sync"' "$ref"
  grep -q '"$DOTFILES_APPLIED/bin/dotfiles" apply' "$ref"
  ! grep -qE '^cd ~ && dotfiles apply' "$ref"
}
