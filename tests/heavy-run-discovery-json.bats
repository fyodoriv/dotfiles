#!/usr/bin/env bats

setup_file() {
  export MODEL="$BATS_TEST_DIRNAME/fixtures/heavy-run-discovery-json-model.py"
  export MODEL_HOME="$BATS_FILE_TMPDIR/home"
  export MODEL_SITE="$BATS_FILE_TMPDIR/site"
  export MODEL_CANARY="$BATS_FILE_TMPDIR/site-canary"
  export DISPATCH_CANARY="$BATS_FILE_TMPDIR/dispatched"
  mkdir -p "$MODEL_HOME/.config" "$MODEL_HOME/tmp" "$MODEL_SITE" "$BATS_FILE_TMPDIR/bin"
  local candidate
  candidate="$(command -v python3)"
  export MODEL_PYTHON
  MODEL_PYTHON="$(env -i HOME="$MODEL_HOME" PATH=/usr/bin:/bin "$candidate" -I -S -c 'import os,sys; print(os.path.realpath(sys.executable))')"
  [ -x "$MODEL_PYTHON" ]
  env -i HOME="$MODEL_HOME" PATH=/usr/bin:/bin "$MODEL_PYTHON" -I -S --version > "$BATS_FILE_TMPDIR/python-version" 2>&1
  printf '# isolated interpreter: %s; %s\n' "$MODEL_PYTHON" "$(cat "$BATS_FILE_TMPDIR/python-version")" >&3
  cat > "$MODEL_SITE/sitecustomize.py" <<'PY'
import os
open(os.environ["SENTINEL_PATH"], "w").close()
PY
  env -i HOME="$MODEL_HOME" PATH=/usr/bin:/bin PYTHONPATH="$MODEL_SITE" SENTINEL_PATH="$MODEL_CANARY" "$MODEL_PYTHON" -c pass
  [ -f "$MODEL_CANARY" ]
  rm "$MODEL_CANARY"
  env -i HOME="$MODEL_HOME" PATH=/usr/bin:/bin PYTHONPATH="$MODEL_SITE" SENTINEL_PATH="$MODEL_CANARY" "$MODEL_PYTHON" -I -S -c pass
  [ ! -e "$MODEL_CANARY" ]
  printf '#!/bin/sh\ntouch "$DISPATCH_CANARY"\nexit 99\n' > "$BATS_FILE_TMPDIR/bin/bats"
  chmod +x "$BATS_FILE_TMPDIR/bin/bats"
}

model_run() {
  env -i HOME="$MODEL_HOME" TMPDIR="$MODEL_HOME/tmp" XDG_CONFIG_HOME="$MODEL_HOME/.config" \
    PATH="$BATS_FILE_TMPDIR/bin:/usr/bin:/bin" PYTHONPATH="$MODEL_SITE" \
    SENTINEL_PATH="$MODEL_CANARY" DISPATCH_CANARY="$DISPATCH_CANARY" \
    "$MODEL_PYTHON" -I -S "$MODEL"
}

@test "P01" {
  printf '%s' '{"tool_input":{"command":"command -v bats"}}' > "$BATS_TEST_TMPDIR/input"
  run model_run < "$BATS_TEST_TMPDIR/input"
  [ "$status" -eq 0 ] || { echo 'model invocation failed' >&2; return 2; }
  [ ! -e "$MODEL_CANARY" ] && [ ! -e "$DISPATCH_CANARY" ]
  [ "$output" = allow ] || { echo 'expected exact discovery allow' >&2; return 1; }
}

assert_model() {
  local expected="$1"
  run model_run < "$BATS_TEST_TMPDIR/input"
  [ "$status" -eq 0 ]
  [ ! -e "$MODEL_CANARY" ] && [ ! -e "$DISPATCH_CANARY" ]
  [ "$output" = "$expected" ]
}

@test "P02" {
  printf '%s' '{"tool_input":{"command":"command -v bats\ncommand -v greadlink"}}' > "$BATS_TEST_TMPDIR/input"
  assert_model allow
}

@test "N01" {
  printf '%s' '{"tool_input":{"command":"\u0000command -v bats"}}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N02" {
  printf '%s' '{"tool_input":{"command":"command -v \u0000bats"}}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N03" {
  printf '%s' '{"tool_input":{"command":"command -v bats\u0000"}}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N04" {
  printf '%s' '{"tool_input":{"command":"command -v bats\u0000; bats"}}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N05" {
  printf '{"tool_input":{"command":"command -v bats\000"}}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N06" {
  printf '%s' '{"tool_input":{"command":"bats","command":"command -v bats"}}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N07" {
  printf '%s' '{"tool_input":{"command":"command -v bats","command":"bats"}}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N08" {
  printf '%s' '{"tool_input":{"command":"bats"},"tool_input":{"command":"command -v bats"}}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N09" {
  printf '%s' '{"tool_input":{"command":"command -v bats"},"tool_input":{"command":"bats"}}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N10" {
  printf '%s' '{"tool_input":{"command":"command -v bats"},"extra":{"x":1,"x":2}}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N11" {
  printf '%s' '{"tool_input":' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N12" {
  printf '%s' '{"tool_input":{"command":"command -v bats"}} {}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N13" {
  printf '%s' '[{"tool_input":{"command":"command -v bats"}}]' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N14" {
  printf '%s' '{"tool_input":{}}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N15" {
  printf '%s' '{"tool_input":{"command":1}}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N16" {
  printf '%s' '{"tool_input":{"command":"command -v bats && bats"}}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N17" {
  printf '%s' '{"tool_input":{"command":"$(command -v bats)"}}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N18" {
  printf '%s' '{"tool_input":{"command":"command -v bats\r\ncommand -v greadlink"}}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N19" {
  printf '%s' '{"tool_input":{"command":"command -v bats\\u0000"}}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N20" {
  printf '%s' '{"tool_input":{"command":"command -v bats"}}' > "$BATS_TEST_TMPDIR/input"
  size=$(wc -c < "$BATS_TEST_TMPDIR/input")
  head -c $((65537 - size)) /dev/zero | tr '\000' ' ' >> "$BATS_TEST_TMPDIR/input"
  [ "$(wc -c < "$BATS_TEST_TMPDIR/input" | tr -d ' ')" -eq 65537 ]
  assert_model fallback
}

@test "N21" {
  printf '{"tool_input":{"command":"command -v bats"},"extra":"\377"}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N22" {
  printf '%s' '{"tool_input":{"command":"command -v bats"},"extra":NaN}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N23" {
  printf '%s' '{"tool_input":{"command":"command -v bats"},"extra":"\ud800"}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N24" {
  printf '%s' '{"tool_input":{"command":"command  -v bats"}}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N25" {
  printf '%s' '{"tool_input":{"command":"heavy-run bats"}}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N26" {
  printf '%s' '{"tool_input":{"command":"bats tests/fixture.bats"}}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N27" {
  env -i HOME="$MODEL_HOME" PATH=/usr/bin:/bin "$MODEL_PYTHON" -I -S -c 'import sys; assert sys.getrecursionlimit() < 2000'
  printf '%s' '{"tool_input":{"command":"command -v bats"},"extra":' > "$BATS_TEST_TMPDIR/input"
  printf '%2000s' '' | tr ' ' '[' >> "$BATS_TEST_TMPDIR/input"
  printf '0' >> "$BATS_TEST_TMPDIR/input"
  printf '%2000s' '' | tr ' ' ']' >> "$BATS_TEST_TMPDIR/input"
  printf '}' >> "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N28" {
  printf '%s' '{"tool_input":{"command":"command -v bats"},"extra":' > "$BATS_TEST_TMPDIR/input"
  printf '%129s' '' | tr ' ' '1' >> "$BATS_TEST_TMPDIR/input"
  printf '}' >> "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N29" {
  printf '%s' '{"tool_input":{"command":"command -v bats"},"extra":{"value":"\u0000"}}' > "$BATS_TEST_TMPDIR/input"
  assert_model fallback
}

@test "N30" {
  run env -i HOME="$MODEL_HOME" TMPDIR="$MODEL_HOME/tmp" XDG_CONFIG_HOME="$MODEL_HOME/.config" \
    PATH="$BATS_FILE_TMPDIR/bin:/usr/bin:/bin" PYTHONPATH="$MODEL_SITE" \
    SENTINEL_PATH="$MODEL_CANARY" DISPATCH_CANARY="$DISPATCH_CANARY" \
    "$MODEL_PYTHON" -I -S -c '
import pathlib, runpy, sys
class Reader:
    @property
    def buffer(self):
        return self
    def read(self, size):
        with pathlib.Path(sys.argv[2]).open("a") as marker:
            marker.write(str(size) + "\n")
        raise OSError("synthetic read failure")
sys.stdin = Reader()
runpy.run_path(sys.argv[1], run_name="__main__")
' "$MODEL" "$BATS_TEST_TMPDIR/read-canary"
  [ "$(cat "$BATS_TEST_TMPDIR/read-canary")" = 65537 ]
  [ ! -e "$MODEL_CANARY" ] && [ ! -e "$DISPATCH_CANARY" ]
  [ "$status" -eq 0 ]
  [ "$output" = fallback ]
}
