#!/usr/bin/env bats
# Pins the contract that EXTRA_OVERLAY_ROOT=<path>/brewfile/Brewfile is
# merged into the brew-install lifecycle script. User story #10, sub-bullet
# (c) under "What dotfiles does with your overlay".
#
# The lifecycle script is a chezmoi template (`.tmpl`) so direct bash
# execution isn't possible. Tests assert on the rendered + executed
# resolution logic: extract the EXTRA_BREWFILE resolution block, render
# the chezmoi `{{ dig ... }}` placeholders to empty strings, then run.

load test_helper

BREW_TMPL="$BATS_TEST_DIRNAME/../.chezmoiscripts/run_onchange_brew.sh.tmpl"

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_OVERLAY="$TEST_DIR/dotfiles-acme"
  mkdir -p "$TEST_OVERLAY/brewfile"
  cat > "$TEST_OVERLAY/brewfile/Brewfile" <<'BREWEOF'
brew "acme-internal-cli"
cask "acme-tunnel-app"
BREWEOF

  # Render the EXTRA_BREWFILE resolution block from the chezmoi template:
  # strip `{{ dig "..." "..." . }}` placeholders to empty strings so the
  # block is runnable bash. The block is bounded by the comment header
  # "Optional overlay Brewfile" and the `if [ -n "$EXTRA_BREWFILE" ]` line.
  RESOLVE_SCRIPT="$TEST_DIR/resolve-brewfile.sh"
  cat > "$RESOLVE_SCRIPT" <<'WRAPEOF'
#!/usr/bin/env bash
WRAPEOF
  awk '
    /^# ── Optional overlay Brewfile/ { capture = 1 }
    capture && /^if \[ -n "\$EXTRA_BREWFILE" \]/ { capture = 0; print "echo \"EXTRA_BREWFILE=$EXTRA_BREWFILE\""; next }
    capture { print }
  ' "$BREW_TMPL" \
    | sed 's@{{ dig "[^"]*" "" \. }}@@g' \
    >> "$RESOLVE_SCRIPT"
  chmod +x "$RESOLVE_SCRIPT"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "EXTRA_OVERLAY_ROOT derives EXTRA_BREWFILE as <root>/brewfile/Brewfile" {
  EXTRA_OVERLAY_ROOT="$TEST_OVERLAY" run bash "$RESOLVE_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"EXTRA_BREWFILE=$TEST_OVERLAY/brewfile/Brewfile"* ]] || {
    echo "Expected EXTRA_BREWFILE to derive to $TEST_OVERLAY/brewfile/Brewfile; got: $output"
    return 1
  }
}

@test "EXTRA_OVERLAY_ROOT unset: EXTRA_BREWFILE stays empty" {
  unset EXTRA_OVERLAY_ROOT EXTRA_BREWFILE
  run bash "$RESOLVE_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"EXTRA_BREWFILE="* ]]
  [[ "$output" != *"EXTRA_BREWFILE=$TEST_OVERLAY"* ]]
}

@test "EXTRA_OVERLAY_ROOT with colon-separated paths: rejected" {
  EXTRA_OVERLAY_ROOT="$TEST_OVERLAY:$TEST_DIR/other" run bash "$RESOLVE_SCRIPT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"single path"* ]] || [[ "$output" == *"one overlay"* ]] || {
    echo "Expected error about single-path requirement; got: $output"
    return 1
  }
}

@test "EXTRA_BREWFILE backwards-compat: still wins when EXTRA_OVERLAY_ROOT also set" {
  EXTRA_BREWFILE="/explicit/path/Brewfile" EXTRA_OVERLAY_ROOT="$TEST_OVERLAY" run bash "$RESOLVE_SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"EXTRA_BREWFILE=/explicit/path/Brewfile"* ]] || {
    echo "Expected explicit EXTRA_BREWFILE to win over overlay-derived; got: $output"
    return 1
  }
}
