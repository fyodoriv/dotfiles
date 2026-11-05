#!/usr/bin/env bats

setup() {
  ROOT="$BATS_TEST_DIRNAME/.."
  SKILL="$ROOT/skills/update-tooling/SKILL.md"
  fixture="$BATS_TEST_TMPDIR/capability"
  tools="$fixture/bin"
  applied="$fixture/applied"
  mkdir -p "$tools" "$applied/.git" "$applied/dist" "$fixture/home"
  printf 'old distribution\n' > "$applied/dist/cli.js"
  awk '/^AGENTBREW_APPLIED=/{capture=1} capture && /^```/{exit} capture {print}' "$SKILL" > "$fixture/build.sh"
  cat > "$tools/git" <<'STUB'
#!/bin/bash
case "$3" in
  fetch|status|merge-base|merge) exit 0 ;;
  diff) exit 1 ;;
  *) exit 65 ;;
esac
STUB
  cat > "$tools/uname" <<'STUB'
#!/bin/bash
case "$1" in -s) printf '%s\n' "${FIXTURE_OS:-Darwin}" ;; -m) printf '%s\n' arm64 ;; esac
STUB
  cat > "$tools/node" <<'STUB'
#!/bin/bash
[ "$*" = 'scripts/native-build-tools.mjs available' ] || exit 66
printf 'probe\n' >> "$FIXTURE_EVENTS"
exit "${FIXTURE_VERIFY:-1}"
STUB
  cat > "$tools/npm" <<'STUB'
#!/bin/bash
printf 'build\n' >> "$FIXTURE_EVENTS"
printf 'new distribution\n' > "$AGENTBREW_APPLIED/dist/cli.js"
STUB
  cat > "$tools/heavy-run" <<'STUB'
#!/bin/bash
exec "$@"
STUB
  chmod +x "$tools/"*
}

_run_build() {
  run /usr/bin/env -u BASH_ENV -u ENV PATH="$tools" HOME="$fixture/home" \
    AGENTBREW_APPLIED="$applied" FIXTURE_EVENTS="$fixture/events" \
    FIXTURE_VERIFY="${probe_status:-1}" FIXTURE_OS="${host_os:-Darwin}" \
    /bin/bash "$fixture/build.sh"
}

_preserved() {
  [ "$(cat "$applied/dist/cli.js")" = 'old distribution' ]
  if [ -f "$fixture/events" ]; then ! grep -q '^build$' "$fixture/events"; fi
}

@test "inventory reads the branch through symbolic-ref" {
  grep -Fq 'current_branch="$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"' "$SKILL"
}

@test "legacy Apple Silicon checkout without Cargo refuses before build" {
  _run_build
  _preserved
  [[ "$output" == *'native build capability'* ]]
}

@test "failed native prebuilt probe preserves the old distribution" {
  mkdir -p "$applied/scripts"
  touch "$applied/scripts/native-build-tools.mjs"
  _run_build
  _preserved
  grep -q '^probe$' "$fixture/events"
  [[ "$output" == *'native build capability'* ]]
}

@test "qualified prebuilt allows the build without Cargo" {
  mkdir -p "$applied/scripts"
  touch "$applied/scripts/native-build-tools.mjs"
  probe_status=0
  _run_build
  [ "$status" -eq 0 ]
  grep -q '^probe$' "$fixture/events"
  grep -q '^build$' "$fixture/events"
}

@test "legacy checkout with Cargo retains its build path" {
  printf '#!/bin/bash\nexit 0\n' > "$tools/cargo"
  chmod +x "$tools/cargo"
  _run_build
  [ "$status" -eq 0 ]
  grep -q '^build$' "$fixture/events"
}

@test "other hosts keep their existing build path" {
  host_os=Linux
  _run_build
  [ "$status" -eq 0 ]
  grep -q '^build$' "$fixture/events"
}

@test "endpoint safe mode does not probe or build" {
  mkdir -p "$fixture/home/.local/state/dotfiles"
  touch "$fixture/home/.local/state/dotfiles/endpoint-node-publisher-blocked"
  _run_build
  [ "$status" -eq 0 ]
  _preserved
  [ ! -e "$fixture/events" ]
}

@test "current Git guard allows branch reading and literal prose" {
  for text in 'git branch --show-current' 'git symbolic-ref --quiet --short HEAD'; do
    payload=$(jq -n --arg command "$text" '{tool_input:{command:$command}}')
    run bash -c 'printf "%s" "$1" | bash "$2/agent-hooks/block-dangerous-git.sh"' _ "$payload" "$ROOT"
    [ "$status" -eq 0 ]
  done
  payload=$(jq -n --arg command "cat <<'NOTE'
git branch --show-current
NOTE
" '{tool_input:{command:$command}}')
  run bash -c 'printf "%s" "$1" | bash "$2/agent-hooks/block-dangerous-git.sh"' _ "$payload" "$ROOT"
  [ "$status" -eq 0 ]
}

@test "current Git guard still refuses an actual force-delete" {
  payload=$(jq -n --arg command 'git branch -D' '{tool_input:{command:$command}}')
  run bash -c 'printf "%s" "$1" | bash "$2/agent-hooks/block-dangerous-git.sh"' _ "$payload" "$ROOT"
  [ "$status" -eq 2 ]
}
