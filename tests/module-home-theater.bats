#!/usr/bin/env bats
# Tests for modules/home-theater/doctor.sh (Plex, VLC, Samsung TV).

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  [ -n "$TEST_DIR" ] || return 1
  TEST_HOME="$TEST_DIR/home"
  MOCK_BIN="$TEST_DIR/bin"
  mkdir -p "$TEST_HOME/Applications" "$MOCK_BIN"
  export HOME="$TEST_HOME"
  export PATH="$MOCK_BIN:$PATH"
  export DOTFILES_PROFILE="full"
  export HOME_THEATER_ENABLED=true
  unset SAMSUNG_TV_HOST
  export HOME_THEATER_APPS_DIR="$TEST_DIR/no-apps"
  MODULE="$BATS_TEST_DIRNAME/../modules/home-theater/doctor.sh"

  # Mocks read their answers from files in $TEST_DIR.
  cat > "$MOCK_BIN/curl" <<'MOCK'
#!/bin/bash
for a in "$@"; do url="$a"; done
case "$url" in
  */identity) [ -f "$MOCK_DIR/plex" ] && cat "$MOCK_DIR/plex" || exit 7 ;;
  *:8001/api/v2/) [ -f "$MOCK_DIR/tv" ] && cat "$MOCK_DIR/tv" || exit 7 ;;
  *) exit 7 ;;
esac
MOCK
  cat > "$MOCK_BIN/duti" <<'MOCK'
#!/bin/bash
if [ "$1" = "-x" ]; then cat "$MOCK_DIR/duti" 2>/dev/null; exit 0; fi
echo "$*" >> "$MOCK_DIR/duti-set"
printf 'VLC\n/Applications/VLC.app\norg.videolan.vlc\n' > "$MOCK_DIR/duti"
MOCK
  cat > "$MOCK_BIN/pmset" <<'MOCK'
#!/bin/bash
printf 'Battery Power:\n sleep                %s\nAC Power:\n sleep                %s\n' "$(cat "$MOCK_DIR/battery" 2>/dev/null || echo 1)" "$(cat "$MOCK_DIR/sleep" 2>/dev/null || echo 10)"
MOCK
  chmod +x "$MOCK_BIN"/*
  export MOCK_DIR="$TEST_DIR"

  FIX_MODE=false
  results=()
  check() {
    local id="$1" test_cmd="$3" fix_cmd="${4:-}"
    if eval "$test_cmd" >/dev/null 2>&1; then
      results+=("$id=pass")
    elif $FIX_MODE && [ -n "$fix_cmd" ] && eval "$fix_cmd" >/dev/null 2>&1 && eval "$test_cmd" >/dev/null 2>&1; then
      results+=("$id=fixed")
    else
      results+=("$id=fail")
    fi
  }
}

teardown() {
  rm -rf "$TEST_DIR"
}

result() { local r; for r in "${results[@]}"; do [ "${r%%=*}" = "$1" ] && echo "${r#*=}"; done; }

good_machine() {
  mkdir -p "$TEST_HOME/Applications/Plex Media Server.app" "$TEST_HOME/Applications/VLC.app"
  echo '<MediaContainer size="0" machineIdentifier="abc" version="1.43"/>' > "$TEST_DIR/plex"
  printf 'VLC\n/Applications/VLC.app\norg.videolan.vlc\n' > "$TEST_DIR/duti"
  echo 0 > "$TEST_DIR/sleep"
  echo '{"device":{"modelName":"QN65S92C","networkType":"wired"}}' > "$TEST_DIR/tv"
  export SAMSUNG_TV_HOST=tv.example.com
}

@test "home-theater: skipped unless opted in" {
  HOME_THEATER_ENABLED=false
  source "$MODULE"
  [ "${#results[@]}" -eq 0 ]
}

@test "home-theater: skipped on the core profile" {
  DOTFILES_PROFILE=core
  source "$MODULE"
  [ "${#results[@]}" -eq 0 ]
}

@test "home-theater: a good machine passes all six checks" {
  command -v jq >/dev/null || skip "jq not installed"
  good_machine
  source "$MODULE"
  [ "${#results[@]}" -eq 6 ]
  for r in "${results[@]}"; do [ "${r#*=}" = pass ] || { echo "$r"; return 1; }; done
}

@test "home-theater: missing apps fail" {
  source "$MODULE"
  [ "$(result tool.plex-media-server)" = fail ]
  [ "$(result tool.vlc)" = fail ]
}

@test "home-theater: Plex not answering fails" {
  good_machine
  rm "$TEST_DIR/plex"
  source "$MODULE"
  [ "$(result home_theater.plex_running)" = fail ]
}

@test "home-theater: mkv opened by another app fails, and the fix sets VLC for mkv, avi, webm" {
  good_machine
  printf 'QuickTime Player\n' > "$TEST_DIR/duti"
  source "$MODULE"
  [ "$(result home_theater.vlc_default_mkv)" = fail ]
  results=(); FIX_MODE=true
  printf 'QuickTime Player\n' > "$TEST_DIR/duti"
  source "$MODULE"
  [ "$(result home_theater.vlc_default_mkv)" = fixed ]
  grep -q 'org.videolan.vlc .mkv all' "$TEST_DIR/duti-set"
  grep -q 'org.videolan.vlc .webm all' "$TEST_DIR/duti-set"
}

@test "home-theater: system sleep on AC power fails (reads the AC section, not battery)" {
  good_machine
  echo 10 > "$TEST_DIR/sleep"
  echo 0 > "$TEST_DIR/battery"
  source "$MODULE"
  [ "$(result home_theater.no_sleep_on_ac)" = fail ]
}

@test "home-theater: Samsung TV on Wi-Fi fails; no host means no TV check" {
  command -v jq >/dev/null || skip "jq not installed"
  good_machine
  echo '{"device":{"modelName":"QN65S92C","networkType":"wireless"}}' > "$TEST_DIR/tv"
  source "$MODULE"
  [ "$(result home_theater.tv_wired)" = fail ]
  results=(); unset SAMSUNG_TV_HOST
  source "$MODULE"
  [ -z "$(result home_theater.tv_wired)" ]
}

@test "home-theater: brew template adds plex, vlc and duti only when opted in" {
  tmpl="$BATS_TEST_DIRNAME/../.chezmoiscripts/run_onchange_brew.sh.tmpl"
  grep -A4 'dig "home_theater" false' "$tmpl" | grep -q 'cask "plex-media-server"'
  grep -A4 'dig "home_theater" false' "$tmpl" | grep -q 'cask "vlc"'
  grep -A4 'dig "home_theater" false' "$tmpl" | grep -q 'brew "duti"'
}

@test "home-theater: a TV host with shell characters is ignored, not eval'd" {
  good_machine
  export SAMSUNG_TV_HOST="tv';touch $TEST_DIR/pwned;'"
  source "$MODULE"
  [ -z "$(result home_theater.tv_wired)" ]
  [ ! -e "$TEST_DIR/pwned" ]
}

@test "home-theater: real Samsung JSON with raw control characters still parses" {
  command -v jq >/dev/null || skip "jq not installed"
  good_machine
  printf '{"device":{"modelName":"QN77S92C","networkType":"wired","name":"[TV]\tLiving\n"}}' > "$TEST_DIR/tv"
  source "$MODULE"
  [ "$(result home_theater.tv_wired)" = pass ]
}
