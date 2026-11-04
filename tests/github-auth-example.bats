#!/usr/bin/env bats

setup() {
  local example="$BATS_TEST_DIRNAME/../home/zshenv.secrets.example"
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$BATS_TEST_TMPDIR/home"
  awk '/^# Option 1 / { selected=1; next }
       /^# Never hardcode/ { exit }
       selected { sub(/^# ?/, ""); print }' "$example" > "$BATS_TEST_TMPDIR/example.sh"
  test -s "$BATS_TEST_TMPDIR/example.sh"
  cat > "$BATS_TEST_TMPDIR/bin/gh" <<'FAKE'
#!/bin/bash
set -eu
[[ "$*" == 'auth token -h github.com' ]] || exit 91
[[ "${FAKE_LOOKUP_FAILURE:-0}" == 0 ]] || exit 1
printf '%s\n' "${GH_TOKEN:-${GITHUB_TOKEN:-fixture-stored}}"
FAKE
  chmod 700 "$BATS_TEST_TMPDIR/bin/gh"
}

run_example() {
  run /usr/bin/env -i HOME="$BATS_TEST_TMPDIR/home"     PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" "$@"     /bin/bash -c 'source "$1"; test "${GITHUB_TOKEN:-}" = "$EXPECTED"'     bash "$BATS_TEST_TMPDIR/example.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "GitHub CLI example replaces an inherited stale GITHUB_TOKEN" {
  run_example GITHUB_TOKEN=fixture-stale EXPECTED=fixture-stored
}

@test "GitHub CLI example ignores an inherited stale GH_TOKEN" {
  run_example GH_TOKEN=fixture-stale EXPECTED=fixture-stored
}

@test "GitHub CLI example preserves the existing token if lookup fails" {
  run_example GITHUB_TOKEN=fixture-existing FAKE_LOOKUP_FAILURE=1 EXPECTED=fixture-existing
}
