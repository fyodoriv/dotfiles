#!/usr/bin/env bats

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  VC_LOCAL="$TEST_DIR/vscode-local"
  VC_USER_DIR="$TEST_HOME/Library/Application Support/Code/User"
  VC_APP="$TEST_HOME/Applications/Visual Studio Code.app"
  VC_BIN="$TEST_HOME/.local/bin/code"

  mkdir -p "$TEST_HOME" "$TEST_DOTFILES/vscode" "$TEST_DOTFILES/modules/vscode" "$VC_LOCAL"
  mkdir -p "$TEST_DOTFILES/lib"
  cp "$BATS_TEST_DIRNAME/../lib/plugin.sh" "$TEST_DOTFILES/lib/"
  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  export VSCODE_LOCAL_DIR="$VC_LOCAL"
  export PATH="$(dirname "$VC_BIN"):$PATH"

  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"
  touch "$OVERRIDES_FILE"
  FIX_MODE=false
  LIST_MODE=false
  pass_count=0; fail_count=0; fix_count=0; skip_count=0; warn_count=0

  pass()        { pass_count=$((pass_count + 1)); }
  fail()        { fail_count=$((fail_count + 1)); }
  fixed()       { fix_count=$((fix_count + 1)); }
  skipped()     { skip_count=$((skip_count + 1)); }
  audit_warn()  { warn_count=$((warn_count + 1)); }
  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }

  check_symlink() {
    local id="$1" src="$2" dst="$3"
    $LIST_MODE && return
    is_overridden "$id" && { skipped "$dst"; return; }
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
      pass "$dst"
    elif $FIX_MODE; then
      mkdir -p "$(dirname "$dst")"
      [ -f "$dst" ] && mv "$dst" "${dst}.backup" 2>/dev/null
      [ -L "$dst" ] && rm "$dst"
      ln -s "$src" "$dst"
      fixed "$dst"
    else
      fail "$dst"
    fi
  }

  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="$4"
    $LIST_MODE && return
    is_overridden "$id" && { skipped "$desc"; return; }
    if eval "$test_cmd" >/dev/null 2>&1; then
      pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then
      if eval "$fix_cmd" >/dev/null 2>&1; then fixed "$desc"; else fail "$desc"; fi
    else
      fail "$desc"
    fi
  }

  check_advisory() {
    local id="$1" desc="$2" test_cmd="$3"
    $LIST_MODE && return
    is_overridden "$id" && { skipped "$desc"; return; }
    if eval "$test_cmd" >/dev/null 2>&1; then pass "$desc"; else audit_warn "$desc"; fi
  }

  security() { return 1; }
  export -f security
}

teardown() {
  rm -rf "$TEST_DIR"
}

_setup_vscode_installed() {
  mkdir -p "$VC_APP" "$VC_USER_DIR" "$(dirname "$VC_BIN")"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$VC_BIN"
  chmod +x "$VC_BIN"
  printf '{"editor.fontSize": 15, "mcpServers": {"base": {"command": "base"}}}\n' > "$TEST_DOTFILES/vscode/settings.json"
  printf '[]\n' > "$TEST_DOTFILES/vscode/keybindings.json"
  printf 'mikestead.dotenv\n' > "$TEST_DOTFILES/vscode/extensions.txt"

  sed -e "s|/Applications/Visual Studio Code.app|$VC_APP|" \
      -e "s|\$HOME/Library/Application Support/Code/User|$VC_USER_DIR|" \
      "$BATS_TEST_DIRNAME/../modules/vscode/doctor.sh" \
      > "$TEST_DOTFILES/modules/vscode/doctor.sh"
}

@test "vscode: base settings materialize generated settings without overlay" {
  mkdir -p "$VC_USER_DIR" "$TEST_DOTFILES/vscode" "$TEST_DOTFILES/modules/vscode"
  printf '{"editor.fontSize": 15, "mcpServers": {"base": {"command": "base"}}}\n' > "$TEST_DOTFILES/vscode/settings.json"
  printf '[]\n' > "$TEST_DOTFILES/vscode/keybindings.json"
  printf '\n' > "$TEST_DOTFILES/vscode/extensions.txt"
  sed -e "s|/Applications/Visual Studio Code.app|$VC_APP|" \
      -e "s|\$HOME/Library/Application Support/Code/User|$VC_USER_DIR|" \
      "$BATS_TEST_DIRNAME/../modules/vscode/doctor.sh" \
      > "$TEST_DOTFILES/modules/vscode/doctor.sh"
  FIX_MODE=true

  source "$TEST_DOTFILES/modules/vscode/doctor.sh"

  [ -f "$VC_LOCAL/settings.generated.json" ]
  grep -q '"base"' "$VC_LOCAL/settings.generated.json"
  [ "$(readlink "$VC_USER_DIR/settings.json")" = "$VC_LOCAL/settings.generated.json" ]
}

@test "vscode: generated settings preserve live MCP only" {
  _setup_vscode_installed
  mkdir -p "$VC_LOCAL"
  printf '{"editor.fontSize": 99, "mcpServers": {"live": {"command": "live"}}}\n' > "$VC_LOCAL/settings.generated.json"
  FIX_MODE=true

  source "$TEST_DOTFILES/modules/vscode/doctor.sh"

  grep -q '"live"' "$VC_LOCAL/settings.generated.json"
  grep -q '"editor.fontSize": 15' "$VC_LOCAL/settings.generated.json"
  ! grep -q '"editor.fontSize": 99' "$VC_LOCAL/settings.generated.json"
}

@test "vscode: repo settings leave MCP servers to agentbrew" {
  run python3 -c 'import json, re, sys; d = json.loads(re.sub(r"(?m)^\s*//.*$", "", open(sys.argv[1]).read())); sys.exit(1 if ("mcpServers" in d or "mcp" in d) else 0)' "$BATS_TEST_DIRNAME/../vscode/settings.json"
  [ "$status" -eq 0 ]
}

@test "vscode: falls back to the app-bundled code CLI when code is not on PATH" {
  _setup_vscode_installed
  rm -f "$VC_BIN"
  bundled="$VC_APP/Contents/Resources/app/bin/code"
  calls="$TEST_DIR/code-calls"
  mkdir -p "$(dirname "$bundled")"
  cat > "$bundled" <<STUB
#!/bin/bash
echo "\$*" >> "$calls"
[ "\$1" = "--list-extensions" ] && echo mikestead.dotenv
exit 0
STUB
  chmod +x "$bundled"
  # Drop every PATH entry that provides a code CLI.
  _path=""
  while IFS= read -r _d; do
    [ -n "$_d" ] && [ ! -x "$_d/code" ] && _path="${_path:+$_path:}$_d"
  done < <(printf '%s\n' "${PATH//:/$'\n'}")
  export PATH="$_path"
  FIX_MODE=true

  source "$TEST_DOTFILES/modules/vscode/doctor.sh"

  [ "$_VC_BIN" = "$bundled" ]
  grep -q -- '--list-extensions' "$calls"
  ! grep -q -- '--install-extension' "$calls"
}

_setup_extension_probe() {
  _setup_vscode_installed
  export VC_TEST_CALLS="$TEST_DIR/code-calls"
  export VC_TEST_INSTALLED="$TEST_DIR/installed-extensions"
  printf 'one.ext\ntwo.ext\nthree.ext\n' > "$TEST_DOTFILES/vscode/extensions.txt"
  printf 'one.ext\ntwo.ext\n' > "$VC_TEST_INSTALLED"
  cat > "$VC_BIN" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$VC_TEST_CALLS"
case "$1" in
  --list-extensions) cat "$VC_TEST_INSTALLED" ;;
  --install-extension) printf 'one.ext\ntwo.ext\n' > "$VC_TEST_INSTALLED" ;;
esac
STUB
}

@test "vscode: one listing retains every extension result and refreshes each module run" {
  _setup_extension_probe
  extension_results=""
  check() {
    case "$1" in
      vscode.extension.*)
        if eval "$3" >/dev/null 2>&1; then
          extension_results="$extension_results $1:pass"
        else
          extension_results="$extension_results $1:fail"
        fi ;;
    esac
  }
  source "$TEST_DOTFILES/modules/vscode/doctor.sh"
  printf "extension results: %s\n" "$extension_results"
  [ "$extension_results" = " vscode.extension.one_ext:pass vscode.extension.three_ext:fail vscode.extension.two_ext:pass" ]
  [ "$(grep -c '^--list-extensions$' "$VC_TEST_CALLS")" -eq 1 ]
  printf 'one.ext\ntwo.ext\nthree.ext\n' > "$VC_TEST_INSTALLED"
  extension_results=""
  source "$TEST_DOTFILES/modules/vscode/doctor.sh"
  [ "$extension_results" = " vscode.extension.one_ext:pass vscode.extension.three_ext:pass vscode.extension.two_ext:pass" ]
  [ "$(grep -c '^--list-extensions$' "$VC_TEST_CALLS")" -eq 2 ]
}

@test "vscode: fix mode sees extensions installed by an earlier extension pack" {
  _setup_extension_probe
  printf 'one.ext\ntwo.ext\n' > "$TEST_DOTFILES/vscode/extensions.txt"
  : > "$VC_TEST_INSTALLED"
  FIX_MODE=true
  source "$TEST_DOTFILES/modules/vscode/doctor.sh"
  [ "$(grep -c '^--install-extension' "$VC_TEST_CALLS")" -eq 1 ]
  [ "$(grep -c '^--list-extensions$' "$VC_TEST_CALLS")" -eq 2 ]
}

@test "vscode: override discovery does not launch the extension CLI" {
  _setup_extension_probe
  mkdir -p "$TEST_DOTFILES/bin"
  cp -R "$BATS_TEST_DIRNAME/../lib/." "$TEST_DOTFILES/lib/"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" "$TEST_DOTFILES/bin/dotfiles-doctor"
  run bash "$TEST_DOTFILES/bin/dotfiles-doctor" --skip vscode.extension.one_ext
  [ "$status" -eq 0 ]
  [ ! -e "$VC_TEST_CALLS" ]
  grep -qx vscode.extension.one_ext "$TEST_DOTFILES/.overrides"
}

@test "vscode: overridden extension checks do not launch the CLI" {
  _setup_extension_probe
  printf 'vscode.extension.one_ext\nvscode.extension.two_ext\nvscode.extension.three_ext\n' > "$OVERRIDES_FILE"
  source "$TEST_DOTFILES/modules/vscode/doctor.sh"
  [ ! -e "$VC_TEST_CALLS" ]
}
