#!/usr/bin/env bats
# Pin the help-text contract shared by the four scaffolding commands the
# `Add and Maintain Config` user-story documents:
#
#   • bin/dotfiles-add          — config file (symlink or copy)
#   • bin/dotfiles-brew-add     — Homebrew package
#   • bin/dotfiles-defaults-add — macOS default + doctor check
#   • bin/dotfiles-new-module   — new doctor module
#
# Each command must:
#   1. exit 0 on `--help` and `-h`
#   2. print a one-line purpose followed by a `Usage:` line
#   3. document the flag set the user-story example uses, so renaming a
#      flag in code requires updating both the help text and the doc.
#
# This is the cheapest insurance that the four scaffolders stay
# discoverable and stay consistent with the public contract in
# docs/user-stories/03-add-and-maintain-config.md.
#
# Closes simplify-dotfiles-add-family-help.

REPO_ROOT="$BATS_TEST_DIRNAME/.."

# Each row: <command> <subcommand-prefix> <pipe-separated-required-flag-tokens>
# The required flag tokens are the flag names that appear in the user-story
# examples and must show up in the `Usage:` line.
#
# Use a plain assignment here (not `declare -a`) — bats wraps each `@test`
# in a function, and `declare` outside any function still flips file-scope
# arrays to local-to-the-loader so the test body sees an empty `FAMILY`.
FAMILY=(
  "dotfiles-add|dotfiles add|--copy|--module"
  "dotfiles-brew-add|dotfiles brew-add|--cask|--full-only|--enterprise"
  "dotfiles-defaults-add|dotfiles defaults-add|--module|--script|--section"
  "dotfiles-new-module|dotfiles new-module|--severity"
)

_help_for() {
  "$REPO_ROOT/bin/$1" --help
}

@test "scaffolding family: all four commands ship a --help that exits 0" {
  local row cmd
  for row in "${FAMILY[@]}"; do
    IFS='|' read -r cmd _rest <<< "$row"
    run _help_for "$cmd"
    [ "$status" -eq 0 ] || {
      echo "$cmd --help exited $status (expected 0)"
      echo "$output"
      return 1
    }
  done
}

@test "scaffolding family: -h is an alias for --help" {
  local row cmd
  for row in "${FAMILY[@]}"; do
    IFS='|' read -r cmd _rest <<< "$row"
    run "$REPO_ROOT/bin/$cmd" -h
    [ "$status" -eq 0 ] || {
      echo "$cmd -h exited $status (expected 0)"
      echo "$output"
      return 1
    }
  done
}

@test "scaffolding family: help output is purpose-line + Usage-line" {
  local row cmd
  for row in "${FAMILY[@]}"; do
    IFS='|' read -r cmd _rest <<< "$row"
    run _help_for "$cmd"
    [ "$status" -eq 0 ]
    # First line is a non-empty one-line purpose statement that does not
    # itself start with "Usage:".
    local first_line
    first_line=$(printf '%s\n' "$output" | head -1)
    [ -n "$first_line" ] || { echo "$cmd: first help line is empty"; return 1; }
    case "$first_line" in
      Usage:*)
        echo "$cmd: first help line should be a purpose, not a Usage: line"
        return 1
        ;;
    esac
    # And there's a Usage: line somewhere in the help output.
    printf '%s\n' "$output" | grep -qE '^Usage: ' || {
      echo "$cmd: help output missing Usage: line"
      printf '%s\n' "$output"
      return 1
    }
  done
}

@test "scaffolding family: Usage line names the right subcommand" {
  local row cmd subcmd
  for row in "${FAMILY[@]}"; do
    IFS='|' read -r cmd subcmd _rest <<< "$row"
    run _help_for "$cmd"
    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | grep -qE "^Usage: $subcmd " || {
      echo "$cmd: Usage line should start with 'Usage: $subcmd '"
      printf '%s\n' "$output"
      return 1
    }
  done
}

@test "scaffolding family: documented flags match the user-story examples" {
  # The user-story (docs/user-stories/03-add-and-maintain-config.md) is the
  # public contract. Each flag listed in the FAMILY rows above must appear
  # in the corresponding command's help output. Renaming a flag in code
  # without updating the help (and the doc) fires this test.
  local row cmd flag rest
  for row in "${FAMILY[@]}"; do
    IFS='|' read -r cmd _subcmd rest <<< "$row"
    run _help_for "$cmd"
    [ "$status" -eq 0 ]
    # `rest` holds the remaining pipe-separated flag tokens.
    local IFS_BACKUP="$IFS"
    IFS='|'
    # shellcheck disable=SC2206
    local flags=($rest)
    IFS="$IFS_BACKUP"
    for flag in "${flags[@]}"; do
      [ -n "$flag" ] || continue
      # `grep -- $flag` so grep treats `--flag-name` as a pattern, not an option.
      printf '%s\n' "$output" | grep -qF -- "$flag" || {
        echo "$cmd: help output is missing documented flag $flag"
        printf '%s\n' "$output"
        return 1
      }
    done
  done
}
