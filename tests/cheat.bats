#!/usr/bin/env bats
# Tests for bin/cheat — quick cheatsheet reference

load test_helper

CHEAT_CMD="$BATS_TEST_DIRNAME/../bin/cheat"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

# The first usage line of each action in `dotfiles actions --json` (its bare
# command when it has no help line), as "name<TAB>usage". The dotfiles
# section of cheat must have a row for each one.
action_usages() {
  bash "$1/bin/dotfiles" actions --json 2>/dev/null |
    jq -r '.[] | "\(.name)\t\(.forms[0].usage // .command)"'
}

# The names whose usage ($1, from action_usages) has no row in the cheat
# output $2. A row is the usage at a two-space indent, then: the end of the
# line (a long usage; what it does is on the next line), its aliases after a
# comma (the plain list without jq), or spaces up to the column at 31 where
# what it does starts (cmd's 28-wide usage column).
missing_from_cheat() {
  local name usage
  while IFS=$'\t' read -r name usage; do
    [ -n "$name" ] || continue
    printf '%s\n' "$2" | awk -v u="$usage" '
      function row(line,   n, rest) {
        n = length(u)
        if (substr(line, 1, n + 2) != "  " u) return 0
        rest = substr(line, n + 3)
        if (rest == "" || rest ~ /^,/) return 1
        return n <= 28 && substr(rest, 1, 29 - n) ~ /^ +$/ && substr(rest, 30 - n, 1) != " "
      }
      row($0) { f = 1 }
      END { exit !f }' || echo "$name"
  done <<<"$1"
}

@test "cheat script exists and is executable" {
  [ -f "$CHEAT_CMD" ]
  [ -x "$CHEAT_CMD" ]
}

@test "cheat script has correct shebang" {
  head -1 "$CHEAT_CMD" | grep -q '#!/bin/bash'
}

@test "cheat with no args shows all sections" {
  run bash "$CHEAT_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Shell Commands"* ]]
  [[ "$output" == *"Git Commands"* ]]
  [[ "$output" == *"IdeaVim"* ]]
  [[ "$output" == *"fzf Shortcuts"* ]]
  [[ "$output" == *"Line Editing"* ]]
  [[ "$output" == *"Modern CLI Tools"* ]]
}

@test "cheat shows filter hint at the bottom" {
  run bash "$CHEAT_CMD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Filter: cheat"* ]]
}

@test "cheat git shows only git section" {
  run bash "$CHEAT_CMD" git
  [ "$status" -eq 0 ]
  [[ "$output" == *"Git Commands"* ]]
  [[ "$output" != *"Shell Commands"* ]]
  [[ "$output" != *"IdeaVim"* ]]
}

@test "cheat vim shows only vim section" {
  run bash "$CHEAT_CMD" vim
  [ "$status" -eq 0 ]
  [[ "$output" == *"IdeaVim"* ]]
  [[ "$output" != *"Shell Commands"* ]]
  [[ "$output" != *"Git Commands"* ]]
}

@test "cheat fzf shows only fzf section" {
  run bash "$CHEAT_CMD" fzf
  [ "$status" -eq 0 ]
  [[ "$output" == *"fzf Shortcuts"* ]]
  [[ "$output" != *"Shell Commands"* ]]
}

@test "cheat shell shows only shell section" {
  run bash "$CHEAT_CMD" shell
  [ "$status" -eq 0 ]
  [[ "$output" == *"Shell Commands"* ]]
  [[ "$output" == *"Dotfiles Management"* ]]
  [[ "$output" != *"IdeaVim"* ]]
}

@test "cheat keys shows only keys section" {
  run bash "$CHEAT_CMD" keys
  [ "$status" -eq 0 ]
  [[ "$output" == *"Line Editing"* ]]
  [[ "$output" != *"Shell Commands"* ]]
}

@test "cheat tools shows only tools section" {
  run bash "$CHEAT_CMD" tools
  [ "$status" -eq 0 ]
  [[ "$output" == *"Modern CLI Tools"* ]]
  [[ "$output" != *"Shell Commands"* ]]
}

@test "cheat --help prints usage" {
  run bash "$CHEAT_CMD" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"cheatsheet"* ]] || [[ "$output" == *"cheat"* ]]
}

@test "cheat shell lists key commands" {
  run bash "$CHEAT_CMD" shell
  [ "$status" -eq 0 ]
  [[ "$output" == *"killport"* ]]
  [[ "$output" == *"morning"* ]]
  [[ "$output" == *"cleanup"* ]]
  [[ "$output" == *"dotfiles doctor"* ]]
}

# ── The dotfiles section comes from `dotfiles actions` ────────────────
# cheat runs with NO_COLOR=1: FORCE_COLOR=1 in the environment would wrap
# each usage in color codes and break the row match.

# A copy of the repo parts cheat reads; $1 is an awk program that edits
# bin/dotfiles on the way.
copy_repo() {
  mkdir -p "$TEST_DIR/repo/bin" "$TEST_DIR/repo/lib"
  cp "$REPO_ROOT/bin/cheat" "$REPO_ROOT/bin/dotfiles-actions" "$TEST_DIR/repo/bin/"
  cp "$REPO_ROOT/lib/colors.sh" "$TEST_DIR/repo/lib/"
  awk "$1" "$REPO_ROOT/bin/dotfiles" > "$TEST_DIR/repo/bin/dotfiles"
}

@test "cheat lists every dotfiles action from dotfiles actions --json" {
  local want missing
  want="$(action_usages "$REPO_ROOT")"
  [ "$(printf '%s\n' "$want" | wc -l)" -ge 36 ]
  run env NO_COLOR=1 bash "$CHEAT_CMD"
  [ "$status" -eq 0 ]
  missing="$(missing_from_cheat "$want" "$output")"
  [ -z "$missing" ] || { echo "cheat misses these dotfiles actions:" $missing; return 1; }
  [[ "$output" == *"dotfiles actions <name>"* ]]
  # The generated list, not the plain fallback.
  [[ "$output" != *"a plain list from bin/dotfiles"* ]]
}

@test "a new command in bin/dotfiles shows in cheat with no edit to cheat" {
  copy_repo '/^  help[|]h[)]$/ && !done { print "  frobnicate)\n    exit 0\n    ;;\n"; done = 1 }
    { print }
    /^Advanced:$/ { print "  frobnicate [--twice]         Frob the knobs" }'
  run env NO_COLOR=1 bash "$TEST_DIR/repo/bin/cheat" shell
  [ "$status" -eq 0 ]
  [[ "$output" == *"  dotfiles frobnicate [--twice]"*"Frob the knobs"* ]] || { echo "$output"; return 1; }
  [ -z "$(missing_from_cheat "$(action_usages "$TEST_DIR/repo")" "$output")" ]
}

@test "a help line with no description does not hide the actions after it" {
  local missing
  # jq stopped at the empty help, and every later action was gone.
  copy_repo '/^  diff  / { print "  diff"; next } { print }'
  action_usages "$TEST_DIR/repo" | grep -qx $'diff\tdotfiles diff'
  run env NO_COLOR=1 bash "$TEST_DIR/repo/bin/cheat" shell
  [ "$status" -eq 0 ]
  missing="$(missing_from_cheat "$(action_usages "$TEST_DIR/repo")" "$output")"
  [ -z "$missing" ] || { echo "cheat misses:" $missing; echo "$output"; return 1; }
  [[ "$output" != *"a plain list from bin/dotfiles"* ]]
}

@test "without jq, cheat still lists every dotfiles action, read from bin/dotfiles" {
  local want missing tool bin="$TEST_DIR/no-jq-bin"
  want="$(action_usages "$REPO_ROOT")"
  [ "$(printf '%s\n' "$want" | wc -l)" -ge 36 ]
  mkdir -p "$bin"
  for tool in dirname sed; do ln -s "$(command -v "$tool")" "$bin/$tool"; done
  # The macOS awk when there is one: Homebrew may put gawk first on PATH.
  if [ -x /usr/bin/awk ]; then ln -s /usr/bin/awk "$bin/awk"; else ln -s "$(command -v awk)" "$bin/awk"; fi
  run env PATH="$bin" NO_COLOR=1 "$BASH" "$CHEAT_CMD"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"brew install jq"* ]]
  missing="$(missing_from_cheat "$want" "$output")"
  [ -z "$missing" ] || { echo "cheat without jq misses:" $missing; echo "$output"; return 1; }
  [[ "$output" == *"Git Commands"* ]]
}

@test "without jq, a start-screen help line on one line keeps its usage apart" {
  local bin="$TEST_DIR/no-jq-bin"
  copy_repo '/^  \(no command\) \[--yes\] \[--health\]$/ { print "  (no command)                 Start screen now"; skip = 1; next }
    skip && /^    / { next } { skip = 0; print }'
  mkdir -p "$bin"
  ln -s "$(command -v dirname)" "$bin/dirname"
  if [ -x /usr/bin/awk ]; then ln -s /usr/bin/awk "$bin/awk"; else ln -s "$(command -v awk)" "$bin/awk"; fi
  run env PATH="$bin" NO_COLOR=1 "$BASH" "$TEST_DIR/repo/bin/cheat" shell
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE '^  dotfiles {21}Start screen now$' || { echo "$output"; return 1; }
  [[ "$output" != *"dotfiles Start screen"* ]]
}
