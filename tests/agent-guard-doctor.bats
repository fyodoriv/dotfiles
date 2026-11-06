#!/usr/bin/env bats

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home" REPO="$TEST_DIR/repo" DOTFILES_DOCTOR_NOTIFY=0
  mkdir -p "$HOME/.claude" "$REPO/bin" "$REPO/modules" "$REPO/.chezmoiscripts" "$TEST_DIR/bin"
  cp -R "$BATS_TEST_DIRNAME/../lib" "$REPO/lib"
  cp -R "$BATS_TEST_DIRNAME/../modules/security" "$REPO/modules/security"
  cp -R "$BATS_TEST_DIRNAME/../agent-hooks" "$REPO/agent-hooks"
  cp "$BATS_TEST_DIRNAME/../bin/dotfiles-doctor" "$REPO/bin/dotfiles-doctor"
  cp "$BATS_TEST_DIRNAME/../.chezmoiscripts/run_after_agent-hooks.sh" "$REPO/.chezmoiscripts/run_after_agent-hooks.sh"
  cat > "$TEST_DIR/bin/chezmoi" <<'SH'
#!/bin/sh
case "$1" in source-path) printf '%s\n' "$REPO" ;; execute-template) printf 'false\n' ;; *) exit 1 ;; esac
SH
  chmod +x "$TEST_DIR/bin/chezmoi"
  export PATH="$TEST_DIR/bin:$PATH" CHEZMOI_SOURCE_DIR="$REPO"
  bash "$REPO/.chezmoiscripts/run_after_agent-hooks.sh" >/dev/null
  printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"~/.config/dotfiles/hooks/block-dangerous-git.sh"}]}]}}' > "$HOME/.claude/settings.json"
  HOOK="$HOME/.config/dotfiles/hooks/block-dangerous-git.sh"
  HELPER="$HOME/.config/dotfiles/hooks/plain-document-write.jq"
}

teardown() { rm -rf "$TEST_DIR"; }

doctor_state() {
  bash "$REPO/bin/dotfiles-doctor" --module security --json | jq -r '.[] | select(.id == "security.agent_git_guard_parser") | .status'
}

guard_status() {
  local payload
  payload="$(jq -n --arg command "$1" '{tool_input:{command:$command}}')"
  printf '%s' "$payload" | "$HOOK" >/dev/null 2>&1
}

@test "doctor detects a missing deployed parser and the installer restores it" {
  rm "$HELPER"
  guard_status 'git status'
  run guard_status 'git reset --hard'
  [ "$status" -eq 2 ]
  run guard_status $'cat <<\x27NOTE\x27\ngit branch -D prose\nNOTE\n'
  [ "$status" -eq 2 ]
  [ "$(doctor_state)" = warn ]
  local entry
  entry="$(bash "$REPO/bin/dotfiles-doctor" --module security --json | jq -c '.[] | select(.id == "security.agent_git_guard_parser")')"
  [[ "$(printf '%s' "$entry" | jq -r '.fix')" == *run_after_agent-hooks.sh* ]]
  bash "$REPO/.chezmoiscripts/run_after_agent-hooks.sh" >/dev/null
  [ "$(doctor_state)" = pass ]
  guard_status 'git status'
  run guard_status 'git reset --hard'
  [ "$status" -eq 2 ]
  guard_status $'cat <<\x27NOTE\x27\ngit branch -D prose\nNOTE\n'
}

@test "doctor detects a broken deployed guard link" {
  rm "$HOOK"
  ln -s "$TEST_DIR/missing-guard" "$HOOK"
  [ "$(doctor_state)" = warn ]
  bash "$REPO/.chezmoiscripts/run_after_agent-hooks.sh" >/dev/null
  [ "$(doctor_state)" = pass ]
}

@test "doctor does not claim an unsupported hook command is registered" {
  printf '%s\n' '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash ~/.config/dotfiles/hooks/block-dangerous-git.sh"}]}]}}' > "$HOME/.claude/settings.json"
  [ "$(doctor_state)" = warn ]
}

@test "doctor detects a broken deployed parser link" {
  rm "$HELPER"
  ln -s "$TEST_DIR/missing" "$HELPER"
  [ "$(doctor_state)" = warn ]
  bash "$REPO/.chezmoiscripts/run_after_agent-hooks.sh" >/dev/null
  [ "$(doctor_state)" = pass ]
}

@test "doctor warns when all hooks are disabled" {
  jq '.disableAllHooks = true' "$HOME/.claude/settings.json" > "$TEST_DIR/settings.json"
  mv "$TEST_DIR/settings.json" "$HOME/.claude/settings.json"
  [ "$(doctor_state)" = warn ]
}

@test "doctor warns when the managed guard is substituted" {
  rm "$HOOK"
  printf '#!/bin/sh\nexit 0\n' > "$HOOK"
  chmod +x "$HOOK"
  [ "$(doctor_state)" = warn ]
}

@test "doctor warns when the managed parser is substituted" {
  rm "$HELPER"
  printf '.\n' > "$HELPER"
  [ "$(doctor_state)" = warn ]
}

@test "doctor warns when a matching hook is conditional" {
  jq '.hooks.PreToolUse[0].hooks[0].if = "false"' "$HOME/.claude/settings.json" > "$TEST_DIR/settings.json"
  mv "$TEST_DIR/settings.json" "$HOME/.claude/settings.json"
  [ "$(doctor_state)" = warn ]
}
