#!/usr/bin/env bats

load test_helper

setup() {
  REAL_CHEZMOI=$(command -v chezmoi)
  ROOT="$BATS_TEST_TMPDIR/sleep guidance"
  REPO="$ROOT/repo with space"
  HOME="$ROOT/home"
  mkdir -p "$REPO/bin" "$REPO/modules/fixture" "$REPO/launchagents" "$ROOT/bin" "$HOME"
  cp -R "$BATS_TEST_DIRNAME/../lib" "$REPO/lib"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" "$REPO/bin/dotfiles-doctor"
  cp "$BATS_TEST_DIRNAME/../launchagents/com.dotfiles.sleepwatcher.plist.tmpl" "$REPO/launchagents/"
  cp -R "$BATS_TEST_DIRNAME/../.chezmoitemplates" "$REPO/.chezmoitemplates"
  mkdir -p "$HOME/.config/chezmoi"
  printf '[data]\ndotfiles_dir = "apps/dotfiles"\n' > "$HOME/.config/chezmoi/chezmoi.toml"
  awk '/^if \[ "\$\{KEEP_AWAKE_TOOLS:-true\}" = "true" \]; then/ {copy=1} copy && /^check "resilience.wakeup_hook_exists"/ {exit} copy {print}' \
    "$BATS_TEST_DIRNAME/../modules/resilience/doctor.sh" > "$REPO/modules/fixture/doctor.sh"
  cat > "$ROOT/bin/chezmoi" <<'SH'
#!/bin/sh
case "$1" in
  source-path) printf '%s\n' "$REPO" ;;
  execute-template)
    if [ "${USE_REAL_CHEZMOI:-0}" = 1 ] && [ "${2:-}" = --source ]; then
      exec "$REAL_CHEZMOI" "$@"
    fi
    printf 'rendered fixture\n' ;;
  *) exit 1 ;;
esac
SH
  cat > "$ROOT/bin/launchctl" <<'SH'
#!/bin/sh
if [ "$1" = list ]; then
  [ "${SLEEPWATCHER_LOADED:-0}" = 1 ] && printf '0 0 com.dotfiles.sleepwatcher\n'
  exit 0
fi
printf 'unexpected service action\n' >> "$ROOT/service-actions"
exit 1
SH
  chmod +x "$ROOT/bin/chezmoi" "$ROOT/bin/launchctl"
  export HOME ROOT REPO REAL_CHEZMOI DOTFILES_DOCTOR_NOTIFY=0 DOTFILES_KEEP_AWAKE_TOOLS=true
  export PATH="$ROOT/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin"
  export XDG_STATE_HOME="$HOME/.local/state"
  /usr/bin/git init -q "$REPO"
}

@test "missing plist gives safe creation steps without running them" {
  quoted=$(printf '%q' "$REPO")
  expected="chezmoi execute-template --source $quoted < $quoted/launchagents/com.dotfiles.sleepwatcher.plist.tmpl"
  run bash "$REPO/bin/dotfiles-doctor" --module fixture --json
  [ "$status" -ne 0 ]
  printf '%s' "$output" | jq -e --arg expected "$expected" 'any(.[]; .id == "resilience.sleepwatcher_loaded" and .status == "fail" and (has("fix") | not) and (.message | contains("You:")) and (.message | contains("missing")) and (.message | contains($expected)) and (.message | contains("launchctl bootstrap")))' >/dev/null
  run bash "$REPO/bin/dotfiles-doctor" --module fixture
  [ "$status" -ne 0 ]
  [[ "$output" == *"$expected"* && "$output" == *"You:"* ]]
  run bash "$REPO/bin/dotfiles-doctor" --module fixture --fix --json
  [ "$status" -ne 0 ]
  [ ! -e "$HOME/Library/LaunchAgents/com.dotfiles.sleepwatcher.plist" ]
  [ ! -e "$ROOT/service-actions" ]
}

@test "an existing unloaded plist gives load guidance without replacing it" {
  mkdir -p "$HOME/Library/LaunchAgents"
  printf 'keep fixture\n' > "$HOME/Library/LaunchAgents/com.dotfiles.sleepwatcher.plist"
  run bash "$REPO/bin/dotfiles-doctor" --module fixture --fix --json
  [ "$status" -ne 0 ]
  printf '%s' "$output" | jq -e 'any(.[]; .id == "resilience.sleepwatcher_loaded" and .status == "fail" and (has("fix") | not) and (.message | contains("You:")) and (.message | contains("launchctl bootstrap")) and (.message | contains("execute-template") | not))' >/dev/null
  [ "$(cat "$HOME/Library/LaunchAgents/com.dotfiles.sleepwatcher.plist")" = 'keep fixture' ]
  [ ! -e "$ROOT/service-actions" ]
}

@test "the offered creation command renders the template and never replaces a file" {
  run bash "$REPO/bin/dotfiles-doctor" --module fixture --json
  [ "$status" -ne 0 ]
  message=$(printf '%s' "$output" | jq -r '.[] | select(.id == "resilience.sleepwatcher_loaded") | .message')
  command=${message#*In Terminal, run }
  command=${command%, then run *}
  run bash -c "$command"
  [ "$status" -eq 0 ]
  plist="$HOME/Library/LaunchAgents/com.dotfiles.sleepwatcher.plist"
  [ "$(cat "$plist")" = 'rendered fixture' ]
  printf 'keep existing\n' > "$plist"
  run bash -c "$command"
  [ "$status" -ne 0 ]
  [ "$(cat "$plist")" = 'keep existing' ]
  [ ! -e "$ROOT/service-actions" ]
}

@test "a loaded sleepwatcher remains a passing check" {
  export SLEEPWATCHER_LOADED=1
  run bash "$REPO/bin/dotfiles-doctor" --module fixture --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e 'any(.[]; .id == "resilience.sleepwatcher_loaded" and .status == "pass")' >/dev/null
}

@test "the creation command renders the real plist from the checked source" {
  export USE_REAL_CHEZMOI=1
  run bash "$REPO/bin/dotfiles-doctor" --module fixture --json
  [ "$status" -ne 0 ]
  message=$(printf '%s' "$output" | jq -r '.[] | select(.id == "resilience.sleepwatcher_loaded") | .message')
  command=${message#*In Terminal, run }
  command=${command%, then run *}
  run bash -c "$command"
  [ "$status" -eq 0 ]
  plist="$HOME/Library/LaunchAgents/com.dotfiles.sleepwatcher.plist"
  /usr/bin/plutil -lint "$plist"
  grep -q '<string>com.dotfiles.sleepwatcher</string>' "$plist"
  [ ! -e "$ROOT/service-actions" ]
}
