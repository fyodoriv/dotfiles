#!/usr/bin/env bats
# Homebrew owns python3 in its bin. A dotfiles link there makes
# `brew upgrade` fail with "same file: .../bin/python3" (2026-10-27).

@test "no dotfiles script links python3 into the Homebrew bin" {
  cd "$BATS_TEST_DIRNAME/.."
  run rg -n --no-heading -e '(brew_bin|BREW_PREFIX|homebrew/bin)[^#]*python3' -e 'for name in python3' bin lib .chezmoiscripts
  [ "$status" -eq 1 ]
}

@test "the orphan sandbox alias linker stays removed" {
  [ ! -e "$BATS_TEST_DIRNAME/../bin/dotfiles-link-homebrew-gnu-sandbox-aliases" ]
}
