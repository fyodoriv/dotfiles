#!/usr/bin/env bats
# Every dotfiles action runs through the CLI and agents, from one source
# (task action-parity; rule "Every action through CLI, agent, and UI").
#
# `dotfiles actions --json` is generated from bin/dotfiles itself: the
# dispatch `case` arms give the names, the show_help text gives the usage and
# what each one does, and `# terminal-only:` / `# confirm:` / `# agent:`
# comments in an arm give the notes. dotfiles has no UI (no web app or
# window), so parity here is CLI and agents; a UI would read the same list.
# These tests fail when a dispatched command misses the agent catalog or its
# help line, or a help line names no command.

load test_helper
bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
CLI="$REPO_ROOT/bin/dotfiles"

setup() {
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# The dispatch arm names, read with a plain grep (not the generator's parser):
# two-space `name)` or `a|b)` lines between `case "$cmd" in` and `esac`, after
# the update-check `case`. The first name of an arm is the action; `""` is start.
dispatch_names() {
  awk '/^case "\$cmd" in$/ { n++; next } n == 2 && /^esac$/ { exit } n == 2 && /^  [^ *][^ ]*\)/ { print }' "$1" |
    sed -E 's/^  ([^)]*)\).*/\1/; s/^""\|//; s/\|.*//'
}

# A copy of the repo parts the generator reads, to change without touching the repo.
copy_cli() {
  mkdir -p "$TEST_DIR/repo/bin" "$TEST_DIR/repo/lib"
  cp "$REPO_ROOT/bin/dotfiles" "$REPO_ROOT/bin/dotfiles-actions" "$TEST_DIR/repo/bin/"
  cp "$REPO_ROOT/lib/colors.sh" "$TEST_DIR/repo/lib/"
}

@test "every dispatched command is an action in dotfiles actions --json, nothing missing, nothing extra" {
  run bash "$CLI" actions --json
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  local want got
  want="$(dispatch_names "$CLI" | LC_ALL=C sort)"
  got="$(printf '%s' "$output" | jq -r '.[].name' | LC_ALL=C sort)"
  [ "$want" = "$got" ] || { diff <(echo "$want") <(echo "$got"); return 1; }
  [ "$(printf '%s\n' "$want" | wc -l | tr -d ' ')" -ge 36 ]
}

@test "the parity check passes: each command has a help line and an agent path or a terminal-only reason" {
  run bash "$CLI" actions --check
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"✓ "*" actions: every dispatched command has a help line"* ]]
  run bash "$CLI" actions --json
  printf '%s' "$output" | jq -e 'all(.[]; (.forms | length) > 0 and (.help | length) > 0)'
  printf '%s' "$output" | jq -e 'all(.[]; .agent or ((.terminal_only // "") | length) > 0)'
  printf '%s' "$output" | jq -e 'all(.[]; .agent == (.terminal_only == null))'
}

@test "a new command without a help line fails the parity check and still reaches agents" {
  copy_cli
  awk '{ print } /^  memory\)$/ && !done { print "    exit 0\n    ;;\n\n  frobnicate)"; done = 1 }' \
    "$REPO_ROOT/bin/dotfiles" > "$TEST_DIR/repo/bin/dotfiles"
  run bash "$TEST_DIR/repo/bin/dotfiles" actions --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"frobnicate"*"no line in show_help"* ]] || { echo "$output"; return 1; }
  run --separate-stderr bash "$TEST_DIR/repo/bin/dotfiles" actions --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e 'any(.[]; .name == "frobnicate" and .forms == [])'
  [[ "$stderr" == *"frobnicate"*"dotfiles actions --check"* ]]
}

@test "a help line for a command that is not dispatched fails the parity check" {
  copy_cli
  awk '{ print } /^Advanced:$/ { print "  vanish                       Was removed long ago" }' \
    "$REPO_ROOT/bin/dotfiles" > "$TEST_DIR/repo/bin/dotfiles"
  run bash "$TEST_DIR/repo/bin/dotfiles" actions --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"vanish"*"not dispatched"* ]] || { echo "$output"; return 1; }
}

@test "each action has a name, a command, forms with usage and arguments, and notes" {
  run bash "$CLI" actions --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e 'all(.[]; has("name") and has("aliases") and has("command") and has("help") and has("forms") and has("agent") and has("terminal_only") and has("confirm") and has("agent_note"))'
  # Arguments come from the usage text.
  printf '%s' "$output" | jq -e '.[] | select(.name == "apply") | .forms[0] | .usage == "dotfiles apply [--pull] [--no-fix] [--if-changed]" and ([.args[].flag] == ["--pull", "--no-fix", "--if-changed"]) and all(.args[]; .required == false and .kind == "flag")'
  printf '%s' "$output" | jq -e '.[] | select(.name == "add") | .forms[0].args[0] == {"kind": "positional", "name": "file", "flag": null, "value": null, "choices": null, "required": true}'
  printf '%s' "$output" | jq -e '.[] | select(.name == "metrics") | .forms[0].args | any(.flag == "--share" and .value == "FILE" and .kind == "option")'
  printf '%s' "$output" | jq -e '.[] | select(.name == "profile") | .forms[0].args[0] | .kind == "choice" and .choices == ["core", "full"] and .required == false'
  printf '%s' "$output" | jq -e '.[] | select(.name == "config") | [.forms[].usage] == ["dotfiles config [<key>]", "dotfiles config set <key> <value>"]'
  printf '%s' "$output" | jq -e '.[] | select(.name == "config") | .forms[1].args[0] == {"kind": "word", "name": "set", "flag": null, "value": null, "choices": null, "required": true}'
  # Aliases come from the arm labels; the bare command is start.
  printf '%s' "$output" | jq -e '.[] | select(.name == "start") | .aliases == [""] and .forms[0].usage == "dotfiles [--yes] [--health]"'
  printf '%s' "$output" | jq -e '.[] | select(.name == "help") | .aliases == ["h"] and .forms[0].usage == "dotfiles --help"'
}

@test "terminal-only and confirm notes mark what agents must not run or must ask about" {
  run bash "$CLI" actions --json
  [ "$status" -eq 0 ]
  local name
  for name in edit quickstart leak; do
    printf '%s' "$output" | jq -e --arg n "$name" '.[] | select(.name == $n) | .agent == false and (.terminal_only | length) > 0' ||
      { echo "$name should be terminal-only"; return 1; }
  done
  for name in apply init update upgrade sync install uninstall contribute plugin; do
    printf '%s' "$output" | jq -e --arg n "$name" '.[] | select(.name == $n) | .agent and (.confirm | length) > 0' ||
      { echo "$name should need a confirm"; return 1; }
  done
  # Read-only commands run without a confirm.
  for name in help version actions status diff managed doctor audit validate metrics; do
    printf '%s' "$output" | jq -e --arg n "$name" '.[] | select(.name == $n) | .agent and .confirm == null' ||
      { echo "$name should run without a confirm"; return 1; }
  done
  # Prompting commands take --yes in the CLI.
  printf '%s' "$output" | jq -e '.[] | select(.name == "uninstall") | .forms[0].args | any(.flag == "--yes")'
  printf '%s' "$output" | jq -e '.[] | select(.name == "start") | .forms[0].args | any(.flag == "--yes")'
}

@test "dotfiles actions prints one line per usage form, the notes, and how agents get the JSON" {
  run bash "$CLI" actions
  [ "$status" -eq 0 ]
  [[ "$output" == *"dotfiles apply [--pull] [--no-fix] [--if-changed]  - Apply dotfiles and self-heal"*"[confirm: "* ]]
  [[ "$output" == *"dotfiles edit  - Open the dotfiles repo in your editor  [terminal only: "* ]]
  [[ "$output" == *"dotfiles config set <key> <value>  - Check a value"* ]]
  [[ "$output" == *"action(s) from bin/dotfiles; agents: dotfiles actions --json"* ]]
  run bash "$CLI" actions config
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^dotfiles config')" -eq 2 ]
  [[ "$output" == *"1 action(s)"* ]]
  run bash "$CLI" actions h --json
  [ "$(printf '%s' "$output" | jq -r '.[].name')" = "help" ]
  run bash "$CLI" actions nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"no action named nope"* ]]
}

@test "dotfiles actions reads only the source: no update check, no git" {
  mkdir -p "$TEST_DIR/bin"
  printf '#!/bin/bash\necho "git $*" >> "%s/calls.log"\nexit 1\n' "$TEST_DIR" > "$TEST_DIR/bin/git"
  chmod +x "$TEST_DIR/bin/git"
  PATH="$TEST_DIR/bin:$PATH" run bash "$CLI" actions --json
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_DIR/calls.log" ] || { cat "$TEST_DIR/calls.log"; return 1; }
}

@test "the /dotfiles agent command points agents at dotfiles actions --json" {
  local f="$REPO_ROOT/commands/dotfiles.md"
  grep -q 'dotfiles actions --json' "$f"
  grep -q 'terminal_only' "$f"
  grep -q 'confirm' "$f"
}
