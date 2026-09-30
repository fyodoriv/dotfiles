#!/usr/bin/env bats
# Integration tests for scaffolding subcommands:
#   dotfiles-new-module, dotfiles-brew-add, dotfiles-defaults-add, dotfiles-profile

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  mkdir -p "$TEST_HOME/.config/chezmoi"
  export HOME="$TEST_HOME"

  FAKE_DOTFILES="$TEST_DIR/dotfiles"
  mkdir -p "$FAKE_DOTFILES/bin" "$FAKE_DOTFILES/modules/macos"
  mkdir -p "$FAKE_DOTFILES/.chezmoiscripts"
  mkdir -p "$FAKE_DOTFILES/data"

  # Seed a minimal macos doctor.sh
  echo "#!/bin/bash" > "$FAKE_DOTFILES/modules/macos/doctor.sh"

  # Seed a minimal brew file with markers that brew-add looks for
  cat > "$FAKE_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl" <<'BREW'
#!/bin/bash
brew "existing-pkg"
# ── Core: Prompt
# ── Full: Terminal
{{ if eq .profile "full" }}
brew "full-only-pkg"
{{ end }}
BREW

  # Seed a minimal macos.sh
  echo "#!/bin/bash" > "$FAKE_DOTFILES/macos.sh"

  # Seed empty JSON data file for defaults-add
  echo "[]" > "$FAKE_DOTFILES/data/macos-defaults.json"

  # Copy subcommand scripts into the fake repo
  for cmd in dotfiles-new-module dotfiles-brew-add dotfiles-defaults-add dotfiles-profile; do
    cp "$BATS_TEST_DIRNAME/../bin/$cmd" "$FAKE_DOTFILES/bin/$cmd"
    chmod +x "$FAKE_DOTFILES/bin/$cmd"
  done
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── dotfiles-new-module ──────────────────────────────────────────

@test "new-module with no args exits 1 and shows usage" {
  run bash "$FAKE_DOTFILES/bin/dotfiles-new-module"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "new-module creates module directory, doctor.sh, and severity file" {
  run bash "$FAKE_DOTFILES/bin/dotfiles-new-module" testmod
  [ "$status" -eq 0 ]
  [ -d "$FAKE_DOTFILES/modules/testmod" ]
  [ -f "$FAKE_DOTFILES/modules/testmod/doctor.sh" ]
  [ -f "$FAKE_DOTFILES/modules/testmod/severity" ]
  [ "$(cat "$FAKE_DOTFILES/modules/testmod/severity")" = "cosmetic" ]
}

@test "new-module respects --severity flag" {
  run bash "$FAKE_DOTFILES/bin/dotfiles-new-module" secmod --severity critical
  [ "$status" -eq 0 ]
  [ "$(cat "$FAKE_DOTFILES/modules/secmod/severity")" = "critical" ]
}

@test "new-module fails if module already exists" {
  mkdir -p "$FAKE_DOTFILES/modules/dupmod"
  run bash "$FAKE_DOTFILES/bin/dotfiles-new-module" dupmod
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "new-module doctor.sh contains commented-out check examples" {
  run bash "$FAKE_DOTFILES/bin/dotfiles-new-module" exmod
  [ "$status" -eq 0 ]
  grep -q 'check ' "$FAKE_DOTFILES/modules/exmod/doctor.sh"
  grep -q 'check_symlink' "$FAKE_DOTFILES/modules/exmod/doctor.sh"
}

# ── dotfiles-brew-add ────────────────────────────────────────────

@test "brew-add with no args exits 1 and shows usage" {
  run bash "$FAKE_DOTFILES/bin/dotfiles-brew-add"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "brew-add appends formula to brew file" {
  run bash "$FAKE_DOTFILES/bin/dotfiles-brew-add" newpkg
  [ "$status" -eq 0 ]
  grep -q 'brew "newpkg"' "$FAKE_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
}

@test "brew-add --cask appends cask line" {
  run bash "$FAKE_DOTFILES/bin/dotfiles-brew-add" myapp --cask
  [ "$status" -eq 0 ]
  grep -q 'cask "myapp"' "$FAKE_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
}

@test "brew-add fails for duplicate package" {
  run bash "$FAKE_DOTFILES/bin/dotfiles-brew-add" existing-pkg
  [ "$status" -eq 1 ]
  [[ "$output" == *"already exists"* ]]
}

@test "brew-add fails when marker is missing from brew file" {
  echo "#!/bin/bash" > "$FAKE_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
  run bash "$FAKE_DOTFILES/bin/dotfiles-brew-add" newpkg
  [ "$status" -eq 1 ]
  [[ "$output" == *"marker"*"not found"* ]]
}

@test "brew-add --full-only adds to full section" {
  run bash "$FAKE_DOTFILES/bin/dotfiles-brew-add" fullpkg --full-only
  [ "$status" -eq 0 ]
  grep -q 'brew "fullpkg"' "$FAKE_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
  [[ "$output" == *"full-only section"* ]]
}

@test "brew-add --full-only fails when section is missing" {
  echo "#!/bin/bash" > "$FAKE_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
  run bash "$FAKE_DOTFILES/bin/dotfiles-brew-add" newpkg --full-only
  [ "$status" -eq 1 ]
  [[ "$output" == *"full-only section not found"* ]]
}

@test "brew-add --enterprise fails when section is missing" {
  echo "#!/bin/bash" > "$FAKE_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
  run bash "$FAKE_DOTFILES/bin/dotfiles-brew-add" newpkg --enterprise
  [ "$status" -eq 1 ]
  [[ "$output" == *"enterprise section not found"* ]]
}

# ── dotfiles-defaults-add ────────────────────────────────────────

@test "defaults-add with insufficient args exits 1 and shows usage" {
  run bash "$FAKE_DOTFILES/bin/dotfiles-defaults-add" com.apple.dock
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "defaults-add appends to JSON data file and module doctor.sh" {
  run bash "$FAKE_DOTFILES/bin/dotfiles-defaults-add" com.apple.dock autohide true bool
  [ "$status" -eq 0 ]
  jq -e '.[] | select(.domain == "com.apple.dock" and .key == "autohide")' "$FAKE_DOTFILES/data/macos-defaults.json"
  grep -q 'check_defaults' "$FAKE_DOTFILES/modules/macos/doctor.sh"
  grep -q 'autohide' "$FAKE_DOTFILES/modules/macos/doctor.sh"
}

@test "defaults-add respects --module flag" {
  mkdir -p "$FAKE_DOTFILES/modules/custom"
  echo "#!/bin/bash" > "$FAKE_DOTFILES/modules/custom/doctor.sh"
  run bash "$FAKE_DOTFILES/bin/dotfiles-defaults-add" com.example foo bar string --module custom
  [ "$status" -eq 0 ]
  grep -q 'check_defaults' "$FAKE_DOTFILES/modules/custom/doctor.sh"
}

# ── dotfiles-profile ─────────────────────────────────────────────

@test "profile with no args and no config shows not found message" {
  run bash "$FAKE_DOTFILES/bin/dotfiles-profile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No chezmoi config found"* ]]
}

@test "profile with invalid value exits 1" {
  run bash "$FAKE_DOTFILES/bin/dotfiles-profile" invalid
  [ "$status" -eq 1 ]
  [[ "$output" == *"must be 'core' or 'full'"* ]]
}

@test "profile shows current profile when config exists" {
  cat > "$TEST_HOME/.config/chezmoi/chezmoi.yaml" <<EOF
data:
  profile: full
EOF
  run bash "$FAKE_DOTFILES/bin/dotfiles-profile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"full"* ]]
}

# ── gitconfig sync check ─────────────────────────────────────────

@test "home/gitconfig and dot_gitconfig.tmpl stay in sync (except hooksPath)" {
  local real_dotfiles="$BATS_TEST_DIRNAME/.."
  # Strip the hooksPath line from both files and compare
  local home_content tmpl_content
  home_content=$(grep -v 'hooksPath' "$real_dotfiles/home/gitconfig")
  tmpl_content=$(grep -v 'hooksPath' "$real_dotfiles/dot_gitconfig.tmpl")
  [ "$home_content" = "$tmpl_content" ]
}
