#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../bin/agent-browser-reap-strays"

setup() {
  TEST_DIR="$(mktemp -d)"
  STUB_BIN="$TEST_DIR/bin"
  mkdir -p "$STUB_BIN"
  cat > "$STUB_BIN/curl" <<'EOF'
#!/bin/bash
url=""
for arg in "$@"; do
  case "$arg" in http://*) url="$arg" ;;
  esac
done
port="$(printf '%s\n' "$url" | sed -n 's#.*127\.0\.0\.1:\([0-9][0-9]*\)/.*#\1#p')"
case "$url" in
  */json/list)
    file="$TEST_DIR/list-$port.json"
    [ -f "$file" ] || exit 7
    cat "$file"
    ;;
  */json/close/*)
    id="${url##*/json/close/}"
    printf '%s %s\n' "$port" "$id" >> "$TEST_DIR/closed"
    printf 'Target closed\n'
    ;;
  *)
    exit 7
    ;;
esac
EOF
  chmod +x "$STUB_BIN/curl"
  export TEST_DIR
  export PATH="$STUB_BIN:$PATH"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "reap-strays dry-run reports blank/newtab targets and exits nonzero" {
  cat > "$TEST_DIR/list-9223.json" <<'JSON'
[
  {"id":"newtab-1","type":"page","url":"chrome://newtab/"},
  {"id":"blank-1","type":"page","url":"about:blank"},
  {"id":"real-1","type":"page","url":"https://example.com/"}
]
JSON

  run "$SCRIPT" --dry-run --port 9223

  [ "$status" -eq 1 ]
  [[ "$output" == *"9223: 2 stray target(s)"* ]]
  [ ! -e "$TEST_DIR/closed" ]
}

@test "reap-strays closes only blank/newtab page targets" {
  cat > "$TEST_DIR/list-9224.json" <<'JSON'
[
  {"id":"newtab-1","type":"page","url":"chrome://newtab/"},
  {"id":"newtab-2","type":"page","url":"chrome://newtab"},
  {"id":"blank-1","type":"page","url":""},
  {"id":"real-1","type":"page","url":"https://example.com/"},
  {"id":"worker-1","type":"service_worker","url":"chrome://newtab/"}
]
JSON

  run "$SCRIPT" --port 9224

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_DIR/closed")" = $'9224 newtab-1\n9224 newtab-2\n9224 blank-1' ]
  [[ "$output" == *"9224: closed 3 stray target(s)"* ]]
}

@test "reap-strays skips unreachable ports without failing" {
  run "$SCRIPT" --port 9225

  [ "$status" -eq 0 ]
  [[ "$output" == *"9225: skipped (CDP unreachable)"* ]]
  [ ! -e "$TEST_DIR/closed" ]
}
