#!/usr/bin/env bats
# Typed extension points for company plugins (issue #145, step 6).

load test_helper

REPO_ROOT="$BATS_TEST_DIRNAME/.."
CLI="$BATS_TEST_DIRNAME/../bin/dotfiles-plugin"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export DOTFILES_PLUGINS_V2=1
  export MARKER="$TEST_DIR/ran"
  unset EXTRA_OVERLAY_ROOT DOTFILES_PLUGINS_LOCK DOTFILES_PLUGINS_HOME
  mkdir -p "$HOME" "$TEST_DIR/stub"
  printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/stub/chezmoi"
  printf '#!/bin/sh\necho "brew $*" >> "%s"\n[ -z "${BREW_FAIL:-}" ]\n' "$MARKER" > "$TEST_DIR/stub/brew"
  printf '#!/bin/sh\necho "launchctl $*" >> "%s"\n' "$MARKER" > "$TEST_DIR/stub/launchctl"
  export DOTFILES_LAUNCHAGENTS_DIR="$TEST_DIR/LaunchAgents" XDG_STATE_HOME="$HOME/.local/state"
  chmod +x "$TEST_DIR/stub/"*
  export PATH="$TEST_DIR/stub:$PATH"
  PLUGIN="$TEST_DIR/dotfiles-acme"
  mkdir -p "$PLUGIN"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# install_plugin <capabilities yaml> <contributes yaml>
install_plugin() {
  printf 'schema: 1\nname: acme\nversion: 1.0.0\ncapabilities:\n%s\ncontributes:\n%s\n' "$1" "$2" \
    > "$PLUGIN/dotfiles-plugin.yaml"
  bash "$CLI" add --dev "$PLUGIN" --yes >/dev/null
}

ext() {
  bash -c 'for f in plugin plugin-capabilities plugin-extensions; do source "$1/lib/$f.sh"; done; shift; "$@"' \
    _ "$REPO_ROOT" "$@"
}

@test "6a: a declared plugin Brewfile gets its own brew bundle pass" {
  printf 'tap "acme/private"\ncask "acme-app"\nbrew "jq"\n' > "$PLUGIN/Brewfile"
  install_plugin '  brew: {taps: [acme/private], casks: true}' '  brewfile: Brewfile'
  run ext plugin_brew_pass
  [ "$status" -eq 0 ]
  grep -qE "^brew bundle --no-upgrade --file=.*/dotfiles-acme/Brewfile$" "$MARKER"
}

@test "6a: an undeclared tap refuses the plugin Brewfile" {
  printf 'tap "other/tap"\n' > "$PLUGIN/Brewfile"
  install_plugin '  brew: {taps: [acme/private]}' '  brewfile: Brewfile'
  run ext plugin_brew_pass
  [ "$status" -ne 0 ]
  [[ "$output" == *"capability not declared: brew_tap other/tap (plugin acme)"* ]]
  [ ! -f "$MARKER" ]
}

@test "6a: casks need capabilities.brew.casks" {
  printf 'cask "acme-app"\n' > "$PLUGIN/Brewfile"
  install_plugin '  sudo: false' '  brewfile: Brewfile'
  run ext plugin_brew_pass
  [ "$status" -ne 0 ]
  [[ "$output" == *"capability not declared: brew_cask"* ]]
}

@test "6a: a failed bundle is reported as unreachable, not a silent pass" {
  printf 'brew "jq"\n' > "$PLUGIN/Brewfile"
  install_plugin '  sudo: false' '  brewfile: Brewfile'
  BREW_FAIL=1 run ext plugin_brew_pass
  [ "$status" -ne 0 ]
  [[ "$output" == *"unreachable (plugin acme)"* ]]
}

@test "6a: a plugin that fails verification is skipped" {
  printf 'brew "jq"\n' > "$PLUGIN/Brewfile"
  install_plugin '  sudo: false' '  brewfile: Brewfile'
  printf '  sudo: true\n' >> "$PLUGIN/dotfiles-plugin.yaml"
  sed -i.bak '/^  sudo: false$/d' "$PLUGIN/dotfiles-plugin.yaml" && rm -f "$PLUGIN/dotfiles-plugin.yaml.bak"
  run ext plugin_brew_pass
  [[ "$output" == *"skipped plugin acme"* ]]
  [ ! -f "$MARKER" ]
}

plist() {
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$1</string>
<key>ProgramArguments</key><array><string>@PLUGIN_DIR@/bin/run</string><string>@HOME@</string></array>
</dict></plist>
PLIST
}

@test "6b: a declared LaunchAgent template is rendered, installed and loaded" {
  mkdir -p "$PLUGIN/launchagents"
  plist com.acme.sync > "$PLUGIN/launchagents/sync.plist"
  install_plugin '  launchagents: [com.acme.*]' '  launchagents: launchagents'
  run ext plugin_launchagents_pass
  [ "$status" -eq 0 ]
  dest="$DOTFILES_LAUNCHAGENTS_DIR/com.acme.sync.plist"
  [ -f "$dest" ]
  grep -q "<string>$HOME</string>" "$dest"
  grep -q "dotfiles-acme/bin/run" "$dest"
  ! grep -q '@HOME@\|@PLUGIN_DIR@' "$dest"
  grep -q "launchctl bootstrap gui/" "$MARKER"
}

@test "6b: an undeclared Label is refused and not installed" {
  mkdir -p "$PLUGIN/launchagents"
  plist com.other.agent > "$PLUGIN/launchagents/x.plist"
  install_plugin '  launchagents: [com.acme.*]' '  launchagents: launchagents'
  run ext plugin_launchagents_pass
  [ "$status" -ne 0 ]
  [[ "$output" == *"capability not declared: launchagents com.other.agent (plugin acme)"* ]]
  [ ! -e "$DOTFILES_LAUNCHAGENTS_DIR/com.other.agent.plist" ]
}

@test "6b: an unchanged agent is not reloaded" {
  mkdir -p "$PLUGIN/launchagents"
  plist com.acme.sync > "$PLUGIN/launchagents/sync.plist"
  install_plugin '  launchagents: [com.acme.*]' '  launchagents: launchagents'
  ext plugin_launchagents_pass
  rm -f "$MARKER"
  run ext plugin_launchagents_pass
  [ "$status" -eq 0 ]
  [ ! -f "$MARKER" ]
}

@test "6b: plugin remove unloads and deletes its LaunchAgents" {
  mkdir -p "$PLUGIN/launchagents"
  plist com.acme.sync > "$PLUGIN/launchagents/sync.plist"
  install_plugin '  launchagents: [com.acme.*]' '  launchagents: launchagents'
  ext plugin_launchagents_pass
  run bash "$CLI" remove acme
  [ "$status" -eq 0 ]
  [ ! -e "$DOTFILES_LAUNCHAGENTS_DIR/com.acme.sync.plist" ]
  grep -q "launchctl bootout gui/.*/com.acme.sync" "$MARKER"
}

@test "6d: a declared shell fragment is sourced by the generated loader" {
  mkdir -p "$PLUGIN/shell"
  printf 'export ACME_FRAGMENT=loaded\n' > "$PLUGIN/shell/zshrc.zsh"
  install_plugin '  shell_fragment: true' '  shell: shell/zshrc.zsh'
  run ext plugin_shell_pass
  [ "$status" -eq 0 ]
  loader="$XDG_STATE_HOME/dotfiles/plugin-shell.zsh"
  run zsh -fc "source '$loader'; print -r -- \$ACME_FRAGMENT"
  [ "$output" = loaded ]
}

@test "6d: an undeclared shell fragment is left out" {
  mkdir -p "$PLUGIN/shell"
  printf 'touch "%s"\n' "$MARKER" > "$PLUGIN/shell/zshrc.zsh"
  install_plugin '  sudo: false' '  shell: shell/zshrc.zsh'
  run ext plugin_shell_pass
  [ "$status" -ne 0 ]
  [[ "$output" == *"capability not declared: shell_fragment (plugin acme)"* ]]
  ! grep -q zshrc.zsh "$XDG_STATE_HOME/dotfiles/plugin-shell.zsh"
}

@test "6d: plugin add and remove refresh the loader" {
  mkdir -p "$PLUGIN/shell"
  printf ':\n' > "$PLUGIN/shell/zshrc.zsh"
  install_plugin '  shell_fragment: true' '  shell: shell/zshrc.zsh'
  grep -q 'shell/zshrc.zsh' "$XDG_STATE_HOME/dotfiles/plugin-shell.zsh"
  bash "$CLI" remove acme
  ! grep -q 'shell/zshrc.zsh' "$XDG_STATE_HOME/dotfiles/plugin-shell.zsh"
}

@test "6d: home/zshrc loads plugin fragments before ~/.zshrc.local" {
  run awk '/plugin-shell.zsh/ && !p { p = NR } /source ~\/.zshrc.local/ && !l && p { l = NR } END { exit !(p && l && p < l) }' \
    "$REPO_ROOT/home/zshrc"
  [ "$status" -eq 0 ]
}

@test "6c: settings merge default < plugin < user < force, and reports conflicts" {
  mkdir -p "$PLUGIN/settings" "$XDG_CONFIG_HOME/dotfiles/settings"
  printf '{"a": 1, "b": {"x": 1, "y": 1}, "c": 1, "d": 1}\n' > "$TEST_DIR/base.json"
  printf '{"b": {"x": 2}, "c": 2, "d": 2, "_force": {"d": 9}}\n' > "$PLUGIN/settings/vscode.json"
  printf '{"c": 3, "d": 3}\n' > "$XDG_CONFIG_HOME/dotfiles/settings/vscode.user.json"
  install_plugin '  sudo: false' '  settings: {vscode: settings/vscode.json}'
  run ext plugin_settings_merge vscode "$TEST_DIR/base.json" "$TEST_DIR/out.json"
  [ "$status" -eq 0 ]
  [ "$(jq -c . "$TEST_DIR/out.json")" = '{"a":1,"b":{"x":2,"y":1},"c":3,"d":9}' ]
  [[ "$output" == *"settings conflict (vscode): c: plugin acme vs user"* ]]
  [[ "$output" == *"settings conflict (vscode): d: plugin acme vs user"* ]]
  [[ "$output" != *"conflict (vscode): b.x"* ]]
}

@test "6c: with no plugins the core settings pass through unchanged" {
  printf '{"a": 1}\n' > "$TEST_DIR/base.json"
  run ext plugin_settings_merge vscode "$TEST_DIR/base.json" "$TEST_DIR/out.json"
  [ "$status" -eq 0 ]
  [ "$(jq -c . "$TEST_DIR/out.json")" = '{"a":1}' ]
}

@test "6c: invalid plugin settings JSON fails without writing" {
  mkdir -p "$PLUGIN/settings"
  printf '{"a": 1}\n' > "$TEST_DIR/base.json"
  printf '{not json\n' > "$PLUGIN/settings/vscode.json"
  install_plugin '  sudo: false' '  settings: {vscode: settings/vscode.json}'
  run ext plugin_settings_merge vscode "$TEST_DIR/base.json" "$TEST_DIR/out.json"
  [ "$status" -ne 0 ]
  [ ! -f "$TEST_DIR/out.json" ]
}

# Collects results the way bin/dotfiles-doctor's check() would.
doctor_run() {
  bash -c '
    for f in plugin plugin-capabilities plugin-extensions; do source "$1/lib/$f.sh"; done
    check() { printf "%s|%s|%s\n" "$1" "$3" "$2"; }
    while IFS=$'"'"'\t'"'"' read -r n r m; do plugin_doctor_run "$n" "$r" "$m" "$2"; done < <(plugin_doctor_modules all)
    echo "IN_PROCESS=${ACME_SET_ME:-unset}"
  ' _ "$REPO_ROOT" "$1"
}

@test "6e: plugin doctor modules run in a child with a cleaned env, ids namespaced" {
  mkdir -p "$PLUGIN/doctor/acme"
  cat > "$PLUGIN/doctor/acme/doctor.sh" <<'MOD'
ACME_SET_ME=leaked
check "acme.clean_env" "no inherited token" '[ -z "${SECRET_TOKEN:-}" ] && [ -z "${DOTFILES_DIR:-}" ]' ""
check "acme.cwd" "runs in plugin root" '[ -f dotfiles-plugin.yaml ]' ""
check "acme.bad" "a failing check" 'false' ""
echo "noise that is not a result"
MOD
  install_plugin '  sudo: false' '  doctor_modules: doctor'
  SECRET_TOKEN=s3cr3t DOTFILES_DIR=/x run doctor_run run
  echo "$output"
  [[ "$output" == *"acme/acme.clean_env|true|"* ]]
  [[ "$output" == *"acme/acme.cwd|true|"* ]]
  [[ "$output" == *"acme/acme.bad|false|a failing check"* ]]
  [[ "$output" == *"IN_PROCESS=unset"* ]]
  [[ "$output" != *"noise"* ]]
}

@test "6e: a module that hangs is stopped and reported" {
  mkdir -p "$PLUGIN/doctor/slow"
  printf 'sleep 30\n' > "$PLUGIN/doctor/slow/doctor.sh"
  install_plugin '  sudo: false' '  doctor_modules: doctor'
  DOTFILES_PLUGIN_TIMEOUT=1 run doctor_run run
  [[ "$output" == *"acme/slow.ran|false|"*"142 = timeout"* ]]
}

@test "6e: list mode names checks without running them" {
  mkdir -p "$PLUGIN/doctor/acme"
  printf 'check "acme.one" "one" "touch %s" ""\n' "$MARKER" > "$PLUGIN/doctor/acme/doctor.sh"
  install_plugin '  sudo: false' '  doctor_modules: doctor'
  run doctor_run list
  [[ "$output" == *"acme/acme.one|true|one"* ]]
  [ ! -f "$MARKER" ]
}

@test "6e: plugin validate scripts report through pass/fail/warn" {
  mkdir -p "$PLUGIN/validate"
  printf 'pass "ok one"\nfail "bad one"\naudit_warn "careful"\n' > "$PLUGIN/validate/a.sh"
  printf 'exit 4\n' > "$PLUGIN/validate/b.sh"
  install_plugin '  sudo: false' '  validate: validate'
  run bash -c '
    for f in plugin plugin-capabilities plugin-extensions; do source "$1/lib/$f.sh"; done
    pass() { echo "P:$*"; }; fail() { echo "F:$*"; }; audit_warn() { echo "W:$*"; }
    plugin_validate_run' _ "$REPO_ROOT"
  [[ "$output" == *"P:acme: ok one"* ]]
  [[ "$output" == *"F:acme: bad one"* ]]
  [[ "$output" == *"W:acme: careful"* ]]
  [[ "$output" == *"F:plugin acme validate script b.sh failed (exit 4"* ]]
}

# install_named <name> <options yaml>: a second dev plugin with options.
install_named() {
  local dir="$TEST_DIR/dotfiles-$1"
  mkdir -p "$dir"
  printf 'schema: 1\nname: %s\nversion: 1.0.0\ncontributes:\n  options:\n%s\n' "$1" "$2" > "$dir/dotfiles-plugin.yaml"
  bash "$CLI" add --dev "$dir" --yes
}

@test "7: an unknown or mistyped option is refused at add" {
  run install_named acme '    chrome.unknown_knob: true'
  [ "$status" -ne 0 ]
  [[ "$output" == *"option chrome.unknown_knob: unknown"* ]]
  run install_named acme '    mas.skip_ids: 123'
  [ "$status" -ne 0 ]
  [[ "$output" == *"option mas.skip_ids: must be a list"* ]]
}

@test "7: booleans use the last plugin in lock order, lists merge" {
  install_named aaa $'    chrome.restore_session: true\n    brew.skip: [foo]'
  install_named bbb $'    chrome.restore_session: false\n    brew.skip: [bar, foo]'
  run ext plugin_option chrome.restore_session
  [ "$output" = false ]
  run ext plugin_option brew.skip
  [ "$output" = $'foo\nbar' ]
  run ext plugin_option spotlight.exclude_worktrees
  [ "$output" = true ]
  run bash "$CLI" options
  [[ "$output" == *"chrome.restore_session = false  (set by: aaa bbb)  conflict"* ]]
  [[ "$output" == *"brew.skip = foo,bar  (set by: aaa bbb)"* ]]
}

@test "7: mas.skip_ids from a plugin keeps dotfiles-mas-upgrade away from that app" {
  install_named acme '    mas.skip_ids: ["123456789"]'
  cat > "$TEST_DIR/stub/mas" <<'STUB'
#!/bin/bash
case "$1" in
  outdated) echo "123456789 Managed (1.0 -> 1.1)" ;;
  upgrade) echo "upgrade $2" >> "$MARKER" ;;
esac
STUB
  chmod +x "$TEST_DIR/stub/mas"
  DOTFILES_MAS_SKIP_IDS="" MAS_BIN="$TEST_DIR/stub/mas" run bash "$REPO_ROOT/bin/dotfiles-mas-upgrade"
  [ "$status" -eq 0 ]
  [ ! -f "$MARKER" ]
}

@test "7: brew.skip from a plugin removes the entry from the core Brewfile" {
  install_named acme '    brew.skip: [blocked-cask]'
  printf 'brew "jq"\ncask "blocked-cask"\n' > "$TEST_DIR/Brewfile"
  awk '/^# Company plugins add names through the core option brew.skip/ { c = 1 } c { print } c && /^fi$/ { exit }' \
    "$REPO_ROOT/.chezmoiscripts/run_onchange_brew.sh.tmpl" |
    sed "s|{{ .chezmoi.sourceDir }}|$REPO_ROOT|g" > "$TEST_DIR/block.sh"
  RENDERED="$TEST_DIR/Brewfile" run bash -c 'RENDERED="$1"; source "$2"' _ "$TEST_DIR/Brewfile" "$TEST_DIR/block.sh"
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_DIR/Brewfile")" = 'brew "jq"' ]
}

render_chrome_plist() {
  sed "s|{{ .chezmoi.homeDir }}|$HOME|g" "$REPO_ROOT/launchagents/com.dotfiles.agent-browser-chrome.plist.tmpl" > "$1"
}

@test "7b: chrome options default leave the purpose Chrome headless" {
  render_chrome_plist "$TEST_DIR/c.plist"
  run bash -c 'source "$1/lib/chrome-purpose-options.sh"; chrome_purpose_apply_options "$2" false false' _ "$REPO_ROOT" "$TEST_DIR/c.plist"
  [ "$status" -eq 0 ]
  grep -q -- '--headless=new' "$TEST_DIR/c.plist"
  ! grep -q -- '--restore-last-session' "$TEST_DIR/c.plist"
}

@test "7b: chrome.purpose_headed and chrome.restore_session change the plist, idempotently" {
  render_chrome_plist "$TEST_DIR/c.plist"
  for _ in 1 2; do
    bash -c 'source "$1/lib/chrome-purpose-options.sh"; chrome_purpose_apply_options "$2" true true' _ "$REPO_ROOT" "$TEST_DIR/c.plist"
  done
  ! grep -q -- '--headless=new' "$TEST_DIR/c.plist"
  [ "$(grep -c -- '--restore-last-session' "$TEST_DIR/c.plist")" -eq 1 ]
  plutil -lint "$TEST_DIR/c.plist"
  [ "$(plutil -extract ProgramArguments.1 raw -o - "$TEST_DIR/c.plist")" = --remote-debugging-port=9223 ]
}

@test "7b: the launchagents script applies the options to the purpose Chrome" {
  grep -q 'chrome_purpose_apply_options "\$dst.tmp" "\$(_core_option chrome.purpose_headed)"' \
    "$REPO_ROOT/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
}

# Sources only modules/workflow/doctor.sh with stub check/skipped functions.
workflow_list() {
  mkdir -p "$HOME/apps/tooling"
  DOTFILES_REPOS_DIR="$HOME/apps" bash -c '
    for f in plugin plugin-capabilities plugin-extensions; do source "$1/lib/$f.sh"; done
    check() { echo "CHECK $1"; }; check_advisory() { echo "CHECK $1"; }
    skipped() { echo "SKIP $*"; }; pass() { :; }; fail() { :; }; audit_warn() { :; }
    DOTFILES_DIR="$1"; DOTFILES_MODULE_DIR="$1"
    source "$1/modules/workflow/doctor.sh"' _ "$REPO_ROOT" < /dev/null 2>/dev/null
}

@test "7c: spotlight.exclude_worktrees defaults on and a plugin can turn it off" {
  run workflow_list
  [[ "$output" == *"CHECK spotlight.agent_worktrees"* ]]
  install_named acme '    spotlight.exclude_worktrees: false'
  run workflow_list
  [[ "$output" != *"CHECK spotlight.agent_worktrees"* ]]
  [[ "$output" == *"SKIP agent worktrees left in the Spotlight index"* ]]
}

@test "7d: blocked_software lists installed apps, casks and formulae" {
  mkdir -p "$TEST_DIR/Apps/Bad.app"
  printf 'apps: [Bad.app, Fine.app]\ncasks: [bad-cask, ok-cask]\nformulae: [bad-f]\n' > "$TEST_DIR/blocked.yaml"
  cat > "$TEST_DIR/stub/brew" <<'STUB'
#!/bin/sh
case "$*" in
  "list --cask -1") echo bad-cask ;;
  "list --formula -1") printf 'jq\nbad-f\n' ;;
esac
STUB
  chmod +x "$TEST_DIR/stub/brew"
  BLOCKED_SOFTWARE_APPS_DIR="$TEST_DIR/Apps" run bash -c 'source "$1/lib/blocked-software.sh"; blocked_software_found "$2"' \
    _ "$REPO_ROOT" "$TEST_DIR/blocked.yaml"
  [ "$status" -eq 0 ]
  [ "$output" = $'app Bad.app\ncask bad-cask\nformula bad-f' ]
}

@test "7d: the plugins doctor adds a blocked_software check for a verified plugin" {
  printf 'apps: [Nothing.app]\n' > "$PLUGIN/blocked.yaml"
  install_plugin '  sudo: false' '  blocked_software: blocked.yaml'
  run bash -c '
    check() { echo "CHECK $1"; eval "$3" && echo PASS || echo FAIL; }; audit_warn() { :; }
    DOTFILES_DIR="$1"; source "$1/modules/plugins/doctor.sh"' _ "$REPO_ROOT"
  [[ "$output" == *"CHECK plugins.acme.blocked_software"* ]]
  [[ "$output" == *"PASS"* ]]
}
