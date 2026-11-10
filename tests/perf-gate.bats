#!/usr/bin/env bats
# scripts/perf-gate.sh: a tracked command may not get slower than the merge-base.
# Each test builds a small git repo with one tracked script that sleeps, so the
# times are known: 100 ms at the base, 120 ms (20% more) in a slowed head.

load host-load

REPO_ROOT="$BATS_TEST_DIRNAME/.."
GATE="$REPO_ROOT/scripts/perf-gate.sh"
BUDGET="$REPO_ROOT/config/perf-budget.tsv"

setup() {
  TEST_DIR="$(cd "$(mktemp -d)" && pwd -P)"
  FIX="$TEST_DIR/repo"
  export GIT_CONFIG_GLOBAL=/dev/null
  export XDG_CACHE_HOME="$TEST_DIR/cache"
  export PERF_GATE_BASE=main PERF_GATE_RUNS=3 PERF_GATE_WARMUPS=0 PERF_GATE_HEAVY_RUN=0
  unset HEAVY_RUN_SLOT
  git init -q -b main "$FIX"
  mkdir -p "$FIX/config"
  tool 0.10
  budget 'tool	2000	./tool.sh'
  commit base
  git -C "$FIX" checkout -q -b work
}

teardown() { rm -rf "$TEST_DIR"; }

# tool <seconds> [file]: write a tracked script that sleeps that long.
tool() {
  printf '#!/bin/bash\nsleep %s\n' "$1" > "$FIX/${2:-tool.sh}"
  chmod +x "$FIX/${2:-tool.sh}"
}

# budget <line>...: write the fixture budget file with these extra lines.
budget() {
  {
    printf 'PERF_GATE_PATH=tool.sh\nPERF_GATE_PATH=new.sh\nPERF_GATE_PATH=config/perf-budget.tsv\n'
    printf '%s\n' "$@"
  } > "$FIX/config/perf-budget.tsv"
}

commit() {
  git -C "$FIX" add -A
  git -C "$FIX" -c user.name=t -c user.email=t@example.com commit -q --no-verify -m "$1"
}

gate() { run bash -c 'cd "$1" && shift && "$@"' _ "$FIX" "$GATE" "$@"; }

# A 20% slowdown must fail the gate. On a saturated host (bats --jobs) the
# wall clock measures the host, so a miss there is a skip, not a failure.
slowdown_seen() {
  [ "$status" -eq 1 ] && return 0
  [ "$status" -eq 0 ] && host_is_saturated && skip "host is saturated; timing is not reliable"
  return 1
}

@test "perf gate fails on a seeded 20% slowdown and names the command" {
  tool 0.12
  gate
  slowdown_seen
  [[ "$output" == *"tool got slower"* ]]
  [[ "$output" == *"perf gate: FAIL"* ]]
  [[ "$output" == *"Make the command faster"* ]]
  [[ "$output" == *"PERF_GATE_ALLOW=<name>:<reason>"* ]]
}

@test "perf gate sees a committed slowdown too" {
  tool 0.12
  commit slower
  gate
  slowdown_seen
  [[ "$output" == *"tool got slower"* ]]
}

@test "perf gate passes when the trees are equally fast" {
  printf '# a comment\n' >> "$FIX/tool.sh"
  gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"perf gate: pass (1 commands"* ]]
  [[ "$output" =~ tool[[:space:]]+base.*head.*ok ]]
}

@test "perf gate fails when the command is over its ceiling" {
  budget 'tool	50	./tool.sh'
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool is over its ceiling"* ]]
}

@test "perf gate skips a diff with no runtime change" {
  echo docs > "$FIX/README.md"
  mkdir -p "$FIX/tests" && echo t > "$FIX/tests/x.bats"
  gate
  [ "$status" -eq 0 ]
  [ "$output" = "perf gate: skipped (no runtime change)" ]
  [ ! -e "$XDG_CACHE_HOME/dotfiles/perf-gate" ]
}

@test "perf gate --force times the commands with no runtime change" {
  gate --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"perf gate: pass"* ]]
}

@test "a command that is missing at the base gets the ceiling check only" {
  tool 0.10 new.sh
  budget 'tool	2000	./tool.sh' 'fresh	2000	./new.sh'
  gate
  [ "$status" -eq 0 ]
  [[ "$output" =~ fresh[[:space:]]+base[[:space:]]+-.*new ]]

  budget 'tool	2000	./tool.sh' 'fresh	50	./new.sh'
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"fresh is over its ceiling"* ]]
}

@test "an allow line passes an intended slowdown, for one PR only" {
  tool 0.12
  budget 'tool	2000	./tool.sh' 'PERF_GATE_ALLOW=tool:does more work on purpose'
  gate
  [ "$status" -eq 0 ]
  [[ "$output" =~ tool.*allowed ]] || { host_is_saturated && skip "host is saturated; timing is not reliable"; return 1; }

  # After the merge the base has the line too: the next PR must remove it.
  commit allow
  git -C "$FIX" branch -q -f main work
  printf '# touch\n' >> "$FIX/tool.sh"
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"PERF_GATE_ALLOW=tool is already in the base budget file"* ]]
}

@test "an allow line does not lift the ceiling" {
  tool 0.12
  budget 'tool	50	./tool.sh' 'PERF_GATE_ALLOW=tool:on purpose'
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool is over its ceiling"* ]]
}

@test "a command that fails in this tree fails the gate" {
  printf '#!/bin/bash\nexit 3\n' > "$FIX/tool.sh"
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool: the command failed in this tree (status 3)"* ]]
}

@test "perf gate --json prints base_min, head_min, ratio, and verdict per command" {
  tool 0.12
  run bash -c 'cd "$1" && "$2" --json 2>/dev/null' _ "$FIX" "$GATE"
  slowdown_seen
  echo "$output" | jq -e '.skipped == false and .ok == false and (.base | length == 40)
    and (.commands | length == 1)
    and (.commands[0] | .name == "tool" and .verdict == "slower" and .base_min >= 100
      and .head_min >= 120 and .ratio > 1.1 and .ceiling_ms == 2000)'

  git -C "$FIX" checkout -q tool.sh
  echo docs > "$FIX/README.md"
  gate --json
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.skipped == true and .reason == "no runtime change"'
}

@test "the commands run with a scratch HOME and without the caller's environment" {
  printf '#!/bin/bash\n[ -z "${BASH_ENV:-}" ] && [ -z "${SECRET_THING:-}" ] && [ "$DO_NOT_TRACK" = 1 ] && [ "$HOME" != "%s" ]\n' "$HOME" > "$FIX/tool.sh"
  run bash -c 'cd "$1" && BASH_ENV=/nonexistent SECRET_THING=x "$2"' _ "$FIX" "$GATE"
  [ "$status" -eq 0 ]
}

@test "timing goes through heavy-run --exclusive, but not inside a heavy-run slot" {
  mkdir -p "$TEST_DIR/bin"
  printf '#!/bin/bash\necho "$1" >> "%s/heavy-run.calls"\nshift\nexec "$@"\n' "$TEST_DIR" > "$TEST_DIR/bin/heavy-run"
  chmod +x "$TEST_DIR/bin/heavy-run"
  printf '# touch\n' >> "$FIX/tool.sh"

  run bash -c 'cd "$1" && PATH="$3:$PATH" PERF_GATE_HEAVY_RUN=1 "$2"' _ "$FIX" "$GATE" "$TEST_DIR/bin"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_DIR/heavy-run.calls")" = "--exclusive" ]

  run bash -c 'cd "$1" && PATH="$3:$PATH" PERF_GATE_HEAVY_RUN=1 HEAVY_RUN_SLOT=1 "$2"' _ "$FIX" "$GATE" "$TEST_DIR/bin"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already inside a heavy-run slot"* ]]
  [ "$(wc -l < "$TEST_DIR/heavy-run.calls" | tr -d ' ')" = 1 ]
}

@test "the base checkout is cached by commit and only two are kept" {
  local cache="$XDG_CACHE_HOME/dotfiles/perf-gate" first second third
  first="$(git -C "$FIX" rev-parse main)"
  printf '# touch\n' >> "$FIX/tool.sh"
  gate
  [ "$status" -eq 0 ]
  [ -x "$cache/$first/tool.sh" ]

  for n in 2 3; do
    commit "step $n"
    git -C "$FIX" branch -q -f main work
    printf '# touch %s\n' "$n" >> "$FIX/tool.sh"
    sleep 1
    gate
    [ "$status" -eq 0 ]
    [ "$n" = 2 ] && second="$(git -C "$FIX" rev-parse main)"
  done
  third="$(git -C "$FIX" rev-parse main)"
  [ ! -e "$cache/$first" ]
  [ -d "$cache/$second" ]
  [ -d "$cache/$third" ]
  [ "$(git -C "$FIX" worktree list | wc -l | tr -d ' ')" = 3 ]
}

@test "a bad budget line is a setup error" {
  budget 'tool	fast	./tool.sh'
  gate
  [ "$status" -eq 2 ]
  [[ "$output" == *"bad line"* ]]
}

@test "the committed budget lists real executables, ceilings, and runtime paths" {
  local n=0 name ceiling cmd rest prog
  while IFS=$'\t' read -r name ceiling cmd rest; do
    case "$name" in '' | '#'* | PERF_GATE_*) continue ;; esac
    n=$((n + 1))
    [[ "$ceiling" =~ ^[0-9]+$ ]] || { echo "bad ceiling: $name"; return 1; }
    prog="${cmd%% *}"
    [ -x "$REPO_ROOT/$prog" ] || { echo "not executable: $prog"; return 1; }
  done < "$BUDGET"
  [ "$n" -ge 5 ]
  grep -qx 'PERF_GATE_PATH=bin/' "$BUDGET"
  grep -qx 'PERF_GATE_PATH=agent-hooks/' "$BUDGET"
  ! grep -q '^PERF_GATE_ALLOW=' <(git -C "$REPO_ROOT" show "$(git -C "$REPO_ROOT" merge-base HEAD origin/feat/chezmoi 2>/dev/null):config/perf-budget.tsv" 2>/dev/null) || skip "an allow line waits for its removal PR"
}

@test "make check runs the perf gate as a timed step, and make perf-gate exists" {
  grep -qE 'gate-timed.sh perf-gate .*perf-gate$' "$REPO_ROOT/Makefile"
  grep -qE '^perf-gate: ## ' "$REPO_ROOT/Makefile"
  head -1 "$GATE" | grep -qx '#!/bin/bash'
}
