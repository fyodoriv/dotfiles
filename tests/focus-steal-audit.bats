#!/usr/bin/env bats

setup() {
  TEST_DIR="$(mktemp -d)"
  export DOTFILES_DIR="$TEST_DIR/dotfiles"
  mkdir -p "$DOTFILES_DIR/bin" "$DOTFILES_DIR/lib" "$DOTFILES_DIR/launchagents"
  cp "$BATS_TEST_DIRNAME/../lib/focus-steal-audit.sh" "$DOTFILES_DIR/lib/"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "focus_steal_open_a_violations flags open -a without -g" {
  cat > "$DOTFILES_DIR/bin/bad-open" <<'SCRIPT'
#!/bin/bash
open -a Safari
SCRIPT
  chmod +x "$DOTFILES_DIR/bin/bad-open"
  # shellcheck source=../lib/focus-steal-audit.sh
  source "$DOTFILES_DIR/lib/focus-steal-audit.sh"
  run focus_steal_open_a_violations
  [ "$status" -eq 0 ]
  [[ "$output" == *bad-open* ]]
}

@test "focus_steal_open_a_violations ignores open -gj -a" {
  cat > "$DOTFILES_DIR/bin/good-open" <<'SCRIPT'
#!/bin/bash
open -gj -a Safari
SCRIPT
  chmod +x "$DOTFILES_DIR/bin/good-open"
  source "$DOTFILES_DIR/lib/focus-steal-audit.sh"
  run focus_steal_open_a_violations
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "focus_steal_activate_violations ignores chromework-install user link activate" {
  cat > "$DOTFILES_DIR/bin/chromework-install" <<'SCRIPT'
#!/bin/bash
cat <<'APPLESCRIPT'
tell application "Google Chrome" to activate
APPLESCRIPT
SCRIPT
  chmod +x "$DOTFILES_DIR/bin/chromework-install"
  source "$DOTFILES_DIR/lib/focus-steal-audit.sh"
  run focus_steal_activate_violations
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "focus_steal_activate_violations flags osascript activate" {
  cat > "$DOTFILES_DIR/bin/bad-activate" <<'SCRIPT'
#!/bin/bash
osascript -e 'tell application "Foo" to activate'
SCRIPT
  chmod +x "$DOTFILES_DIR/bin/bad-activate"
  source "$DOTFILES_DIR/lib/focus-steal-audit.sh"
  run focus_steal_activate_violations
  [ "$status" -eq 0 ]
  [[ "$output" == *bad-activate* ]]
}

@test "focus_steal_activate_violations ignores comment lines" {
  cat > "$DOTFILES_DIR/bin/commented" <<'SCRIPT'
#!/bin/bash
# tell application "Foo" to activate
echo "Restart Chrome to activate."
SCRIPT
  chmod +x "$DOTFILES_DIR/bin/commented"
  source "$DOTFILES_DIR/lib/focus-steal-audit.sh"
  run focus_steal_activate_violations
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
