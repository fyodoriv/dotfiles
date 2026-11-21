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

@test "remove-framework-python: user-only repair leaves sudo, framework Python and dormant files alone" {
  local root="$BATS_TEST_TMPDIR/root"
  local home="$root/home" stubs="$root/stub-bin"
  local framework_bin="$root/Library/Frameworks/Python.framework/Versions/3.14/bin"
  mkdir -p "$home/.config/venv.framework-bak" "$stubs" "$framework_bin"
  export FRAMEWORK_REPAIR_CALLS="$root/calls"
  : > "$FRAMEWORK_REPAIR_CALLS"
  printf '#!/bin/bash\nprintf "sudo\\n" >> "$FRAMEWORK_REPAIR_CALLS"\nexit 1\n' > "$stubs/sudo"
  printf '#!/bin/bash\nprintf "python3\\n" >> "$FRAMEWORK_REPAIR_CALLS"\n' > "$framework_bin/python3"
  printf '#!/bin/bash\nexit 1\n' > "$stubs/uv"
  printf '#!/bin/bash\nexit 0\n' > "$stubs/launchctl"
  chmod +x "$stubs/"{sudo,uv,launchctl} "$framework_bin/python3"
  local reference='/Library/Frameworks/Python.framework/Versions/3.14/bin/python3'
  printf '%s\n' "$reference" > "$home/.config/active.conf"
  printf '%s\n' "$reference" > "$home/.config/tool.log"
  printf '%s\n' "$reference" > "$home/.config/venv.framework-bak/pyvenv.cfg"

  run env -u DOTFILES_IS_AGENT HOME="$home" PATH="$framework_bin:$stubs:$PATH" \
    DOTFILES_PYTHON_ROOT="$root" bash "$BATS_TEST_DIRNAME/../bin/dotfiles-remove-framework-python" --user-only
  [ "$status" -eq 0 ]
  if [ -s "$FRAMEWORK_REPAIR_CALLS" ]; then
    printf 'Unexpected commands in user-only repair:\n'
    cat "$FRAMEWORK_REPAIR_CALLS"
    return 1
  fi
  [[ "$output" == *"$home/.config/active.conf"* ]]
  [[ "$output" != *tool.log* && "$output" != *venv.framework-bak* ]]
  [[ "$output" == *"ask an administrator"* ]]
  [ -d "$framework_bin" ]

  printf '# Setting PATH for Python 3.14\nPATH="%s:\${PATH}"\nexport PATH\n' "$framework_bin" > "$home/.zprofile"
  cp "$home/.zprofile" "$root/original-profile"
  run env -u DOTFILES_IS_AGENT HOME="$home" PATH="$framework_bin:$stubs:$PATH" \
    DOTFILES_PYTHON_ROOT="$root" bash "$BATS_TEST_DIRNAME/../bin/dotfiles-remove-framework-python" --user-onyl
  if [ "$status" -ne 2 ]; then
    printf 'Expected invalid option to exit 2, got %s.\n' "$status"
    return 1
  fi
  [ ! -s "$FRAMEWORK_REPAIR_CALLS" ]
  cmp -s "$home/.zprofile" "$root/original-profile"
}

@test "remove-framework-python: a failed pipx reinstall reports incomplete repair" {
  local root="$BATS_TEST_TMPDIR/root"
  local home="$root/home" stubs="$root/stub-bin"
  local pipx_venv="$home/.local/pipx/venvs/tool-example"
  mkdir -p "$pipx_venv" "$stubs" "$root/Library/Frameworks/Python.framework"
  printf 'home = /Library/Frameworks/Python.framework/Versions/3.14/bin\n' > "$pipx_venv/pyvenv.cfg"
  export FRAMEWORK_REPAIR_CALLS="$root/calls"
  export FRAMEWORK_REPAIR_PYTHON="$stubs/python-fixture"
  : > "$FRAMEWORK_REPAIR_CALLS"
  cp /bin/echo "$FRAMEWORK_REPAIR_PYTHON"
  printf '#!/bin/bash\nprintf "%%s\\n" "$FRAMEWORK_REPAIR_PYTHON"\n' > "$stubs/uv"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$FRAMEWORK_REPAIR_CALLS"\nexit 1\n' > "$stubs/pipx"
  printf '#!/bin/bash\nprintf "unexpected sudo\\n" >> "$FRAMEWORK_REPAIR_CALLS"\nexit 1\n' > "$stubs/sudo"
  printf '#!/bin/bash\nexit 0\n' > "$stubs/launchctl"
  chmod +x "$stubs/"{uv,pipx,sudo,launchctl}

  run env -u DOTFILES_IS_AGENT HOME="$home" PATH="$stubs:$PATH" \
    DOTFILES_PYTHON_ROOT="$root" bash "$BATS_TEST_DIRNAME/../bin/dotfiles-remove-framework-python" --user-only
  if [ "$status" -ne 1 ]; then
    printf 'Expected incomplete repair to exit 1, got %s.\n' "$status"
    return 1
  fi
  [[ "$output" == *"Could not rebuild tool-example"* && "$output" != *"no framework-using pipx venvs"* ]]
  [ "$(cat "$FRAMEWORK_REPAIR_CALLS")" = "reinstall --python $FRAMEWORK_REPAIR_PYTHON tool-example" ]
}

@test "remove-framework-python: Doctor gives a non-admin repair with the advisory" {
  local fixture_root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$fixture_root/Library/Frameworks/Python.framework"
  local block="$BATS_TEST_TMPDIR/doctor-framework"
  printf '_framework=%q\n' "$fixture_root/Library/Frameworks/Python.framework" > "$block"
  awk '
    /^_framework=/ { copy = 1; next }
    /pipx venv architecture drift/ { exit }
    copy { print }
  ' "$BATS_TEST_DIRNAME/../modules/security/doctor.sh" >> "$block"

  run env HOME="$fixture_root" DOTFILES_DIR="$BATS_TEST_DIRNAME/.." bash -c '
    check_advisory() { printf "%s\n" "$1" "$4"; }
    check() { printf "unexpected required check %s\n" "$1"; return 1; }
    source "$1"
  ' doctor "$block"
  [ "$status" -eq 0 ]
  [[ "$output" == *security.no_framework_python* && "$output" == *"--user-only"* && "$output" == *"administrator"* ]]
  [[ "$output" != *"unexpected required check"* ]]
}
