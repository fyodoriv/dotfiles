#!/usr/bin/env bats
# Tests for bin/dotfiles-remove-framework-python

load test_helper

@test "remove-framework-python: script exists and is executable" {
  [ -x "$BATS_TEST_DIRNAME/../bin/dotfiles-remove-framework-python" ]
}

@test "remove-framework-python: exits early in agent terminal" {
  export DOTFILES_IS_AGENT=1
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-remove-framework-python"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sudo"* ]] || [[ "$output" == *"agent"* ]]
}

@test "remove-framework-python: exits 0 when no framework install exists" {
  # On machines without python.org framework, should exit clean
  if [ -d "/Library/Frameworks/Python.framework" ]; then
    skip "Framework python exists on this machine — skip destructive test"
  fi
  unset DOTFILES_IS_AGENT
  run bash "$BATS_TEST_DIRNAME/../bin/dotfiles-remove-framework-python"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to do"* ]] || [[ "$output" == *"No python.org"* ]]
}

@test "remove-framework-python: IT ticket lists the install paths that exist" {
  root="$(mktemp -d)"
  fake_bin="$root/usr/local/bin"
  mkdir -p "$root/Library/Frameworks/Python.framework/Versions/3.14" \
    "$root/Library/Frameworks/PythonT.framework" \
    "$root/Applications/Python 3.14" \
    "$fake_bin" "$root/stub-bin" "$root/home"
  ln -s "$root/Library/Frameworks/Python.framework/Versions/3.14/bin/python3" \
    "$fake_bin/python3-intel64"
  printf '#!/bin/bash\nexit 1\n' > "$root/stub-bin/sudo"
  printf '#!/bin/bash\nexit 1\n' > "$root/stub-bin/uv"
  printf '#!/bin/bash\nexit 0\n' > "$root/stub-bin/launchctl"
  chmod +x "$root/stub-bin/sudo" "$root/stub-bin/uv" "$root/stub-bin/launchctl"

  run env -u DOTFILES_IS_AGENT HOME="$root/home" PATH="$root/stub-bin:$PATH" \
    DOTFILES_PYTHON_ROOT="$root" bash "$BATS_TEST_DIRNAME/../bin/dotfiles-remove-framework-python"
  rm -rf "$root"

  [ "$status" -eq 0 ]
  [[ "$output" == *"USER-MODE"* ]]
  [[ "$output" == *"$root/Library/Frameworks/Python.framework"* ]]
  [[ "$output" == *"$root/Library/Frameworks/PythonT.framework"* ]]
  [[ "$output" == *"$root/Applications/Python 3.14"* ]]
  [[ "$output" == *"$fake_bin/python3-intel64"* ]]
  [[ "$output" != *"/Applications/Python 3.13"* ]]
  [[ "$output" != *"Cellar/python@3.13"* ]]
  [[ "$output" != *"com.minsky"* ]]
}

@test "remove-framework-python: --profile-only strips python.org PATH blocks, keeps the rest" {
  home="$(mktemp -d)"
  cat > "$home/.zprofile" <<'PROFILE'
# keep me
# Setting PATH for Python 2.7
# The original version is saved in .zprofile.pysave
PATH="/Library/Frameworks/Python.framework/Versions/2.7/bin:${PATH}"
export PATH
eval "$(/opt/homebrew/bin/brew shellenv)"

# Setting PATH for Python 3.11
# The original version is saved in .zprofile.pysave
PATH="/Library/Frameworks/Python.framework/Versions/3.11/bin:${PATH}"
export PATH
export PATH="$HOME/bin:$PATH"
PROFILE
  run env HOME="$home" DOTFILES_IS_AGENT=1 bash "$BATS_TEST_DIRNAME/../bin/dotfiles-remove-framework-python" --profile-only
  [ "$status" -eq 0 ]
  ! grep -q 'Python.framework' "$home/.zprofile"
  ! grep -q 'Setting PATH for Python' "$home/.zprofile"
  grep -q '^# keep me$' "$home/.zprofile"
  grep -q 'brew shellenv' "$home/.zprofile"
  grep -q '^export PATH="$HOME/bin:$PATH"$' "$home/.zprofile"
  [ "$(grep -c '^export PATH$' "$home/.zprofile")" -eq 0 ]
  ls "$home"/.zprofile.dotfiles-bak-* >/dev/null
  grep -q 'Versions/3.11' "$home"/.zprofile.dotfiles-bak-*
}

@test "remove-framework-python: --profile-only is a no-op without python.org blocks" {
  home="$(mktemp -d)"
  printf 'export PATH="$HOME/bin:$PATH"\n' > "$home/.zprofile"
  run env HOME="$home" bash "$BATS_TEST_DIRNAME/../bin/dotfiles-remove-framework-python" --profile-only
  [ "$status" -eq 0 ]
  [[ "$output" == *"no python.org PATH"* ]]
  ! ls "$home"/.zprofile.dotfiles-bak-* >/dev/null 2>&1
}
