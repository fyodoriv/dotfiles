#!/usr/bin/env bats
# scripts/perf-gate.sh: a tracked command may not get slower than the merge-base.
# Each test builds a small git repo with one tracked script that sleeps, so the
# times are known: 100 ms at the base, 200 ms in a slowed head. The seeded
# slowdown is large on purpose: these tests run next to other bats jobs, and a
# 20% step of a 100 ms command can drown in that load. One test pins the 10%
# limit with a 20% step of a 500 ms command, where the step is 100 ms.
#
# Under memory pressure two equal 100 ms trees have measured 13% apart. So no
# test compares equal 100 ms trees. A test that only needs a runtime change
# calls `quicker` (the head sleeps less than the base), and a test that needs
# equal trees uses a 300 ms or 400 ms tool, where 10% is 30 ms or more.

REPO_ROOT="$BATS_TEST_DIRNAME/.."
GATE="$REPO_ROOT/scripts/perf-gate.sh"
TIMER="$REPO_ROOT/scripts/perf-gate.pl"
BUDGET="$REPO_ROOT/config/perf-budget.tsv"

setup() {
  TEST_DIR="$(cd "$(mktemp -d)" && pwd -P)"
  FIX="$TEST_DIR/repo"
  CACHE="$TEST_DIR/cache/dotfiles/perf-gate.noindex"
  export GIT_CONFIG_GLOBAL=/dev/null
  export XDG_CACHE_HOME="$TEST_DIR/cache"
  export PERF_GATE_BASE=main PERF_GATE_RUNS=3 PERF_GATE_WARMUPS=0 PERF_GATE_HEAVY_RUN=0
  unset HEAVY_RUN_SLOT PERF_GATE_NO_BASE
  git init -q -b main "$FIX"
  mkdir -p "$FIX/config"
  tool 0.10
  budget 'tool	2000	./tool.sh'
  commit base
  git -C "$FIX" checkout -q -b work
}

teardown() {
  [ -z "${HOLDER:-}" ] || kill "$HOLDER" 2>/dev/null || true
  rm -rf "$TEST_DIR"
}

# tool <seconds> [file]: write a tracked script that sleeps that long.
tool() {
  printf '#!/bin/bash\nsleep %s\n' "$1" > "$FIX/${2:-tool.sh}"
  chmod +x "$FIX/${2:-tool.sh}"
}

# quicker [seconds]: a runtime change that cannot look slower: the tool now
# sleeps less than at the base (50 ms against 100 ms by default).
quicker() { tool "${1:-0.05}"; }

# budget <line>...: write the fixture budget file: the path list, then these lines.
budget() {
  {
    printf 'PERF_GATE_PATH=tool.sh\nPERF_GATE_PATH=new.sh\nPERF_GATE_PATH=lib.sh\nPERF_GATE_PATH=config/perf-budget.tsv\n'
    printf '%s\n' "$@"
  } > "$FIX/config/perf-budget.tsv"
}

commit() {
  git -C "$FIX" add -A
  git -C "$FIX" -c user.name=t -c user.email=t@example.com commit -q --no-verify -m "$1"
}

# merge: the work so far becomes the new base.
merge() {
  commit "$1"
  git -C "$FIX" branch -q -f main work
}

# bats prints this output only when the test fails: it shows why a gate run went wrong.
gate() {
  run bash -c 'cd "$1" && shift && "$@"' _ "$FIX" "$GATE" "$@"
  printf 'gate %s -> status %s\n%s\n' "$*" "$status" "$output"
}

# ── Verdicts ─────────────────────────────────────────────────────────

@test "perf gate fails on a seeded slowdown and names the command" {
  tool 0.20
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool got slower"* ]]
  [[ "$output" == *"perf gate: FAIL"* ]]
  [[ "$output" == *"Make the command faster"* ]]
  [[ "$output" == *"PERF_GATE_ALLOW=<name>:<reason>"* ]]
}

@test "perf gate sees a committed slowdown too" {
  tool 0.20
  commit slower
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool got slower"* ]]
}

@test "perf gate passes when the trees are equally fast" {
  tool 0.40
  merge "slow base"
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

@test "a command that fails in this tree is a setup error" {
  printf '#!/bin/bash\nexit 3\n' > "$FIX/tool.sh"
  gate
  [ "$status" -eq 2 ]
  [[ "$output" == *"tool failed in this tree (status 3)"* ]]
  [[ "$output" != *"perf gate: pass"* ]]
}

@test "a command that a signal kills is reported with the signal" {
  printf '#!/bin/bash\nkill -TERM $$\n' > "$FIX/tool.sh"
  gate
  [ "$status" -eq 2 ]
  [[ "$output" == *"tool failed in this tree (signal 15)"* ]]
}

@test "the limits are 10% and 3 ms: a 20% step fails" {
  # 500 ms -> 600 ms. A limit of 20% or more would pass this; so would a
  # floor of 100 ms or more.
  tool 0.50
  merge "slow base"
  tool 0.60
  run bash -c 'cd "$1" && "$2" --json 2>/dev/null' _ "$FIX" "$GATE"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.limit_ratio == 1.10 and .limit_ms == 3
    and (.commands[0] | .verdict == "slower" and .ratio > 1.10 and .ratio < 1.25)'
  grep -qF 'my ($RATIO, $FLOOR_MS) = (1.10, 3);' "$TIMER"
}

@test "perf gate --json prints base_min, head_min, ratio, and verdict per command" {
  tool 0.20
  run bash -c 'cd "$1" && "$2" --json 2>/dev/null' _ "$FIX" "$GATE"
  [ "$status" -eq 1 ]
  echo "$output" | jq -e '.skipped == false and .ok == false and (.base | length == 40)
    and .base_ref == "main" and (.base_ref_date | test("^20[0-9-]+$"))
    and .limit_ratio == 1.10 and .limit_ms == 3
    and (.commands | length == 1)
    and (.commands[0] | .name == "tool" and .verdict == "slower" and .base_min >= 100
      and .head_min >= 200 and .ratio > 1.1 and .ceiling_ms == 2000)'

  git -C "$FIX" checkout -q tool.sh
  echo docs > "$FIX/README.md"
  run bash -c 'cd "$1" && "$2" --json 2>/dev/null' _ "$FIX" "$GATE"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.skipped == true and .reason == "no runtime change"'
}

# ── The base side never passes silently ──────────────────────────────

@test "a command that is missing at the base commit gets the ceiling check only" {
  quicker
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

@test "a row that points an existing name at another file is still compared with the base row" {
  # The base budget has "tool". The head row names a file the base does not
  # have, so the old rule called it "new" and checked the ceiling only.
  tool 0.20 new.sh
  budget 'tool	2000	./new.sh'
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool got slower"* ]]
  [[ "$output" == *"the base runs its own row (./tool.sh)"* ]]
  [[ "$output" != *" new"$'\n'* ]]
}

@test "a wrapper in front of an existing command is still compared with the base row" {
  tool 0.20
  budget 'tool	2000	/usr/bin/env ./tool.sh'
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool got slower"* ]]
}

@test "a command that the base has but that fails there is a setup error, not a new command" {
  printf '#!/bin/bash\nexit 1\n' > "$FIX/tool.sh"
  merge "broken base"
  tool 0.10
  gate
  [ "$status" -eq 2 ]
  [[ "$output" == *"tool failed in the base checkout (status 1)"* ]]
  [[ "$output" != *"perf gate: pass"* ]]
}

@test "a base file that lost its execute bit is a setup error, not a new command" {
  chmod -x "$FIX/tool.sh"
  merge "no x bit at base"
  chmod +x "$FIX/tool.sh"
  gate
  [ "$status" -eq 2 ]
  [[ "$output" == *"tool failed in the base checkout"* ]]
}

@test "no base commit is a setup error unless PERF_GATE_NO_BASE=1" {
  tool 0.20
  PERF_GATE_BASE=origin/nowhere gate
  [ "$status" -eq 2 ]
  [[ "$output" == *"no base commit"* ]]

  PERF_GATE_BASE=origin/nowhere PERF_GATE_NO_BASE=1 gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"only the ceilings apply"* ]]
  [[ "$output" =~ tool[[:space:]]+base[[:space:]]+-.*new ]]
}

@test "perf gate prints the base ref, its date, and the merge-base" {
  quicker
  gate
  [ "$status" -eq 0 ]
  [[ "$output" =~ perf\ gate:\ base\ ref\ main\ \(last\ commit\ 20[0-9]{2}-[0-9]{2}-[0-9]{2}\),\ merge-base\ [0-9a-f]{12} ]]
}

# ── The base checkout ────────────────────────────────────────────────

@test "a base checkout whose folder is gone is built again" {
  local sha
  sha="$(git -C "$FIX" rev-parse main)"
  quicker
  gate
  [ "$status" -eq 0 ]
  rm -rf "$CACHE/$sha"          # git still lists the worktree; the .use file stays
  [ -e "$CACHE/$sha.use" ]
  tool 0.20
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool got slower"* ]]
  [ -x "$CACHE/$sha/tool.sh" ]
}

@test "a base checkout at another commit is built again, not trusted" {
  local sha
  sha="$(git -C "$FIX" rev-parse main)"
  quicker
  gate
  [ "$status" -eq 0 ]
  # Someone moves the cached checkout to a commit where the tool is slow.
  tool 0.20
  commit slow
  git -C "$CACHE/$sha" checkout -q --detach "$(git -C "$FIX" rev-parse HEAD)"
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool got slower"* ]]
  [ "$(git -C "$CACHE/$sha" rev-parse HEAD)" = "$sha" ]
}

@test "a base checkout with an edited or added file is built again, not trusted" {
  local sha
  sha="$(git -C "$FIX" rev-parse main)"
  quicker
  gate
  [ "$status" -eq 0 ]
  # Someone slows the tool inside the cached checkout, so a slow head looks equal.
  printf '#!/bin/bash\nsleep 0.20\n' > "$CACHE/$sha/tool.sh"
  tool 0.20
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a clean copy of the base commit"* ]]
  [[ "$output" == *"tool got slower"* ]]

  echo planted > "$CACHE/$sha/extra.sh"
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a clean copy of the base commit"* ]]
  [ ! -e "$CACHE/$sha/extra.sh" ]
}

@test "an ignored file in the base checkout also makes it be built again" {
  local sha
  echo '*.cache' > "$FIX/.gitignore"
  merge "ignore rule"
  sha="$(git -C "$FIX" rev-parse main)"
  quicker
  gate
  [ "$status" -eq 0 ]
  [[ "$output" != *"not a clean copy"* ]]
  mkdir "$CACHE/$sha/deep"
  echo planted > "$CACHE/$sha/deep/x.cache"
  gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"not a clean copy of the base commit"* ]]
  [ ! -e "$CACHE/$sha/deep" ]
}

@test "a symlink at the base checkout path is unlinked, and its target is not touched" {
  local sha
  sha="$(git -C "$FIX" rev-parse main)"
  # A real worktree of someone else, at another commit than the base.
  tool 0.20
  commit other
  git -C "$FIX" worktree add -q --detach "$TEST_DIR/real" HEAD
  echo "their work" > "$TEST_DIR/real/notes.txt"
  mkdir -p "$CACHE"
  ln -s "$TEST_DIR/real" "$CACHE/$sha"
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool got slower"* ]]
  [ ! -L "$CACHE/$sha" ] && [ -x "$CACHE/$sha/tool.sh" ]
  [ "$(cat "$TEST_DIR/real/notes.txt")" = "their work" ]
  git -C "$FIX" worktree list | grep -qF "$TEST_DIR/real"
}

@test "a folder at the base checkout path that the gate did not build is a setup error" {
  local sha
  sha="$(git -C "$FIX" rev-parse main)"
  mkdir -p "$CACHE/$sha"
  echo keep > "$CACHE/$sha/mine.txt"
  tool 0.20
  gate
  [ "$status" -eq 2 ]
  [[ "$output" == *"$CACHE/$sha is not a clean base checkout, and the gate did not build it"* ]]
  [ "$(cat "$CACHE/$sha/mine.txt")" = keep ]
}

@test "the prune leaves an old folder alone when the gate did not build it" {
  local a=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa b=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  mkdir -p "$CACHE/$a" "$CACHE/$b"
  echo keep > "$CACHE/$a/mine.txt"
  touch -t 202001010000 "$CACHE/$a"
  quicker
  gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"left $CACHE/$a alone"* ]]
  [ "$(cat "$CACHE/$a/mine.txt")" = keep ]
}

@test "a cache path with a space still prunes old checkouts" {
  export XDG_CACHE_HOME="$TEST_DIR/my cache"
  local spaced="$XDG_CACHE_HOME/dotfiles/perf-gate.noindex" first
  first="$(git -C "$FIX" rev-parse main)"
  for n in 1 2 3; do
    quicker "0.0$((10 - 3 * n))"    # 70, 40, 10 ms: each step is quicker than its base
    gate
    [ "$status" -eq 0 ]
    merge "step $n"
    sleep 1
  done
  [ ! -e "$spaced/$first" ]
  [ "$(find "$spaced" -maxdepth 1 -type d -name '[0-9a-f]*' | wc -l | tr -d ' ')" = 2 ]
}

@test "the base checkout is cached by commit, two are kept, and one in use is not removed" {
  local first second third
  # Four steps follow, each quicker than its base: 250 -> 190 -> 130 -> 70 -> 10 ms.
  tool 0.25
  merge "slow base"
  first="$(git -C "$FIX" rev-parse main)"
  quicker 0.19
  gate
  [ "$status" -eq 0 ]
  [ -x "$CACHE/$first/tool.sh" ]

  # Another gate still times in the first checkout: it holds the shared lock.
  /usr/bin/perl -e 'use Fcntl qw(:flock); open(my $f, ">>", $ARGV[0]) or die; flock($f, LOCK_SH); print "held\n"; sleep 60' \
    "$CACHE/$first.use" > "$TEST_DIR/holder.out" &
  HOLDER=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TEST_DIR/holder.out" ] && break; sleep 0.2; done

  for n in 2 3; do
    merge "step $n"
    if [ "$n" = 2 ]; then quicker 0.13; else quicker 0.07; fi
    sleep 1
    gate
    [ "$status" -eq 0 ]
    [ "$n" = 2 ] && second="$(git -C "$FIX" rev-parse main)"
  done
  third="$(git -C "$FIX" rev-parse main)"
  [ -d "$CACHE/$first" ]        # in use: kept
  [ -d "$CACHE/$second" ] && [ -d "$CACHE/$third" ]

  kill "$HOLDER"; wait "$HOLDER" 2>/dev/null || true; HOLDER=""
  merge "step 4"
  quicker 0.01
  sleep 1
  gate
  [ "$status" -eq 0 ]
  [ ! -e "$CACHE/$first" ] && [ ! -e "$CACHE/$first.use" ]
  [ ! -e "$CACHE/$second" ]
  [ -d "$CACHE/$third" ] && [ -d "$CACHE/$(git -C "$FIX" rev-parse main)" ]
}

@test "perf gate never prunes worktrees that are not its own" {
  git -C "$FIX" worktree add -q --detach "$TEST_DIR/other" main
  rm -rf "$TEST_DIR/other"      # a stale entry that `git worktree prune` would drop
  quicker
  gate
  [ "$status" -eq 0 ]
  git -C "$FIX" worktree list | grep -qF "$TEST_DIR/other"
}

# ── Scope ────────────────────────────────────────────────────────────

@test "perf gate skips a diff with no runtime change" {
  echo docs > "$FIX/README.md"
  mkdir -p "$FIX/tests" && echo t > "$FIX/tests/x.bats"
  gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"perf gate: skipped (no runtime change)" ]]
  [ ! -e "$CACHE" ]
}

@test "a git failure in the scope check is a setup error, not a skip" {
  echo docs > "$FIX/README.md"
  mkdir -p "$TEST_DIR/bin"
  printf '#!/bin/bash\nfor a in "$@"; do [ "$a" = "%s" ] && exit 128; done\nexec "%s" "$@"\n' diff "$(command -v git)" > "$TEST_DIR/bin/git"
  chmod +x "$TEST_DIR/bin/git"
  run bash -c 'cd "$1" && PATH="$3:$PATH" "$2"' _ "$FIX" "$GATE" "$TEST_DIR/bin"
  [ "$status" -eq 2 ]
  [[ "$output" == *"git diff against"*"failed"* ]]
  [[ "$output" != *"skipped"* ]]

  printf '#!/bin/bash\nfor a in "$@"; do [ "$a" = "%s" ] && exit 128; done\nexec "%s" "$@"\n' ls-files "$(command -v git)" > "$TEST_DIR/bin/git"
  run bash -c 'cd "$1" && PATH="$3:$PATH" "$2"' _ "$FIX" "$GATE" "$TEST_DIR/bin"
  [ "$status" -eq 2 ]
  [[ "$output" == *"git ls-files failed"* ]]
}

@test "perf gate --force times the commands with no runtime change" {
  tool 0.40
  merge "slow base"
  gate --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"perf gate: pass"* ]]
}

@test "a budget file with no path line or no command is a setup error" {
  tool 0.20
  printf 'tool\t2000\t./tool.sh\n' > "$FIX/config/perf-budget.tsv"
  gate
  [ "$status" -eq 2 ]
  [[ "$output" == *"has no PERF_GATE_PATH line"* ]]

  printf 'PERF_GATE_PATH=tool.sh\n# no rows\n' > "$FIX/config/perf-budget.tsv"
  gate
  [ "$status" -eq 2 ]
  [[ "$output" == *"lists no command"* ]]
}

@test "a PR cannot switch the gate off by removing a path from its own list" {
  # The budget file and tool.sh leave the head list; the base list still has them.
  tool 0.20
  printf 'PERF_GATE_PATH=elsewhere/\ntool\t2000\t./tool.sh\n' > "$FIX/config/perf-budget.tsv"
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool got slower"* ]]
}

@test "a file moved out of a runtime path still counts as a runtime change" {
  printf '# shared code, long enough for git to see the move as a rename\n# line 2\n# line 3\n' > "$FIX/lib.sh"
  tool 0.40
  merge "add lib"
  mkdir -p "$FIX/docs"
  git -C "$FIX" mv lib.sh docs/lib.sh
  gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"perf gate: pass"* ]]
}

@test "a command row removed from the budget fails without an allow line" {
  tool 0.40
  tool 0.10 new.sh
  budget 'tool	2000	./tool.sh' 'second	2000	./new.sh'
  merge "two commands"
  budget 'tool	2000	./tool.sh'
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"second is in the base budget file but not in this one"* ]]

  budget 'tool	2000	./tool.sh' 'PERF_GATE_ALLOW=second:the command is gone'
  gate
  [ "$status" -eq 0 ]
}

# ── Allow lines ──────────────────────────────────────────────────────

@test "an allow line passes an intended slowdown, for one PR only" {
  tool 0.20
  budget 'tool	2000	./tool.sh' 'PERF_GATE_ALLOW=tool:does more work on purpose'
  gate
  [ "$status" -eq 0 ]
  [[ "$output" =~ tool.*allowed ]]

  # After the merge the base has the same line: it is stale. The gate says
  # which line to remove, before any timing and without the generic advice.
  merge allow
  tool 0.40
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"remove this line from config/perf-budget.tsv: PERF_GATE_ALLOW=tool:does more work on purpose"* ]]
  [[ "$output" != *"Make the command faster"* ]]
  [[ "$output" != *" ms "* ]]
  [[ "$output" != *"perf gate: FAIL"* ]]

  # A line counts again when its reason is this PR's own: name plus reason differ from the base.
  budget 'tool	2000	./tool.sh' 'PERF_GATE_ALLOW=tool:slower again, for the new index'
  gate
  [ "$status" -eq 0 ]
  [[ "$output" =~ tool.*allowed ]]
}

@test "an allow line does not lift the ceiling" {
  tool 0.20
  budget 'tool	50	./tool.sh' 'PERF_GATE_ALLOW=tool:on purpose'
  gate
  [ "$status" -eq 1 ]
  [[ "$output" == *"tool is over its ceiling"* ]]
}

@test "an allow line that names an unknown command is a setup error" {
  tool 0.20
  budget 'tool	2000	./tool.sh' 'PERF_GATE_ALLOW=tol:typo'
  gate
  [ "$status" -eq 2 ]
  [[ "$output" == *"PERF_GATE_ALLOW=tol names no command"* ]]
}

@test "a bad budget line is a setup error" {
  budget 'tool	fast	./tool.sh'
  gate
  [ "$status" -eq 2 ]
  [[ "$output" == *"bad line"* ]]
}

# ── A change to the gate itself ──────────────────────────────────────

@test "a PR that changes the gate's own files needs a new perf-gate allow line" {
  mkdir -p "$FIX/scripts"
  echo v1 > "$FIX/scripts/perf-gate.sh"
  echo v1 > "$FIX/scripts/perf-gate.pl"
  tool 0.40
  # The fixture path list does not name scripts/: the gate files count anyway.
  merge "gate files at the base"
  echo v2 > "$FIX/scripts/perf-gate.pl"
  gate
  [ "$status" -eq 2 ]
  [[ "$output" == *"WARNING: this change edits the gate itself (scripts/perf-gate.pl)"* ]]
  [[ "$output" == *"Add PERF_GATE_ALLOW=perf-gate:<reason>"* ]]
  [[ "$output" != *"perf gate: pass"* ]]

  budget 'tool	2000	./tool.sh' 'PERF_GATE_ALLOW=perf-gate:fix a review finding'
  gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING: this change edits the gate itself"* ]]
  [[ "$output" == *"allowed by PERF_GATE_ALLOW=perf-gate: fix a review finding"* ]]

  # After the merge the base has the same line: it does not cover the next change.
  merge "gate change"
  echo v3 > "$FIX/scripts/perf-gate.sh"
  gate
  [ "$status" -eq 2 ]
  [[ "$output" == *"scripts/perf-gate.sh differ from the base"* ]]
  [[ "$output" == *"write this PR's own reason"* ]]

  # Two gate PRs in a row: the second passes with its own reason on the line.
  budget 'tool	2000	./tool.sh' 'PERF_GATE_ALLOW=perf-gate:second review round'
  gate
  [ "$status" -eq 0 ]
  [[ "$output" == *"allowed by PERF_GATE_ALLOW=perf-gate: second review round"* ]]

  # The gate's test file counts as the gate too.
  merge "second gate change"
  budget 'tool	2000	./tool.sh'
  mkdir -p "$FIX/tests"
  echo t1 > "$FIX/tests/perf-gate.bats"
  merge "gate tests at the base"
  echo t2 > "$FIX/tests/perf-gate.bats"
  gate
  [ "$status" -eq 2 ]
  [[ "$output" == *"edits the gate itself (tests/perf-gate.bats)"* ]]
}

@test "the command name perf-gate is reserved" {
  budget 'perf-gate	2000	./tool.sh'
  gate
  [ "$status" -eq 2 ]
  [[ "$output" == *"the name perf-gate is reserved"* ]]
}

# ── Setup errors exit 2 ──────────────────────────────────────────────

@test "a bad PERF_GATE_RUNS or PERF_GATE_WARMUPS is a setup error" {
  local bad
  for bad in 0 abc -1 1.5; do
    PERF_GATE_RUNS="$bad" gate
    [ "$status" -eq 2 ]
    [[ "$output" == *"PERF_GATE_RUNS must be a number above 0"* ]]
  done
  PERF_GATE_WARMUPS=x gate
  [ "$status" -eq 2 ]
  [[ "$output" == *"PERF_GATE_WARMUPS must be a number"* ]]
}

@test "an unknown argument is a setup error" {
  gate --fast
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown argument --fast"* ]]
}

@test "outside a git repository is a setup error" {
  mkdir "$TEST_DIR/plain"
  run bash -c 'cd "$1" && GIT_CEILING_DIRECTORIES="$1" "$2"' _ "$TEST_DIR/plain" "$GATE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not in a git repository"* ]]
}

@test "a cache folder that cannot be written is a setup error" {
  tool 0.20
  mkdir -p "$TEST_DIR/ro"
  chmod 555 "$TEST_DIR/ro"
  XDG_CACHE_HOME="$TEST_DIR/ro" gate
  chmod 755 "$TEST_DIR/ro"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot create or write the cache folder"* ]]
}

@test "no HOME and no XDG_CACHE_HOME, or a relative cache path, is a setup error" {
  tool 0.20
  run bash -c 'cd "$1" && env -u HOME -u XDG_CACHE_HOME "$2"' _ "$FIX" "$GATE"
  [ "$status" -eq 2 ]
  [[ "$output" == *"HOME and XDG_CACHE_HOME are both unset"* ]]

  XDG_CACHE_HOME=relative/cache gate
  [ "$status" -eq 2 ]
  [[ "$output" == *"must be an absolute path"* ]]
  [ ! -e "$FIX/relative" ]
}

@test "a missing perl is a setup error" {
  tool 0.20
  PERF_GATE_PERL="$TEST_DIR/no-perl" gate
  [ "$status" -eq 2 ]
  [[ "$output" == *"perl not found"* ]]
}

# ── How the commands run ─────────────────────────────────────────────

@test "the commands run with a scratch HOME and without the caller's environment" {
  printf '#!/bin/bash\nsleep 0.30\n[ -z "${BASH_ENV:-}" ] && [ -z "${SECRET_THING:-}" ] && [ "$DO_NOT_TRACK" = 1 ] && [ "$HOME" != "%s" ]\n' "$HOME" > "$FIX/tool.sh"
  merge "env probe"
  printf '# a comment\n' >> "$FIX/tool.sh"
  run bash -c 'cd "$1" && BASH_ENV=/nonexistent SECRET_THING=x "$2"' _ "$FIX" "$GATE"
  [ "$status" -eq 0 ]
}

@test "timing goes through heavy-run --exclusive with a readable command, but not inside a slot" {
  mkdir -p "$TEST_DIR/bin"
  printf '#!/bin/bash\necho "$*" >> "%s/heavy-run.calls"\nshift\nexec "$@"\n' "$TEST_DIR" > "$TEST_DIR/bin/heavy-run"
  chmod +x "$TEST_DIR/bin/heavy-run"
  quicker

  run bash -c 'cd "$1" && PATH="$3:$PATH" PERF_GATE_HEAVY_RUN=1 "$2"' _ "$FIX" "$GATE" "$TEST_DIR/bin"
  [ "$status" -eq 0 ]
  [[ "$output" == *"waiting for an exclusive heavy-run slot"* ]]
  [[ "$(cat "$TEST_DIR/heavy-run.calls")" == "--exclusive /usr/bin/perl "*"/scripts/perf-gate.pl "* ]]
  [ "$(wc -c < "$TEST_DIR/heavy-run.calls" | tr -d ' ')" -lt 600 ]

  run bash -c 'cd "$1" && PATH="$3:$PATH" PERF_GATE_HEAVY_RUN=1 HEAVY_RUN_SLOT=1 "$2"' _ "$FIX" "$GATE" "$TEST_DIR/bin"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already inside a heavy-run slot"* ]]
  [ "$(wc -l < "$TEST_DIR/heavy-run.calls" | tr -d ' ')" = 1 ]
}

# ── This repo's own setup ────────────────────────────────────────────

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
  for path in bin/ lib/ agent-hooks/ config/ scripts/perf-gate.sh scripts/perf-gate.pl; do
    grep -qx "PERF_GATE_PATH=$path" "$BUDGET" || { echo "missing path: $path"; return 1; }
  done
}

@test "make check runs the perf gate as a timed step, and make perf-gate exists" {
  grep -qE 'gate-timed.sh perf-gate .*perf-gate$' "$REPO_ROOT/Makefile"
  grep -qE '^perf-gate: ## ' "$REPO_ROOT/Makefile"
  # The recipe is the bare script: no env knob, no flag, no "|| true".
  [ "$(awk '/^perf-gate:/ { on = 1; next } on && /^\t/ { print; next } on { exit }' "$REPO_ROOT/Makefile")" \
    = "$(printf '\t@echo "═══ Performance gate ═══"\n\t@scripts/perf-gate.sh')" ]
  grep -qxF "$(printf '\t@scripts/gate-timed.sh perf-gate $(MAKE) --no-print-directory perf-gate')" "$REPO_ROOT/Makefile"
  head -1 "$GATE" | grep -qx '#!/bin/bash'
  head -1 "$TIMER" | grep -qx '#!/usr/bin/perl'
  /usr/bin/perl -c "$TIMER"
}

@test "the base checkout cache is a .noindex folder, so Spotlight skips it" {
  grep -qF 'dotfiles/perf-gate.noindex' "$GATE"
}
