#!/usr/bin/env bats

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  FIXTURE="$BATS_TEST_TMPDIR/fixture"
  CONFIG="$BATS_TEST_TMPDIR/configured"
  mkdir -p "$FIXTURE/agent-hooks" "$FIXTURE/bin" "$FIXTURE/lib" "$CONFIG/bin" "$CONFIG/lib" "$BATS_TEST_TMPDIR/home"
  cp "$ROOT/agent-hooks/bootstrap-endpoint-path.sh" "$BATS_TEST_TMPDIR/original"
  cmp "$ROOT/agent-hooks/bootstrap-endpoint-path.sh" "$BATS_TEST_TMPDIR/original"
  printf '%s\n' untouched > "$BATS_TEST_TMPDIR/canary"
  HELPER="$BATS_TEST_TMPDIR/helper"
  /bin/cat > "$HELPER" <<'HELPER'
export FIXTURE_MARKER=loaded
dotfiles_prepend_endpoint_tool_paths() { PATH="$1:$PATH"; export PATH; }
dotfiles_resolve_jq() { :; }
dotfiles_resolve_find() { :; }
dotfiles_resolve_fnm_node_bin() { :; }
dotfiles_resolve_python() { :; }
HELPER
}

prepare_instrumented() {
  env -i PATH=/usr/bin:/bin HOME="$BATS_TEST_TMPDIR/home" /usr/bin/python3 -I - "$BATS_TEST_TMPDIR/original" "$BATS_TEST_TMPDIR/instrumented" "${1:-normal}" <<'PYCODE'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_bytes()
needle = b'  source "$lib_root/lib/dotfiles-endpoint-paths.sh"\n'
if sys.argv[3] == 'mismatch':
    needle = b'not-the-source-boundary\n'
if source.count(needle) != 1:
    sys.exit(1)
snippet = b'''  case "$lib_root" in
    "$FIXTURE_CONFIG") printf '%s\\n' configured >&9 ;;
    "$FIXTURE_FALLBACK") printf '%s\\n' fallback >&9 ;;
    *) printf '%s\\n' inconclusive >&9 ;;
  esac
'''
Path(sys.argv[2]).write_bytes(source.replace(needle, snippet + needle, 1))
PYCODE
}

run_copy() {
  local copy="$1" tag="$2" selected="$3"
  cp "$copy" "$FIXTURE/agent-hooks/bootstrap-endpoint-path.sh"
  cmp "$copy" "$FIXTURE/agent-hooks/bootstrap-endpoint-path.sh"
  env -i PATH=/usr/bin:/bin HOME="$BATS_TEST_TMPDIR/home" DOTFILES_DIR="$selected" \
    FIXTURE_CONFIG="$selected" FIXTURE_FALLBACK="$FIXTURE" \
    /bin/bash --noprofile --norc -c 'source "$1"; printf "%s\n%s\n%s\n" "${FIXTURE_MARKER-}" "${DOTFILES_DIR-}" "$PATH"' \
    _ "$FIXTURE/agent-hooks/bootstrap-endpoint-path.sh" \
    9>"$BATS_TEST_TMPDIR/$tag.receipt" >"$BATS_TEST_TMPDIR/$tag.out" 2>"$BATS_TEST_TMPDIR/$tag.err"
}

compare_fixture() {
  local selected="$1" expected="$2"
  prepare_instrumented
  run_copy "$BATS_TEST_TMPDIR/original" baseline "$selected"
  run_copy "$BATS_TEST_TMPDIR/instrumented" observed "$selected"
  cmp "$BATS_TEST_TMPDIR/baseline.out" "$BATS_TEST_TMPDIR/observed.out"
  cmp "$BATS_TEST_TMPDIR/baseline.err" "$BATS_TEST_TMPDIR/observed.err"
  [ ! -s "$BATS_TEST_TMPDIR/baseline.receipt" ]
  if [ "$expected" = absent ]; then
    [ ! -s "$BATS_TEST_TMPDIR/observed.receipt" ]
    ! /usr/bin/grep -qx loaded "$BATS_TEST_TMPDIR/observed.out"
  else
    [ "$(/bin/cat "$BATS_TEST_TMPDIR/observed.receipt")" = "$expected" ]
    [ "$(/usr/bin/wc -l < "$BATS_TEST_TMPDIR/observed.receipt" | /usr/bin/tr -d ' ')" = 1 ]
    /usr/bin/grep -qx loaded "$BATS_TEST_TMPDIR/observed.out"
  fi
  [ "$(/bin/cat "$BATS_TEST_TMPDIR/canary")" = untouched ]
}

@test "configured helper is observed" {
  cp "$HELPER" "$CONFIG/lib/dotfiles-endpoint-paths.sh"
  compare_fixture "$CONFIG" configured
}

@test "fallback helper is observed" {
  cp "$HELPER" "$FIXTURE/lib/dotfiles-endpoint-paths.sh"
  compare_fixture "$CONFIG" fallback
}

@test "missing helper has no receipt" {
  compare_fixture "$CONFIG" absent
}

@test "stale configured root falls back" {
  cp "$HELPER" "$FIXTURE/lib/dotfiles-endpoint-paths.sh"
  compare_fixture "$BATS_TEST_TMPDIR/stale" fallback
}

@test "symlinked configured root is observed" {
  cp "$HELPER" "$CONFIG/lib/dotfiles-endpoint-paths.sh"
  ln -s "$CONFIG" "$BATS_TEST_TMPDIR/link"
  compare_fixture "$BATS_TEST_TMPDIR/link" configured
}

@test "transform mismatch refuses before running a copy" {
  run prepare_instrumented mismatch
  [ "$status" -ne 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/instrumented" ]
  [ ! -e "$FIXTURE/agent-hooks/bootstrap-endpoint-path.sh" ]
  [ "$(/bin/cat "$BATS_TEST_TMPDIR/canary")" = untouched ]
}

@test "closed receipt descriptor surfaces failure" {
  cp "$HELPER" "$CONFIG/lib/dotfiles-endpoint-paths.sh"
  prepare_instrumented
  cp "$BATS_TEST_TMPDIR/instrumented" "$FIXTURE/agent-hooks/bootstrap-endpoint-path.sh"
  cmp "$BATS_TEST_TMPDIR/instrumented" "$FIXTURE/agent-hooks/bootstrap-endpoint-path.sh"
  run env -i PATH=/usr/bin:/bin HOME="$BATS_TEST_TMPDIR/home" DOTFILES_DIR="$CONFIG" \
    FIXTURE_CONFIG="$CONFIG" FIXTURE_FALLBACK="$FIXTURE" \
    /bin/bash --noprofile --norc -c 'source "$1"; printf "%s\n" "${FIXTURE_MARKER-}"' \
    _ "$FIXTURE/agent-hooks/bootstrap-endpoint-path.sh" 9>&-
  [ "$status" -ne 0 ]
  [[ "$output" != *loaded* ]]
  [ "$(/bin/cat "$BATS_TEST_TMPDIR/canary")" = untouched ]
}
