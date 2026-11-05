#!/usr/bin/env bats
# SSH-style github.com URLs must go over HTTPS with the gh credential helper,
# so a missing or unregistered SSH key never blocks a push.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CFG="$BATS_TEST_TMPDIR/gitconfig"
  # Render without chezmoi: the url section has no template logic.
  sed -n '/^\[url "https:\/\/github.com\/"\]/,/^\[/p' "$REPO/dot_gitconfig.tmpl" | sed '$d' >"$CFG"
}

rewrite() {
  GIT_CONFIG_GLOBAL="$CFG" GIT_CONFIG_NOSYSTEM=1 git ls-remote --get-url "$1"
}

@test "git@github.com: URLs go over HTTPS" {
  run rewrite git@github.com:fyodoriv/dotfiles.git
  [ "$status" -eq 0 ]
  [ "$output" = "https://github.com/fyodoriv/dotfiles.git" ]
}

@test "ssh://git@github.com/ URLs go over HTTPS" {
  run rewrite ssh://git@github.com/fyodoriv/dotfiles.git
  [ "$output" = "https://github.com/fyodoriv/dotfiles.git" ]
}

@test "other SSH hosts keep SSH" {
  run rewrite git@github.example.com:org/repo.git
  [ "$output" = "git@github.example.com:org/repo.git" ]
}
