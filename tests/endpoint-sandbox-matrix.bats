#!/usr/bin/env bats
# Sandbox PATH regression matrix — simulates Cursor agent subshell PATH
# (/opt/homebrew/bin:/usr/bin:/bin) and asserts shims resolve after bootstrap.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  SHIM_BIN="$TEST_DOTFILES/bin"
  STUB_HB="$TEST_DIR/stubs/opt/homebrew"

  mkdir -p "$TEST_HOME" "$SHIM_BIN" "$STUB_HB/bin" "$STUB_HB/opt/curl/bin" \
    "$STUB_HB/opt/grep/libexec/gnubin" "$STUB_HB/opt/gnu-sed/libexec/gnubin" \
    "$STUB_HB/opt/gawk/libexec/gnubin" "$TEST_DOTFILES/lib" "$TEST_DOTFILES/agent-hooks"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  export DOTFILES_BREW_PREFIX="$STUB_HB"
  export SANDBOX_PATH="/opt/homebrew/bin:/usr/bin:/bin"

  cp /bin/echo "$STUB_HB/bin/jq"
  cp /bin/echo "$STUB_HB/bin/ggrep"
  cp /bin/echo "$STUB_HB/bin/gsed"
  cp /bin/echo "$STUB_HB/bin/gawk"
  cp /bin/echo "$STUB_HB/bin/perl"
  cp /bin/echo "$STUB_HB/bin/gfind"
  cp /bin/echo "$STUB_HB/opt/curl/bin/curl"
  chmod +x "$STUB_HB/bin/"* "$STUB_HB/opt/curl/bin/curl"
  ln -sf "$STUB_HB/bin/ggrep" "$STUB_HB/opt/grep/libexec/gnubin/grep"
  ln -sf "$STUB_HB/bin/gsed" "$STUB_HB/opt/gnu-sed/libexec/gnubin/sed"
  ln -sf "$STUB_HB/bin/gawk" "$STUB_HB/opt/gawk/libexec/gnubin/awk"

  for shim_script in curl jq grep perl find sed awk otool python git; do
    [ -f "$BATS_TEST_DIRNAME/../bin/dotfiles-link-${shim_script}-shim" ] || continue
    cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-${shim_script}-shim" "$SHIM_BIN/"
    chmod +x "$SHIM_BIN/dotfiles-link-${shim_script}-shim"
  done

  cp "$BATS_TEST_DIRNAME/../lib/dotfiles-endpoint-paths.sh" "$TEST_DOTFILES/lib/"
  cp "$BATS_TEST_DIRNAME/../agent-hooks/bootstrap-endpoint-path.sh" "$TEST_DOTFILES/agent-hooks/"
  chmod +x "$TEST_DOTFILES/agent-hooks/bootstrap-endpoint-path.sh"

  cat > "$SHIM_BIN/git" <<'EOF'
#!/bin/bash
echo dotfiles-git "$@"
EOF
  chmod +x "$SHIM_BIN/git"

  DOTFILES_BREW_PREFIX="$STUB_HB" "$SHIM_BIN/dotfiles-link-curl-shim"
  DOTFILES_BREW_PREFIX="$STUB_HB" "$SHIM_BIN/dotfiles-link-jq-shim"
  DOTFILES_BREW_PREFIX="$STUB_HB" "$SHIM_BIN/dotfiles-link-grep-shim"
  DOTFILES_BREW_PREFIX="$STUB_HB" "$SHIM_BIN/dotfiles-link-perl-shim"
  DOTFILES_BREW_PREFIX="$STUB_HB" "$SHIM_BIN/dotfiles-link-find-shim"
  DOTFILES_BREW_PREFIX="$STUB_HB" "$SHIM_BIN/dotfiles-link-sed-shim"
  DOTFILES_BREW_PREFIX="$STUB_HB" "$SHIM_BIN/dotfiles-link-awk-shim"
  mkdir -p "$STUB_HB/xcode-toolchain/usr/bin"
  cat > "$STUB_HB/xcode-toolchain/usr/bin/llvm-otool" <<'EOF'
#!/usr/bin/env bash
echo stub-llvm-otool
EOF
  chmod +x "$STUB_HB/xcode-toolchain/usr/bin/llvm-otool"
  DOTFILES_XCODE_TOOLCHAIN="$STUB_HB/xcode-toolchain" \
    "$SHIM_BIN/dotfiles-link-otool-shim"
}

teardown() {
  rm -rf "$TEST_DIR"
}

_bootstrap_sandbox() {
  PATH="$SANDBOX_PATH" bash -c "
    export HOME='$TEST_HOME'
    export DOTFILES_DIR='$TEST_DOTFILES'
    source '$TEST_DOTFILES/agent-hooks/bootstrap-endpoint-path.sh'
    command -v $1
  "
}

@test "sandbox matrix: bootstrap resolves jq away from /usr/bin/jq" {
  run _bootstrap_sandbox jq
  [ "$status" -eq 0 ]
  [[ "$output" == "$SHIM_BIN/jq" ]]
}

@test "sandbox matrix: bootstrap resolves grep away from /usr/bin/grep" {
  run _bootstrap_sandbox grep
  [ "$status" -eq 0 ]
  [[ "$output" == "$SHIM_BIN/grep" ]]
}

@test "sandbox matrix: bootstrap resolves sed away from /usr/bin/sed" {
  run _bootstrap_sandbox sed
  [ "$status" -eq 0 ]
  [[ "$output" == "$SHIM_BIN/sed" ]]
}

@test "sandbox matrix: bootstrap resolves awk away from /usr/bin/awk" {
  run _bootstrap_sandbox awk
  [ "$status" -eq 0 ]
  [[ "$output" == "$SHIM_BIN/awk" ]]
}

@test "sandbox matrix: bootstrap resolves find away from /usr/bin/find" {
  run _bootstrap_sandbox find
  [ "$status" -eq 0 ]
  [[ "$output" == "$SHIM_BIN/find" ]]
}

@test "sandbox matrix: bootstrap resolves otool away from /usr/bin/otool" {
  run _bootstrap_sandbox otool
  [ "$status" -eq 0 ]
  [[ "$output" == "$SHIM_BIN/otool" ]]
}

@test "sandbox matrix: bootstrap resolves curl away from /usr/bin/curl" {
  run _bootstrap_sandbox curl
  [ "$status" -eq 0 ]
  [[ "$output" == "$SHIM_BIN/curl" ]]
}

@test "sandbox matrix: bootstrap resolves perl away from /usr/bin/perl" {
  run _bootstrap_sandbox perl
  [ "$status" -eq 0 ]
  [[ "$output" == "$SHIM_BIN/perl" ]]
}

@test "sandbox matrix: bootstrap resolves git away from /usr/bin/git" {
  run _bootstrap_sandbox git
  [ "$status" -eq 0 ]
  [[ "$output" == "$SHIM_BIN/git" ]]
}

@test "sandbox matrix: bootstrap resolves python3.13 via dotfiles shim when uv python present" {
  mkdir -p "$TEST_HOME/.local/share/uv/python/cpython-3.13.14-macos-aarch64-none/bin"
  cp /bin/echo "$TEST_HOME/.local/share/uv/python/cpython-3.13.14-macos-aarch64-none/bin/python3.13"
  chmod +x "$TEST_HOME/.local/share/uv/python/cpython-3.13.14-macos-aarch64-none/bin/python3.13"
  codesign --sign - --force "$TEST_HOME/.local/share/uv/python/cpython-3.13.14-macos-aarch64-none/bin/python3.13" >/dev/null 2>&1 || true
  DOTFILES_UV_PYTHON="$TEST_HOME/.local/share/uv/python/cpython-3.13.14-macos-aarch64-none/bin/python3.13" \
    "$SHIM_BIN/dotfiles-link-python-shim"
  run _bootstrap_sandbox python3.13
  [ "$status" -eq 0 ]
  [[ "$output" == "$SHIM_BIN/python3.13" ]]
}

@test "sandbox matrix: bare sandbox PATH hits gnu grep alias without bootstrap (not /usr/bin/grep)" {
  mkdir -p "$STUB_HB/bin"
  cp /bin/echo "$STUB_HB/bin/ggrep"
  chmod +x "$STUB_HB/bin/ggrep"
  ln -sfn ggrep "$STUB_HB/bin/grep"
  run env PATH="$STUB_HB/bin:/usr/bin:/bin" command -v grep
  [ "$status" -eq 0 ]
  [[ "$output" == "$STUB_HB/bin/grep" ]]
  [[ "$output" != "/usr/bin/grep" ]]
}

@test "sandbox matrix: sed shim is symlink to gsed" {
  [ -L "$SHIM_BIN/sed" ]
  [[ "$(readlink "$SHIM_BIN/sed")" == *gsed* ]]
}

@test "sandbox matrix: awk shim is symlink to gawk" {
  [ -L "$SHIM_BIN/awk" ]
  [[ "$(readlink "$SHIM_BIN/awk")" == *gawk* ]]
}

@test "sandbox matrix: otool shim is symlink to llvm-otool" {
  [ -L "$SHIM_BIN/otool" ]
  [[ "$(readlink "$SHIM_BIN/otool")" == *llvm-otool* ]]
}

@test "sandbox matrix: fnm node on PATH when .node-version present" {
  mkdir -p "$TEST_HOME/.local/share/fnm/node-versions/v20.0.0/installation/bin"
  cp /bin/echo "$TEST_HOME/.local/share/fnm/node-versions/v20.0.0/installation/bin/node"
  cp /bin/echo "$TEST_HOME/.local/share/fnm/node-versions/v20.0.0/installation/bin/npx"
  chmod +x "$TEST_HOME/.local/share/fnm/node-versions/v20.0.0/installation/bin/"*
  echo "v20.0.0" > "$TEST_HOME/.node-version"

  run env HOME="$TEST_HOME" DOTFILES_DIR="$TEST_DOTFILES" PATH="$SANDBOX_PATH" \
    /bin/bash -c "
      source '$TEST_DOTFILES/agent-hooks/bootstrap-endpoint-path.sh'
      command -v node
    "
  [ "$status" -eq 0 ]
  [[ "$output" == *fnm/node-versions/v20.0.0/installation/bin/node ]]
}
