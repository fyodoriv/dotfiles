#!/usr/bin/env bats
# capslock_control: false keeps Caps Lock as Caps Lock: no LaunchAgent, no
# visual-script remap, and the live mapping is cleared on apply.

load test_helper

TMPL="$BATS_TEST_DIRNAME/../.chezmoiscripts/run_onchange_launchagents.sh.tmpl"

setup() {
  TEST_DIR="$(mktemp -d)"
  mkdir -p "$TEST_DIR/bin"
  export HIDUTIL_LOG="$TEST_DIR/hidutil.log"
  export HIDUTIL_MAPPING=""
  cat > "$TEST_DIR/bin/hidutil" <<'EOF'
#!/bin/bash
echo "$*" >> "$HIDUTIL_LOG"
[ "$2" = "--get" ] && printf '%s\n' "$HIDUTIL_MAPPING"
exit 0
EOF
  chmod +x "$TEST_DIR/bin/hidutil"
  PATH="$TEST_DIR/bin:$PATH"
  eval "$(sed -n '/^should_skip_agent() {/,/^}/p' "$TMPL")"
  eval "$(sed -n '/^capslock_clear_live_mapping() {/,/^}/p' "$TMPL")"
}

teardown() {
  rm -rf "$TEST_DIR"
}

CAPS_ONLY='(
    {
    HIDKeyboardModifierMappingDst = 30064771296;
    HIDKeyboardModifierMappingSrc = 30064771129;
}
)'

@test "capslock_control=false skips the capslock-control LaunchAgent" {
  CAPSLOCK_CONTROL=false
  should_skip_agent capslock-control
}

@test "capslock_control=true or unset keeps the capslock-control LaunchAgent" {
  CAPSLOCK_CONTROL=true
  ! should_skip_agent capslock-control
  unset CAPSLOCK_CONTROL
  ! should_skip_agent capslock-control
}

@test "capslock_control=false clears a live Caps Lock → Control mapping" {
  CAPSLOCK_CONTROL=false HIDUTIL_MAPPING="$CAPS_ONLY"
  run capslock_clear_live_mapping
  [ "$status" -eq 0 ]
  grep -q 'UserKeyMapping":\[\]' "$HIDUTIL_LOG"
}

# Real `hidutil property --get` output: one row per HID service, so a single
# Caps Lock → Control remap shows up many times.
CAPS_MULTI='RegistryID  Key                   Value
1000009cc   UserKeyMapping   (
        {
        HIDKeyboardModifierMappingDst = 30064771296;
        HIDKeyboardModifierMappingSrc = 30064771129;
    }
)
1000008b2   UserKeyMapping   (null)
100000a5c   UserKeyMapping   (
        {
        HIDKeyboardModifierMappingDst = 30064771296;
        HIDKeyboardModifierMappingSrc = 30064771129;
    }
)'

@test "capslock_control=false clears the remap when hidutil lists it once per device" {
  CAPSLOCK_CONTROL=false HIDUTIL_MAPPING="$CAPS_MULTI"
  run capslock_clear_live_mapping
  [ "$status" -eq 0 ]
  grep -q 'UserKeyMapping":\[\]' "$HIDUTIL_LOG"
}

@test "capslock_control=false leaves other remaps alone and warns" {
  CAPSLOCK_CONTROL=false
  HIDUTIL_MAPPING='({HIDKeyboardModifierMappingDst=30064771296;HIDKeyboardModifierMappingSrc=30064771129;},{HIDKeyboardModifierMappingDst=30064771113;HIDKeyboardModifierMappingSrc=30064771300;})'
  run capslock_clear_live_mapping
  [[ "$output" == *"other key remaps are active"* ]]
  ! grep -q -- '--set' "$HIDUTIL_LOG"
}

@test "capslock_control=true never touches the live mapping" {
  CAPSLOCK_CONTROL=true HIDUTIL_MAPPING="$CAPS_ONLY"
  run capslock_clear_live_mapping
  [ ! -s "$HIDUTIL_LOG" ]
}

@test "macos-visual.sh remaps Caps Lock only when capslock_control is not false" {
  run grep -B2 'HIDKeyboardModifierMappingSrc' "$BATS_TEST_DIRNAME/../macos-visual.sh"
  [[ "$output" == *'DOTFILES_CAPSLOCK_CONTROL:-true}" != "false"'* ]]
  grep -q 'DOTFILES_CAPSLOCK_CONTROL="{{ dig "capslock_control" (dig "owner_machine" false .) . }}"' \
    "$BATS_TEST_DIRNAME/../.chezmoiscripts/run_onchange_macos.sh.tmpl"
}

@test "chezmoi config keeps capslock_control across chezmoi init" {
  grep -q 'hasKey . "capslock_control"' "$BATS_TEST_DIRNAME/../.chezmoi.yaml.tmpl"
  grep -q '^  capslock_control: {{ \$capslockControl }}' "$BATS_TEST_DIRNAME/../.chezmoi.yaml.tmpl"
}

@test "capslock_control defaults to owner_machine, so a new user keeps Caps Lock" {
  grep -q '\$capslockControl := \$ownerMachine' "$BATS_TEST_DIRNAME/../.chezmoi.yaml.tmpl"
  grep -q 'CAPSLOCK_CONTROL="{{ dig "capslock_control" (dig "owner_machine" false .) . }}"' "$TMPL"
}

@test "a failing hidutil --get cannot abort the set -euo pipefail apply script" {
  cat > "$TEST_DIR/bin/hidutil" <<'STUB'
#!/bin/bash
echo "$*" >> "$HIDUTIL_LOG"
exit 1
STUB
  chmod +x "$TEST_DIR/bin/hidutil"
  run bash -c "set -euo pipefail; $(declare -f capslock_clear_live_mapping); CAPSLOCK_CONTROL=false; capslock_clear_live_mapping; echo reached-end"
  [ "$status" -eq 0 ]
  [[ "$output" == *reached-end* ]]
}

# `dotfiles apply` runs `chezmoi init`, which re-renders chezmoi.yaml from
# .chezmoi.yaml.tmpl. Render it for real: the owner keeps the remap, a new
# user does not, and an explicit choice survives a second init.
_render_config() {
  HOME="$TEST_DIR" chezmoi execute-template --init --source "$BATS_TEST_DIRNAME/.." \
    --override-data "$1" < "$BATS_TEST_DIRNAME/../.chezmoi.yaml.tmpl"
}

_render_launchagents() {
  HOME="$TEST_DIR" chezmoi execute-template --source "$BATS_TEST_DIRNAME/.." \
    --override-data "$1" < "$TMPL" | grep '^CAPSLOCK_CONTROL='
}

@test "owner Mac (owner_machine true, no capslock_control key) keeps the remap after init" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  run _render_config '{"owner_machine":true,"profile":"full"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\n  capslock_control: true'* ]]
  run _render_launchagents '{"owner_machine":true,"profile":"full"}'
  [ "$output" = 'CAPSLOCK_CONTROL="true"' ]
}

@test "new user (owner_machine false) gets the remap off after init" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  run _render_config '{"owner_machine":false,"profile":"core"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\n  capslock_control: false'* ]]
  run _render_launchagents '{"owner_machine":false,"profile":"core"}'
  [ "$output" = 'CAPSLOCK_CONTROL="false"' ]
}

@test "an explicit capslock_control choice survives re-init on both kinds of Mac" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  run _render_config '{"owner_machine":true,"capslock_control":false}'
  [[ "$output" == *$'\n  capslock_control: false'* ]]
  run _render_config '{"owner_machine":false,"capslock_control":true}'
  [[ "$output" == *$'\n  capslock_control: true'* ]]
}
