#!/usr/bin/env bats
# Tests for endpoint-security tool shims (curl, jq, grep, find).

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  SHIM_BIN="$TEST_DOTFILES/bin"
  STUB_BIN="$TEST_DIR/stubs"

  mkdir -p "$TEST_HOME" "$SHIM_BIN" "$STUB_BIN/usr/bin" "$TEST_DOTFILES/lib" "$TEST_DOTFILES/.chezmoiscripts"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  export DOTFILES_BREW_PREFIX="$STUB_BIN/opt/homebrew"
  export PATH="$STUB_BIN/usr/bin:$PATH"

  mkdir -p "$DOTFILES_BREW_PREFIX/bin" "$DOTFILES_BREW_PREFIX/opt/curl/bin" "$DOTFILES_BREW_PREFIX/opt/grep/libexec/gnubin" \
    "$DOTFILES_BREW_PREFIX/opt/gnu-sed/libexec/gnubin" "$DOTFILES_BREW_PREFIX/opt/gawk/libexec/gnubin"
  _real_gfind="/usr/bin/find"
  [ -x /opt/homebrew/bin/gfind ] && _real_gfind="/opt/homebrew/bin/gfind"
  cp "$_real_gfind" "$DOTFILES_BREW_PREFIX/bin/gfind"
  chmod +x "$DOTFILES_BREW_PREFIX/bin/gfind"

  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-curl-shim" "$SHIM_BIN/dotfiles-link-curl-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-jq-shim" "$SHIM_BIN/dotfiles-link-jq-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-python-shim" "$SHIM_BIN/dotfiles-link-python-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-grep-shim" "$SHIM_BIN/dotfiles-link-grep-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-perl-shim" "$SHIM_BIN/dotfiles-link-perl-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-find-shim" "$SHIM_BIN/dotfiles-link-find-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-sed-shim" "$SHIM_BIN/dotfiles-link-sed-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-awk-shim" "$SHIM_BIN/dotfiles-link-awk-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-git-shim" "$SHIM_BIN/dotfiles-link-git-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-otool-shim" "$SHIM_BIN/dotfiles-link-otool-shim"
  chmod +x "$SHIM_BIN"/*

  cat > "$STUB_BIN/usr/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo system-curl "$@"
EOF
  cat > "$STUB_BIN/usr/bin/jq" <<'EOF'
#!/usr/bin/env bash
echo system-jq "$@"
EOF
  cat > "$STUB_BIN/usr/bin/grep" <<'EOF'
#!/usr/bin/env bash
echo system-grep "$@"
EOF
  cat > "$STUB_BIN/usr/bin/perl" <<'EOF'
#!/usr/bin/env bash
echo system-perl "$@"
EOF
  cat > "$STUB_BIN/usr/bin/find" <<'EOF'
#!/usr/bin/env bash
echo system-find "$@"
EOF
  chmod +x "$STUB_BIN/usr/bin/"*

  cat > "$DOTFILES_BREW_PREFIX/opt/curl/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo brew-curl "$@"
EOF
  chmod +x "$DOTFILES_BREW_PREFIX/opt/curl/bin/curl"
  cat > "$DOTFILES_BREW_PREFIX/bin/jq" <<'EOF'
#!/usr/bin/env bash
echo brew-jq "$@"
EOF
  cat > "$DOTFILES_BREW_PREFIX/bin/ggrep" <<'EOF'
#!/usr/bin/env bash
echo brew-grep "$@"
EOF
  cat > "$DOTFILES_BREW_PREFIX/bin/perl" <<'EOF'
#!/usr/bin/env bash
echo brew-perl "$@"
EOF
  cat > "$DOTFILES_BREW_PREFIX/bin/gsed" <<'EOF'
#!/usr/bin/env bash
echo brew-sed "$@"
EOF
  cat > "$DOTFILES_BREW_PREFIX/bin/gawk" <<'EOF'
#!/usr/bin/env bash
echo brew-awk "$@"
EOF
  ln -sf "$DOTFILES_BREW_PREFIX/bin/ggrep" "$DOTFILES_BREW_PREFIX/opt/grep/libexec/gnubin/grep"
  ln -sf "$DOTFILES_BREW_PREFIX/bin/gsed" "$DOTFILES_BREW_PREFIX/opt/gnu-sed/libexec/gnubin/sed"
  ln -sf "$DOTFILES_BREW_PREFIX/bin/gawk" "$DOTFILES_BREW_PREFIX/opt/gawk/libexec/gnubin/awk"
  chmod +x "$DOTFILES_BREW_PREFIX/bin/"*

  DOTFILES_BREW_PREFIX="$DOTFILES_BREW_PREFIX" "$SHIM_BIN/dotfiles-link-curl-shim"
  DOTFILES_BREW_PREFIX="$DOTFILES_BREW_PREFIX" "$SHIM_BIN/dotfiles-link-jq-shim"
  DOTFILES_BREW_PREFIX="$DOTFILES_BREW_PREFIX" "$SHIM_BIN/dotfiles-link-grep-shim"
  DOTFILES_BREW_PREFIX="$DOTFILES_BREW_PREFIX" "$SHIM_BIN/dotfiles-link-perl-shim"
  DOTFILES_BREW_PREFIX="$DOTFILES_BREW_PREFIX" "$SHIM_BIN/dotfiles-link-find-shim"
  DOTFILES_BREW_PREFIX="$DOTFILES_BREW_PREFIX" "$SHIM_BIN/dotfiles-link-sed-shim"
  DOTFILES_BREW_PREFIX="$DOTFILES_BREW_PREFIX" "$SHIM_BIN/dotfiles-link-awk-shim"
  # Stub toolchain llvm-otool so tests never touch /usr/bin/otool (endpoint agent tool-shim-public).
  # Use a bash script stub (not a copied Mach-O) — unsigned echo copies in /var/folders get SIGKILL (137).
  mkdir -p "$STUB_BIN/xcode-toolchain/usr/bin"
  cat > "$STUB_BIN/xcode-toolchain/usr/bin/llvm-otool" <<'EOF'
#!/usr/bin/env bash
echo "stub-llvm-otool $*"
EOF
  chmod +x "$STUB_BIN/xcode-toolchain/usr/bin/llvm-otool"
  DOTFILES_XCODE_TOOLCHAIN="$STUB_BIN/xcode-toolchain" \
    "$SHIM_BIN/dotfiles-link-otool-shim"

  mkdir -p "$TEST_HOME/.local/share/uv/python/cpython-3.13.13-macos-aarch64-none/bin"
  cp /bin/echo "$TEST_HOME/.local/share/uv/python/cpython-3.13.13-macos-aarch64-none/bin/python3.13"
  chmod +x "$TEST_HOME/.local/share/uv/python/cpython-3.13.13-macos-aarch64-none/bin/python3.13"
  DOTFILES_UV_PYTHON="$TEST_HOME/.local/share/uv/python/cpython-3.13.13-macos-aarch64-none/bin/python3.13" \
    "$SHIM_BIN/dotfiles-link-python-shim"
}

teardown() {
  rm -rf "$TEST_DIR"
}

_prepend_shims() {
  # shellcheck source=../lib/dotfiles-endpoint-paths.sh
  source "$TEST_DOTFILES/lib/dotfiles-endpoint-paths.sh"
  dotfiles_prepend_endpoint_tool_paths "$SHIM_BIN"
}

@test "endpoint-paths: prepends dotfiles bin and keg curl" {
  cp "$BATS_TEST_DIRNAME/../lib/dotfiles-endpoint-paths.sh" "$TEST_DOTFILES/lib/dotfiles-endpoint-paths.sh"
  _prepend_shims
  [[ "$PATH" == "$SHIM_BIN:"* ]]
  [[ "$PATH" == *"$DOTFILES_BREW_PREFIX/opt/curl/bin"* ]]
  [ "${HOMEBREW_CURL_PATH:-}" = "$DOTFILES_BREW_PREFIX/opt/curl/bin/curl" ]
}

@test "curl shim: symlink points to keg-only Homebrew curl" {
  [ -L "$SHIM_BIN/curl" ]
  [ "$(readlink "$SHIM_BIN/curl")" = "$DOTFILES_BREW_PREFIX/opt/curl/bin/curl" ]
}

@test "curl shim: prefers Homebrew curl over system curl" {
  cp "$BATS_TEST_DIRNAME/../lib/dotfiles-endpoint-paths.sh" "$TEST_DOTFILES/lib/dotfiles-endpoint-paths.sh"
  _prepend_shims
  run "$SHIM_BIN/curl" -sf example.com
  [ "$status" -eq 0 ]
  [[ "$output" == "brew-curl -sf example.com" ]]
}

@test "curl shim: not a bash script (EPDL unsigned fix)" {
  [ -L "$SHIM_BIN/curl" ]
}

@test "curl shim: escape hatch documented as /usr/bin/curl in link script" {
  grep -q '/usr/bin/curl' "$SHIM_BIN/dotfiles-link-curl-shim"
}

@test "jq shim: symlink points to Homebrew jq" {
  [ -L "$SHIM_BIN/jq" ]
  [ "$(readlink "$SHIM_BIN/jq")" = "$DOTFILES_BREW_PREFIX/bin/jq" ]
}

@test "jq shim: prefers Homebrew jq over system jq" {
  cp "$BATS_TEST_DIRNAME/../lib/dotfiles-endpoint-paths.sh" "$TEST_DOTFILES/lib/dotfiles-endpoint-paths.sh"
  _prepend_shims
  run "$SHIM_BIN/jq" -n '.x=1'
  [ "$status" -eq 0 ]
  [[ "$output" == "brew-jq -n .x=1" ]]
}

@test "jq shim: not a bash script (EPDL unsigned fix)" {
  [ -L "$SHIM_BIN/jq" ]
}

@test "grep shim: symlink points to Homebrew ggrep" {
  [ -L "$SHIM_BIN/grep" ]
  [ "$(readlink "$SHIM_BIN/grep")" = "$DOTFILES_BREW_PREFIX/bin/ggrep" ]
}

@test "ggrep shim: symlink points to Homebrew ggrep" {
  [ -L "$SHIM_BIN/ggrep" ]
  [ "$(readlink "$SHIM_BIN/ggrep")" = "$DOTFILES_BREW_PREFIX/bin/ggrep" ]
}

@test "grep shim: prefers Homebrew ggrep over system grep" {
  run "$SHIM_BIN/grep" -q foo bar
  [ "$status" -eq 0 ]
  [[ "$output" == "brew-grep -q foo bar" ]]
}

@test "ggrep shim: prefers Homebrew ggrep over system grep" {
  run "$SHIM_BIN/ggrep" -q foo bar
  [ "$status" -eq 0 ]
  [[ "$output" == "brew-grep -q foo bar" ]]
}

@test "grep shim: not a bash script (EPDL unsigned fix)" {
  [ -L "$SHIM_BIN/grep" ]
  [ -L "$SHIM_BIN/ggrep" ]
}

@test "grep shim: escape hatch documented as /usr/bin/grep in link script" {
  grep -q '/usr/bin/grep' "$SHIM_BIN/dotfiles-link-grep-shim"
}

@test "perl shim: symlink points to Homebrew perl" {
  [ -L "$SHIM_BIN/perl" ]
  [ "$(readlink "$SHIM_BIN/perl")" = "$DOTFILES_BREW_PREFIX/bin/perl" ]
}

@test "perl shim: prefers Homebrew perl over system perl" {
  cp "$BATS_TEST_DIRNAME/../lib/dotfiles-endpoint-paths.sh" "$TEST_DOTFILES/lib/dotfiles-endpoint-paths.sh"
  _prepend_shims
  run "$SHIM_BIN/perl" -e 'print "ok"'
  [ "$status" -eq 0 ]
  [[ "$output" == "brew-perl -e print \"ok\"" ]]
}

@test "perl shim: not a bash script (EPDL unsigned fix)" {
  [ -L "$SHIM_BIN/perl" ]
}

@test "perl shim: escape hatch documented as /usr/bin/perl in link script" {
  grep -q '/usr/bin/perl' "$SHIM_BIN/dotfiles-link-perl-shim"
}

@test "sed shim: symlink points to Homebrew gsed" {
  [ -L "$SHIM_BIN/sed" ]
  [ "$(readlink "$SHIM_BIN/sed")" = "$DOTFILES_BREW_PREFIX/bin/gsed" ]
}

@test "sed shim: prefers Homebrew gsed over system sed" {
  run "$SHIM_BIN/sed" 's/a/b/'
  [ "$status" -eq 0 ]
  [[ "$output" == "brew-sed s/a/b/" ]]
}

@test "awk shim: symlink points to Homebrew gawk" {
  [ -L "$SHIM_BIN/awk" ]
  [ "$(readlink "$SHIM_BIN/awk")" = "$DOTFILES_BREW_PREFIX/bin/gawk" ]
}

@test "awk shim: prefers Homebrew gawk over system awk" {
  run "$SHIM_BIN/awk" '{print 1}'
  [ "$status" -eq 0 ]
  [[ "$output" == "brew-awk {print 1}" ]]
}

@test "otool shim: symlink points to Xcode/CLT llvm-otool" {
  [ -L "$SHIM_BIN/otool" ]
  # realpath may rewrite /var → /private/var on macOS temp dirs
  [ "$(readlink "$SHIM_BIN/otool")" = "$(/bin/realpath "$STUB_BIN/xcode-toolchain/usr/bin/llvm-otool")" ]
}

@test "otool shim: prefers toolchain llvm-otool over /usr/bin/otool" {
  run "$SHIM_BIN/otool" -hv /bin/ls
  [ "$status" -eq 0 ]
  [[ "$output" == "stub-llvm-otool -hv /bin/ls" ]]
}

@test "otool shim: not a bash script (EPDL unsigned fix)" {
  [ -L "$SHIM_BIN/otool" ]
}

@test "otool shim: refuses Apple tool-shim-public path" {
  grep -q 'tool-shim-public' "$SHIM_BIN/dotfiles-link-otool-shim"
  grep -q '/usr/bin/otool' "$SHIM_BIN/dotfiles-link-otool-shim"
}

@test "endpoint-paths: bootstrap resolves dotfiles dir from bin script" {
  cp "$BATS_TEST_DIRNAME/../lib/dotfiles-endpoint-paths.sh" "$TEST_DOTFILES/lib/dotfiles-endpoint-paths.sh"
  run bash -c 'source "$1/lib/dotfiles-endpoint-paths.sh"; dotfiles_resolve_dir_from_bin_script "$1/bin/dotfiles-doctor"' _ "$TEST_DOTFILES"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_DOTFILES" ]
}

@test "endpoint-paths: prepends ~/.local/bin after dotfiles bin" {
  cp "$BATS_TEST_DIRNAME/../lib/dotfiles-endpoint-paths.sh" "$TEST_DOTFILES/lib/dotfiles-endpoint-paths.sh"
  mkdir -p "$TEST_HOME/.local/bin"
  _prepend_shims
  [[ "$PATH" == "$SHIM_BIN:"* ]]
  [[ "$PATH" == *"$TEST_HOME/.local/bin"* ]]
}

@test "python3 shim: symlink points to uv-managed python3.13" {
  [ -L "$SHIM_BIN/python3" ]
  [ "$(readlink "$SHIM_BIN/python3")" = "$TEST_HOME/.local/share/uv/python/cpython-3.13.13-macos-aarch64-none/bin/python3.13" ]
}

@test "python3.13 shim: symlink points to same uv python" {
  [ -L "$SHIM_BIN/python3.13" ]
  [ "$(readlink "$SHIM_BIN/python3.13")" = "$(readlink "$SHIM_BIN/python3")" ]
}

@test "python3 shim: not a bash script (EPDL unsigned fix)" {
  [ -L "$SHIM_BIN/python3" ]
  [ -L "$SHIM_BIN/python3.13" ]
}

@test "endpoint-security apply script invokes ad-hoc sign helpers" {
  cp "$BATS_TEST_DIRNAME/../.chezmoiscripts/run_after_endpoint-security.sh" \
     "$TEST_DOTFILES/.chezmoiscripts/run_after_endpoint-security.sh"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-adhoc-sign-bottles" "$SHIM_BIN/dotfiles-adhoc-sign-bottles"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-adhoc-sign-uv-pythons" "$SHIM_BIN/dotfiles-adhoc-sign-uv-pythons"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-adhoc-sign-endpoint-shims" "$SHIM_BIN/dotfiles-adhoc-sign-endpoint-shims"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-curl-shim" "$SHIM_BIN/dotfiles-link-curl-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-jq-shim" "$SHIM_BIN/dotfiles-link-jq-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-python-shim" "$SHIM_BIN/dotfiles-link-python-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-grep-shim" "$SHIM_BIN/dotfiles-link-grep-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-perl-shim" "$SHIM_BIN/dotfiles-link-perl-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-find-shim" "$SHIM_BIN/dotfiles-link-find-shim"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-link-otool-shim" "$SHIM_BIN/dotfiles-link-otool-shim"
  chmod +x "$TEST_DOTFILES/.chezmoiscripts/run_after_endpoint-security.sh" \
           "$SHIM_BIN/dotfiles-adhoc-sign-bottles" \
           "$SHIM_BIN/dotfiles-adhoc-sign-uv-pythons" \
           "$SHIM_BIN/dotfiles-adhoc-sign-endpoint-shims" \
           "$SHIM_BIN/dotfiles-link-curl-shim" \
           "$SHIM_BIN/dotfiles-link-jq-shim" \
           "$SHIM_BIN/dotfiles-link-python-shim" \
           "$SHIM_BIN/dotfiles-link-grep-shim" \
           "$SHIM_BIN/dotfiles-link-perl-shim" \
           "$SHIM_BIN/dotfiles-link-otool-shim"

  cat > "$SHIM_BIN/dotfiles-adhoc-sign-jq" <<'EOF'
#!/usr/bin/env bash
echo signed-jq >> "$HOME/sign.log"
EOF
  cat > "$SHIM_BIN/dotfiles-adhoc-sign-curl" <<'EOF'
#!/usr/bin/env bash
echo signed-curl >> "$HOME/sign.log"
EOF
  cat > "$SHIM_BIN/dotfiles-adhoc-sign-ggrep" <<'EOF'
#!/usr/bin/env bash
echo signed-ggrep >> "$HOME/sign.log"
EOF
  cat > "$SHIM_BIN/dotfiles-adhoc-sign-bottles" <<'EOF'
#!/usr/bin/env bash
echo signed-bottles >> "$HOME/sign.log"
EOF
  cat > "$SHIM_BIN/dotfiles-adhoc-sign-uv-pythons" <<'EOF'
#!/usr/bin/env bash
echo signed-uv >> "$HOME/sign.log"
EOF
  cat > "$SHIM_BIN/dotfiles-adhoc-sign-endpoint-shims" <<'EOF'
#!/usr/bin/env bash
echo signed-endpoint-shims >> "$HOME/sign.log"
EOF
  cat > "$SHIM_BIN/dotfiles-link-curl-shim" <<'EOF'
#!/usr/bin/env bash
echo linked-curl >> "$HOME/sign.log"
EOF
  cat > "$SHIM_BIN/dotfiles-link-jq-shim" <<'EOF'
#!/usr/bin/env bash
echo linked-jq >> "$HOME/sign.log"
EOF
  cat > "$SHIM_BIN/dotfiles-link-python-shim" <<'EOF'
#!/usr/bin/env bash
echo linked-python >> "$HOME/sign.log"
EOF
  cat > "$SHIM_BIN/dotfiles-link-grep-shim" <<'EOF'
#!/usr/bin/env bash
echo linked-grep >> "$HOME/sign.log"
EOF
  cat > "$SHIM_BIN/dotfiles-link-perl-shim" <<'EOF'
#!/usr/bin/env bash
echo linked-perl >> "$HOME/sign.log"
EOF
  cat > "$SHIM_BIN/dotfiles-link-sed-shim" <<'EOF'
#!/usr/bin/env bash
echo linked-sed >> "$HOME/sign.log"
EOF
  cat > "$SHIM_BIN/dotfiles-link-awk-shim" <<'EOF'
#!/usr/bin/env bash
echo linked-awk >> "$HOME/sign.log"
EOF
  cat > "$SHIM_BIN/dotfiles-link-find-shim" <<'EOF'
#!/usr/bin/env bash
echo linked-find >> "$HOME/sign.log"
EOF
  cat > "$SHIM_BIN/dotfiles-link-otool-shim" <<'EOF'
#!/usr/bin/env bash
echo linked-otool >> "$HOME/sign.log"
EOF
  cat > "$SHIM_BIN/dotfiles-link-git-shim" <<'EOF'
#!/usr/bin/env bash
echo linked-git >> "$HOME/sign.log"
EOF
  chmod +x "$SHIM_BIN/dotfiles-adhoc-sign-jq" \
           "$SHIM_BIN/dotfiles-adhoc-sign-curl" \
           "$SHIM_BIN/dotfiles-adhoc-sign-ggrep" \
           "$SHIM_BIN/dotfiles-adhoc-sign-bottles" \
           "$SHIM_BIN/dotfiles-adhoc-sign-uv-pythons" \
           "$SHIM_BIN/dotfiles-adhoc-sign-endpoint-shims" \
           "$SHIM_BIN/dotfiles-link-curl-shim" \
           "$SHIM_BIN/dotfiles-link-jq-shim" \
           "$SHIM_BIN/dotfiles-link-python-shim" \
           "$SHIM_BIN/dotfiles-link-grep-shim" \
           "$SHIM_BIN/dotfiles-link-perl-shim" \
           "$SHIM_BIN/dotfiles-link-sed-shim" \
           "$SHIM_BIN/dotfiles-link-awk-shim" \
           "$SHIM_BIN/dotfiles-link-find-shim" \
           "$SHIM_BIN/dotfiles-link-otool-shim" \
           "$SHIM_BIN/dotfiles-link-git-shim"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_endpoint-security.sh"
  [ "$status" -eq 0 ]
  grep -qx signed-jq "$TEST_HOME/sign.log"
  grep -qx signed-curl "$TEST_HOME/sign.log"
  grep -qx signed-ggrep "$TEST_HOME/sign.log"
  grep -qx signed-bottles "$TEST_HOME/sign.log"
  grep -qx signed-uv "$TEST_HOME/sign.log"
  grep -qx linked-curl "$TEST_HOME/sign.log"
  grep -qx linked-jq "$TEST_HOME/sign.log"
  grep -qx linked-python "$TEST_HOME/sign.log"
  grep -qx linked-grep "$TEST_HOME/sign.log"
  grep -qx linked-perl "$TEST_HOME/sign.log"
  grep -qx linked-sed "$TEST_HOME/sign.log"
  grep -qx linked-awk "$TEST_HOME/sign.log"
  grep -qx linked-find "$TEST_HOME/sign.log"
  grep -qx linked-otool "$TEST_HOME/sign.log"
  grep -qx linked-git "$TEST_HOME/sign.log"
  grep -qx signed-endpoint-shims "$TEST_HOME/sign.log"
}

@test "endpoint-security apply script prefers CHEZMOI_SOURCE_DIR over the dev checkout" {
  local applied="$TEST_DIR/applied" dev="$TEST_HOME/apps/tooling/dotfiles" copy="$TEST_DIR/chezmoi-tmp"
  local label dir helper
  for label in applied dev; do
    dir="$applied"; [ "$label" = dev ] && dir="$dev"
    mkdir -p "$dir/bin"
    for helper in dotfiles-adhoc-sign-jq dotfiles-adhoc-sign-uv-pythons \
                  dotfiles-adhoc-sign-bottles dotfiles-adhoc-sign-endpoint-shims; do
      printf '#!/usr/bin/env bash\necho %s-%s >> "$HOME/sign.log"\n' "$label" "$helper" > "$dir/bin/$helper"
      chmod +x "$dir/bin/$helper"
    done
  done
  mkdir -p "$copy"
  cp "$BATS_TEST_DIRNAME/../.chezmoiscripts/run_after_endpoint-security.sh" "$copy/run.sh"

  CHEZMOI_SOURCE_DIR="$applied" DOTFILES_DIR="" run bash "$copy/run.sh"
  [ "$status" -eq 0 ]
  # setup() stubs grep to always succeed, so match with bash instead.
  local log
  log="$(<"$TEST_HOME/sign.log")"
  [[ "$log" == *applied-dotfiles-adhoc-sign-bottles* ]]
  [[ "$log" != *dev-dotfiles-* ]]
}

@test "endpoint shim signer ad-hoc signs find script shim" {
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-adhoc-sign-endpoint-shims" "$SHIM_BIN/dotfiles-adhoc-sign-endpoint-shims"
  chmod +x "$SHIM_BIN/dotfiles-adhoc-sign-endpoint-shims"
  codesign --remove-signature "$SHIM_BIN/find" >/dev/null 2>&1 || true

  run "$SHIM_BIN/dotfiles-adhoc-sign-endpoint-shims" "$SHIM_BIN"
  [ "$status" -eq 0 ]
  codesign -dvv "$SHIM_BIN/find" 2>&1 | grep -q "Signature=adhoc"
}

@test "bin executables: no #!/usr/bin/env shebang (endpoint agents may block /usr/bin/env)" {
  local bad=0 bin_dir="$BATS_TEST_DIRNAME/../bin"
  while IFS= read -r script; do
    [ -n "$script" ] || continue
    echo "env shebang found: $script" >&2
    bad=1
  done < <(/usr/bin/grep -rl '^#!/usr/bin/env' "$bin_dir" 2>/dev/null || true)
  [ "$bad" -eq 0 ]
}
