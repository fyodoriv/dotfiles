#!/usr/bin/env bats
# Tests for development dependency documentation and CI alignment.

DOTFILES_DIR="$BATS_TEST_DIRNAME/.."

assert_file_mentions_tools() {
  local file="$1"; shift
  local tool
  for tool in "$@"; do
    grep -Fq "$tool" "$file" || {
      echo "missing $tool in $file"
      return 1
    }
  done
}

@test "make install-deps includes required and optional dev tools" {
  # kcov was removed in be2dab1 — coverage now runs through the in-tree
  # bin/dotfiles-coverage harness. The Makefile must still mention the
  # current dep set.
  assert_file_mentions_tools "$DOTFILES_DIR/Makefile" \
    "shellcheck" "bats-core" "parallel" "chezmoi" "fd" "jq" "shfmt"
  grep -Fq 'brew install $(DEV_DEPS) $(OPTIONAL_DEV_DEPS)' "$DOTFILES_DIR/Makefile"
}

@test "make install-deps does not list kcov as a dependency" {
  # Lock in the kcov removal: if anyone re-adds it to DEV_DEPS or
  # OPTIONAL_DEV_DEPS, this test fails. Comments referencing kcov are
  # explanatory and stay allowed.
  ! grep -E '^\s*(DEV_DEPS|OPTIONAL_DEV_DEPS)\s*[:+]?=.*\bkcov\b' \
    "$DOTFILES_DIR/Makefile"
}

@test "README and CONTRIBUTING list the install-deps tool set" {
  for doc in "$DOTFILES_DIR/README.md" "$DOTFILES_DIR/CONTRIBUTING.md"; do
    assert_file_mentions_tools "$doc" \
      "shellcheck" "bats-core" "parallel" "chezmoi" "fd" "jq" "shfmt"
  done
}

@test "README and CONTRIBUTING reference the in-tree coverage harness" {
  for doc in "$DOTFILES_DIR/README.md" "$DOTFILES_DIR/CONTRIBUTING.md"; do
    grep -Fq 'bin/dotfiles-coverage' "$doc" || {
      echo "missing bin/dotfiles-coverage reference in $doc"
      return 1
    }
  done
}

@test "CI dependency installs include the tools used by each gate" {
  assert_file_mentions_tools "$DOTFILES_DIR/.github/workflows/ci.yml" \
    "shellcheck" "bats-core" "parallel" "chezmoi" "jq" "fd"
}
