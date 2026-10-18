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

# A scratch dotfiles repo (bin/dotfiles-add, .chezmoiignore, a tools module)
# and a scratch HOME, so `dotfiles add` and `chezmoi apply` never touch the
# real checkout or the real HOME.
_scratch_repo() {
  SCRATCH="$(cd "$BATS_TEST_TMPDIR" && pwd -P)"
  export HOME="$SCRATCH/home"
  FAKE_REPO="$SCRATCH/dotfiles"
  mkdir -p "$HOME" "$FAKE_REPO/bin" "$FAKE_REPO/home" "$FAKE_REPO/modules/tools"
  cp "$REPO_ROOT/bin/dotfiles-add" "$FAKE_REPO/bin/"
  cp "$REPO_ROOT/.chezmoiignore" "$FAKE_REPO/"
  : > "$FAKE_REPO/modules/tools/doctor.sh"
  # .chezmoiignore reads these two keys without a default.
  printf 'data:\n  profile: core\n  is_enterprise: false\n' > "$SCRATCH/chezmoi.yaml"
}

_apply() {
  chezmoi apply --source "$FAKE_REPO" --destination "$HOME" \
    --config "$SCRATCH/chezmoi.yaml" --cache "$SCRATCH/cache" \
    --persistent-state "$SCRATCH/state.boltdb" "$@"
}

@test "dotfiles add: a nested file keeps its path under HOME after apply" {
  _scratch_repo
  mkdir -p "$HOME/.config/x"
  printf 'y=1\n' > "$HOME/.config/x/y.conf"
  run "$FAKE_REPO/bin/dotfiles-add" "$HOME/.config/x/y.conf"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -f "$FAKE_REPO/home/config/x/y.conf" ]
  [ -f "$FAKE_REPO/dot_config/x/symlink_y.conf.tmpl" ]
  rm "$HOME/.config/x/y.conf"
  run _apply "$HOME/.config/x/y.conf"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -L "$HOME/.config/x/y.conf" ]
  [ "$(readlink "$HOME/.config/x/y.conf")" = "$FAKE_REPO/home/config/x/y.conf" ]
  [ "$(cat "$HOME/.config/x/y.conf")" = "y=1" ]
  [ ! -e "$HOME/.y.conf" ]
  [ ! -e "$FAKE_REPO/symlink_dot_y.conf.tmpl" ]
}

@test "dotfiles add: a top-level dotfile still lands in home/ and links after apply" {
  _scratch_repo
  printf 'top=1\n' > "$HOME/.toprc"
  run "$FAKE_REPO/bin/dotfiles-add" "$HOME/.toprc"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -f "$FAKE_REPO/home/toprc" ]
  [ "$(cat "$FAKE_REPO/symlink_dot_toprc.tmpl")" = '{{ .chezmoi.sourceDir }}/home/toprc' ]
  grep -qF 'symlink._toprc' "$FAKE_REPO/modules/tools/doctor.sh"
  rm "$HOME/.toprc"
  run _apply "$HOME/.toprc"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [ -L "$HOME/.toprc" ]
  [ "$(cat "$HOME/.toprc")" = "top=1" ]
}
