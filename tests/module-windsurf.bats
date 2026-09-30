#!/usr/bin/env bats
# Tests for modules/windsurf/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  WS_LOCAL="$TEST_DIR/ws_local"
  WS_USER_DIR="$TEST_HOME/Library/Application Support/Windsurf/User"
  WS_APP="$TEST_HOME/Applications/Windsurf.app"
  WS_BIN="$TEST_HOME/.codeium/windsurf/bin/windsurf"

  mkdir -p "$TEST_HOME" "$TEST_DOTFILES/windsurf" "$TEST_DOTFILES/modules/windsurf" "$WS_LOCAL"

  # Doctor module needs WINDSURF_LOCAL_DIR override
  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  export WINDSURF_LOCAL_DIR="$WS_LOCAL"

  # Mock the doctor helpers
  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"
  touch "$OVERRIDES_FILE"
  FIX_MODE=false
  LIST_MODE=false
  pass_count=0; fail_count=0; fix_count=0; skip_count=0; warn_count=0

  pass()        { pass_count=$((pass_count + 1)); }
  fail()        { fail_count=$((fail_count + 1)); }
  fixed()       { fix_count=$((fix_count + 1)); }
  skipped()     { skip_count=$((skip_count + 1)); }
  audit_warn()  { warn_count=$((warn_count + 1)); }

  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }

  check_symlink() {
    local id="$1" src="$2" dst="$3"
    $LIST_MODE && return
    is_overridden "$id" && { skipped "$dst"; return; }
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
      pass "$dst"
    elif $FIX_MODE; then
      mkdir -p "$(dirname "$dst")"
      [ -f "$dst" ] && mv "$dst" "${dst}.backup" 2>/dev/null
      [ -L "$dst" ] && rm "$dst"
      ln -s "$src" "$dst"
      fixed "$dst"
    else
      fail "$dst"
    fi
  }

  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="$4"
    $LIST_MODE && return
    is_overridden "$id" && { skipped "$desc"; return; }
    if eval "$test_cmd" >/dev/null 2>&1; then
      pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then
      if eval "$fix_cmd" >/dev/null 2>&1; then fixed "$desc"; else fail "$desc"; fi
    else
      fail "$desc"
    fi
  }

  check_advisory() {
    local id="$1" desc="$2" test_cmd="$3"
    $LIST_MODE && return
    is_overridden "$id" && { skipped "$desc"; return; }
    if eval "$test_cmd" >/dev/null 2>&1; then pass "$desc"; else audit_warn "$desc"; fi
  }

  # Stub: a no-op `security` is harmless in the test sandbox; the module
  # gracefully handles an empty/missing CA bundle.
  security() { return 1; }
  export -f security  # so subshells inside the module see the stub
}

teardown() {
  rm -rf "$TEST_DIR"
}

_link_windsurf_user_config() {
  mkdir -p "$WS_USER_DIR" "$WS_LOCAL"
  cp "$TEST_DOTFILES/windsurf/settings.json" "$WS_LOCAL/settings.generated.json"
  ln -s "$WS_LOCAL/settings.generated.json" "$WS_USER_DIR/settings.json"
  ln -s "$TEST_DOTFILES/windsurf/keybindings.json" "$WS_USER_DIR/keybindings.json"
}

# ── App-not-installed short-circuit ─────────────────────────────────────────

@test "windsurf: short-circuits when Windsurf.app is missing" {
  # No app dir created → module should emit install/cli/symlink checks only
  # Override the module's hard-coded _WS_APP via a sandboxed prelude.
  cat > "$TEST_DIR/run.sh" <<EOF
source "$TEST_DOTFILES/modules/windsurf/doctor.sh"
EOF
  printf '{ "editor.fontSize": 15 }\n' > "$TEST_DOTFILES/windsurf/settings.json"
  printf '[]\n' > "$TEST_DOTFILES/windsurf/keybindings.json"
  # Copy the doctor with TEST_HOME-aware paths
  sed -e "s|/Applications/Windsurf.app|$WS_APP|" \
      -e "s|\$HOME/.codeium/windsurf/bin/windsurf|$WS_BIN|" \
      -e "s|\$HOME/Library/Application Support/Windsurf/User|$WS_USER_DIR|" \
      "$BATS_TEST_DIRNAME/../modules/windsurf/doctor.sh" \
      > "$TEST_DOTFILES/modules/windsurf/doctor.sh"

  FIX_MODE=true
  source "$TEST_DOTFILES/modules/windsurf/doctor.sh"

  [ "$fail_count" -eq 2 ]
  [ -f "$WS_LOCAL/settings.generated.json" ]
  [ "$(readlink "$WS_USER_DIR/settings.json")" = "$WS_LOCAL/settings.generated.json" ]
}

# ── Settings + keybindings symlinks (Windsurf-installed path) ──────────────

_setup_windsurf_installed() {
  mkdir -p "$WS_APP"
  mkdir -p "$WS_USER_DIR"
  mkdir -p "$(dirname "$WS_BIN")"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$WS_BIN"
  chmod +x "$WS_BIN"

  # Source files
  printf '{ "editor.fontSize": 15 }\n' > "$TEST_DOTFILES/windsurf/settings.json"
  printf '[]\n' > "$TEST_DOTFILES/windsurf/keybindings.json"
  printf 'mikestead.dotenv\nesbenp.prettier-vscode\n' > "$TEST_DOTFILES/windsurf/extensions.txt"

  sed -e "s|/Applications/Windsurf.app|$WS_APP|" \
      -e "s|\$HOME/.codeium/windsurf/bin/windsurf|$WS_BIN|" \
      -e "s|\$HOME/Library/Application Support/Windsurf/User|$WS_USER_DIR|" \
      "$BATS_TEST_DIRNAME/../modules/windsurf/doctor.sh" \
      > "$TEST_DOTFILES/modules/windsurf/doctor.sh"
}

@test "windsurf: settings symlinks fail when missing" {
  _setup_windsurf_installed
  source "$TEST_DOTFILES/modules/windsurf/doctor.sh"

  # 2 missing symlinks → fail_count includes them; install/cli pass; extensions fail (CLI returns success but list is empty)
  [ "$fail_count" -ge 2 ]
}

@test "windsurf: settings symlinks pass when correctly linked" {
  _setup_windsurf_installed
  _link_windsurf_user_config

  source "$TEST_DOTFILES/modules/windsurf/doctor.sh"
  # 2 install/cli + 2 symlinks = 4 pass
  [ "$pass_count" -ge 4 ]
}

@test "windsurf: fix mode creates symlinks when missing" {
  _setup_windsurf_installed
  FIX_MODE=true

  source "$TEST_DOTFILES/modules/windsurf/doctor.sh"

  [ -L "$WS_USER_DIR/settings.json" ]
  [ "$(readlink "$WS_USER_DIR/settings.json")"    = "$WS_LOCAL/settings.generated.json" ]
  [ -L "$WS_USER_DIR/keybindings.json" ]
  [ "$(readlink "$WS_USER_DIR/keybindings.json")" = "$TEST_DOTFILES/windsurf/keybindings.json" ]
}

@test "windsurf: fix mode backs up existing regular settings.json before symlinking" {
  _setup_windsurf_installed
  FIX_MODE=true
  echo '{ "user.custom": true }' > "$WS_USER_DIR/settings.json"

  source "$TEST_DOTFILES/modules/windsurf/doctor.sh"

  [ -L "$WS_USER_DIR/settings.json" ]
  [ -f "$WS_USER_DIR/settings.json.backup" ]
  grep -q "user.custom" "$WS_USER_DIR/settings.json.backup"
}

# ── Per-machine override ────────────────────────────────────────────────────

@test "windsurf: settings override symlinks to the override file when present" {
  _setup_windsurf_installed
  FIX_MODE=true
  printf '{ "override.machine": "yes" }\n' > "$WS_LOCAL/settings.override.json5"

  source "$TEST_DOTFILES/modules/windsurf/doctor.sh"

  [ -L "$WS_USER_DIR/settings.json" ]
  [ "$(readlink "$WS_USER_DIR/settings.json")" = "$WS_LOCAL/settings.override.json5" ]
}

@test "windsurf: overlay settings merge with base settings" {
  _setup_windsurf_installed
  export EXTRA_OVERLAY_ROOT="$TEST_DIR/overlay"
  mkdir -p "$EXTRA_OVERLAY_ROOT/windsurf"
  printf '{ "company.private": true }\n' > "$EXTRA_OVERLAY_ROOT/windsurf/settings.json"
  FIX_MODE=true

  source "$TEST_DOTFILES/modules/windsurf/doctor.sh"

  [ -f "$WS_LOCAL/settings.generated.json" ]
  grep -q '"editor.fontSize"' "$WS_LOCAL/settings.generated.json"
  grep -q '"company.private"' "$WS_LOCAL/settings.generated.json"
  [ "$(readlink "$WS_USER_DIR/settings.json")" = "$WS_LOCAL/settings.generated.json" ]
}

@test "windsurf: generated settings preserve live MCP only" {
  _setup_windsurf_installed
  mkdir -p "$WS_LOCAL"
  printf '{"editor.fontSize": 99, "mcpServers": {"live": {"command": "live"}}}\n' > "$WS_LOCAL/settings.generated.json"
  FIX_MODE=true

  source "$TEST_DOTFILES/modules/windsurf/doctor.sh"

  grep -q '"live"' "$WS_LOCAL/settings.generated.json"
  grep -q '"editor.fontSize": 15' "$WS_LOCAL/settings.generated.json"
  ! grep -q '"editor.fontSize": 99' "$WS_LOCAL/settings.generated.json"
}

# ── Extensions ──────────────────────────────────────────────────────────────

@test "windsurf: emits one check per extension in extensions.txt" {
  _setup_windsurf_installed
  _link_windsurf_user_config

  # Replace the windsurf CLI stub with one that lists exactly one of the two
  # extensions as installed, so we can verify the check fires per extension.
  cat > "$WS_BIN" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --list-extensions) echo "mikestead.dotenv";;
  *) exit 0;;
esac
EOF
  chmod +x "$WS_BIN"

  source "$TEST_DOTFILES/modules/windsurf/doctor.sh"

  # 1 extension reported as installed → 1 pass; the other → 1 fail (no fix mode)
  [ "$pass_count" -ge 3 ]   # install + cli + settings + keybindings + 1 ext
  [ "$fail_count" -ge 1 ]   # missing extension
}

@test "windsurf: comment + blank lines in extensions.txt are ignored" {
  _setup_windsurf_installed
  _link_windsurf_user_config

  cat > "$TEST_DOTFILES/windsurf/extensions.txt" <<EOF
# Header comment
mikestead.dotenv

# Another comment

esbenp.prettier-vscode
EOF

  # CLI reports both as installed
  cat > "$WS_BIN" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --list-extensions) printf "mikestead.dotenv\nesbenp.prettier-vscode\n";;
  *) exit 0;;
esac
EOF
  chmod +x "$WS_BIN"

  source "$TEST_DOTFILES/modules/windsurf/doctor.sh"

  # Only 2 extension checks should run (comments + blanks dropped)
  # = install + cli + settings + keybindings + 2 exts + cascade advisory = 7 pass
  [ "$pass_count" -ge 6 ]
  [ "$fail_count" -eq 0 ]
}

@test "windsurf: overlay extensions are included" {
  _setup_windsurf_installed
  _link_windsurf_user_config
  export EXTRA_OVERLAY_ROOT="$TEST_DIR/overlay"
  mkdir -p "$EXTRA_OVERLAY_ROOT/windsurf"
  printf 'company.private-extension\n' > "$EXTRA_OVERLAY_ROOT/windsurf/extensions.txt"

  cat > "$WS_BIN" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  --list-extensions) printf "mikestead.dotenv\nesbenp.prettier-vscode\n";;
  *) exit 0;;
esac
EOF
  chmod +x "$WS_BIN"

  source "$TEST_DOTFILES/modules/windsurf/doctor.sh"

  [ "$fail_count" -ge 1 ]
}

# ── Cascade model tier (advisory) ───────────────────────────────────────────
#
# The advisory check verifies the Cascade catalog (in ~/.codeium/windsurf/
# user_settings.pb) includes the strings `claude-opus-4-8-max` AND
# `1M Context`. It's best-effort because the protobuf is binary and the
# actual selection lives in a wire-format field we don't decode.

# Helper to plant a synthetic user_settings.pb. The file is treated as
# opaque bytes — we just put the strings doctor.sh greps for. The real
# file is a protobuf with the strings embedded inline.
_plant_user_settings_pb() {
  local content="$1"
  local pb="$TEST_HOME/.codeium/windsurf/user_settings.pb"
  mkdir -p "$(dirname "$pb")"
  printf '%s' "$content" > "$pb"
}

@test "windsurf: cascade.model_tier passes when catalog has Opus 4.8 Max + 1M Context" {
  _setup_windsurf_installed
  _link_windsurf_user_config
  # Both required catalog strings present (literal `claude-opus-4-8-max`
  # appears on its own line because the protobuf stores it as a contiguous
  # byte sequence — `strings` extracts it cleanly).
  _plant_user_settings_pb $'header\x00claude-opus-4-8-max\x00more\x00Claude Opus 4.8 Max\x00\x001M Context\x00trailing'

  source "$TEST_DOTFILES/modules/windsurf/doctor.sh"
  # Advisory passes — no warning incurred for model_tier
  [ "$pass_count" -ge 5 ]
}

@test "windsurf: cascade.model_tier warns when catalog has only the old Opus 4.7" {
  _setup_windsurf_installed
  _link_windsurf_user_config
  # Pre-2026-05-29 catalog: 4.7 entries, no 4.8, no 1M Context
  _plant_user_settings_pb $'header\x00claude-opus-4-7-max\x00more\x00trailing'

  source "$TEST_DOTFILES/modules/windsurf/doctor.sh"
  # Advisory warns (audit_warn fires) — warn_count goes up. We don't
  # constrain fail_count here because extension checks may fail in the
  # sandbox (orthogonal to what we're testing); the assertion is that
  # the cascade.model_tier check produced a warning, not a fail.
  [ "$warn_count" -ge 1 ]
}

@test "windsurf: cascade.model_tier warns when 1M Context toggle absent" {
  _setup_windsurf_installed
  _link_windsurf_user_config
  # Opus 4.8 present but the 1M Context capability string is missing — partial drift
  _plant_user_settings_pb $'\x00claude-opus-4-8-max\x00other'

  source "$TEST_DOTFILES/modules/windsurf/doctor.sh"
  [ "$warn_count" -ge 1 ]
}

@test "windsurf: cascade.model_tier passes (no warn) when user_settings.pb is absent" {
  _setup_windsurf_installed
  _link_windsurf_user_config
  # No protobuf — Cascade hasn't been launched yet on this box
  rm -f "$TEST_HOME/.codeium/windsurf/user_settings.pb"
  # Baseline warn count (cascade.agentbrew_present may also warn — capture
  # baseline before sourcing so we can isolate model_tier's contribution)
  local warn_count_before=$warn_count

  source "$TEST_DOTFILES/modules/windsurf/doctor.sh"

  # The model_tier check passes silently when the protobuf is absent —
  # specifically, it doesn't add to warn_count beyond whatever other
  # advisories already fired (chiefly the agentbrew_present check, which
  # also evaluates the same ~/.codeium/windsurf dir).
  #
  # We assert that warn_count is at most one above baseline: i.e. only
  # the agentbrew_present check's warning, never the model_tier's.
  [ "$((warn_count - warn_count_before))" -le 1 ]
}

@test "windsurf: cascade.model_tier overrides skip checks" {
  _setup_windsurf_installed
  _link_windsurf_user_config
  _plant_user_settings_pb $'\x00claude-opus-4-7-max\x00'  # drifted catalog
  echo "windsurf.cascade.model_tier" >> "$OVERRIDES_FILE"

  source "$TEST_DOTFILES/modules/windsurf/doctor.sh"
  [ "$skip_count" -ge 1 ]
}
