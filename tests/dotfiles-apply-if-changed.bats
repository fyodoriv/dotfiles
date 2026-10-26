#!/usr/bin/env bats
# `dotfiles apply --if-changed` skips the full chezmoi apply and doctor when
# the source, chezmoi config, and plugins are unchanged since the last full
# apply and `chezmoi status` shows no drift (lib/apply-state.sh).

load test_helper

REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME" "$TEST_DIR/fakebin"
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
  unset XDG_STATE_HOME XDG_CONFIG_HOME DOTFILES_PLUGINS_LOCK

  REPO="$TEST_DIR/dotfiles"
  mkdir -p "$REPO/bin" "$REPO/lib"
  cp "$REPO_ROOT/bin/dotfiles" "$REPO/bin/"
  for f in colors lock apply-state; do cp "$REPO_ROOT/lib/$f.sh" "$REPO/lib/"; done
  printf '#!/bin/bash\necho doctor >> "%s/calls.log"\n' "$TEST_DIR" > "$REPO/bin/dotfiles-doctor"
  chmod +x "$REPO/bin/dotfiles" "$REPO/bin/dotfiles-doctor"
  echo "a = 1" > "$REPO/dot_testrc"
  git init --quiet "$REPO"
  git -C "$REPO" add -A
  git -C "$REPO" commit --quiet --no-verify -m "chore: initial"

  # Fake chezmoi: logs each call; FAKE_STATUS is the status output,
  # FAKE_STATUS_RC and FAKE_APPLY_RC set exit codes.
  cat > "$TEST_DIR/fakebin/chezmoi" <<FAKE
#!/bin/bash
echo "\$1 \${*:2}" >> "$TEST_DIR/calls.log"
case "\$1" in
  status) [ -n "\${FAKE_STATUS:-}" ] && printf '%s\n' "\$FAKE_STATUS"; exit "\${FAKE_STATUS_RC:-0}" ;;
  apply) exit "\${FAKE_APPLY_RC:-0}" ;;
esac
FAKE
  chmod +x "$TEST_DIR/fakebin/chezmoi"
  export PATH="$TEST_DIR/fakebin:$PATH"
  RECORD="$HOME/.local/state/dotfiles/last-apply"
}

teardown() {
  rm -rf "$TEST_DIR"
}

calls() {
  grep -c "^$1" "$TEST_DIR/calls.log" 2>/dev/null || true
}

@test "first --if-changed run applies fully and records the source" {
  run "$REPO/bin/dotfiles" apply --if-changed
  [ "$status" -eq 0 ]
  [[ "$output" == *"no record yet"* ]]
  [ "$(calls apply)" -eq 1 ]
  [ "$(calls doctor)" -eq 1 ]
  grep -q "^head $(git -C "$REPO" rev-parse HEAD)$" "$RECORD"
}

@test "second --if-changed run with nothing changed skips chezmoi apply and doctor" {
  "$REPO/bin/dotfiles" apply --if-changed
  run "$REPO/bin/dotfiles" apply --if-changed
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped chezmoi apply and doctor"* ]]
  [ "$(calls apply)" -eq 1 ]
  [ "$(calls doctor)" -eq 1 ]
  # The drift check leaves out the scripts that run on every apply.
  grep -q -- "^status --source $REPO --exclude=always" "$TEST_DIR/calls.log"
}

@test "a hand-edited file is reported and the full apply runs" {
  "$REPO/bin/dotfiles" apply --if-changed
  FAKE_STATUS="MM .testrc" run "$REPO/bin/dotfiles" apply --if-changed
  [ "$status" -eq 0 ]
  [[ "$output" == *"Drift since the last apply"* ]]
  [[ "$output" == *"MM .testrc"* ]]
  [ "$(calls apply)" -eq 2 ]
}

@test "a new source commit runs the full apply" {
  "$REPO/bin/dotfiles" apply --if-changed
  echo "a = 2" > "$REPO/dot_testrc"
  git -C "$REPO" commit --quiet --no-verify -am "chore: change"
  run "$REPO/bin/dotfiles" apply --if-changed
  [ "$status" -eq 0 ]
  [ "$(calls apply)" -eq 2 ]
  grep -q "^head $(git -C "$REPO" rev-parse HEAD)$" "$RECORD"
}

@test "an uncommitted source change runs the full apply and leaves no record" {
  "$REPO/bin/dotfiles" apply --if-changed
  echo "a = 3" > "$REPO/dot_testrc"
  run "$REPO/bin/dotfiles" apply --if-changed
  [ "$status" -eq 0 ]
  [ "$(calls apply)" -eq 2 ]
  [ ! -e "$RECORD" ]
}

@test "a changed chezmoi config or plugin lock runs the full apply" {
  "$REPO/bin/dotfiles" apply --if-changed
  mkdir -p "$HOME/.config/chezmoi" "$HOME/.config/dotfiles"
  echo "data: {profile: full}" > "$HOME/.config/chezmoi/chezmoi.yaml"
  "$REPO/bin/dotfiles" apply --if-changed
  [ "$(calls apply)" -eq 2 ]
  echo "plugins: {}" > "$HOME/.config/dotfiles/plugins.lock"
  "$REPO/bin/dotfiles" apply --if-changed
  [ "$(calls apply)" -eq 3 ]
  run "$REPO/bin/dotfiles" apply --if-changed
  [[ "$output" == *"skipped chezmoi apply"* ]]
  [ "$(calls apply)" -eq 3 ]
}

@test "a failed chezmoi status runs the full apply" {
  "$REPO/bin/dotfiles" apply --if-changed
  FAKE_STATUS_RC=1 run "$REPO/bin/dotfiles" apply --if-changed
  [ "$status" -eq 0 ]
  [[ "$output" == *"chezmoi status failed"* ]]
  [ "$(calls apply)" -eq 2 ]
}

@test "a failed apply leaves no record, so the next run applies again" {
  "$REPO/bin/dotfiles" apply --if-changed
  FAKE_APPLY_RC=1 run "$REPO/bin/dotfiles" apply
  [ "$status" -ne 0 ]
  [ ! -e "$RECORD" ]
  run "$REPO/bin/dotfiles" apply --if-changed
  [ "$(calls apply)" -eq 3 ]
}

@test "apply without --if-changed always runs the full apply" {
  "$REPO/bin/dotfiles" apply --if-changed
  run "$REPO/bin/dotfiles" apply
  [ "$status" -eq 0 ]
  [ "$(calls apply)" -eq 2 ]
  [ "$(calls doctor)" -eq 2 ]
}

@test "an apply with passthrough arguments keeps the record" {
  "$REPO/bin/dotfiles" apply --if-changed
  local before; before="$(cat "$RECORD")"
  run "$REPO/bin/dotfiles" apply "$HOME/.testrc"
  [ "$status" -eq 0 ]
  [ "$(cat "$RECORD")" = "$before" ]
}

@test "real chezmoi: an always-run script is not drift, a hand edit is" {
  command -v chezmoi >/dev/null 2>&1 || skip "chezmoi not installed"
  PATH="${PATH#"$TEST_DIR/fakebin:"}"
  local src="$TEST_DIR/src"
  mkdir -p "$src"
  echo "a = 1" > "$src/dot_testrc"
  printf '#!/bin/bash\ntrue\n' > "$src/run_after_hello.sh"
  git init --quiet "$src"
  git -C "$src" add -A
  git -C "$src" commit --quiet --no-verify -m "chore: initial"
  # shellcheck source=../lib/apply-state.sh
  source "$REPO_ROOT/lib/apply-state.sh"
  chezmoi apply --no-tty --source "$src" --destination "$HOME" </dev/null
  apply_state_record "$src"
  apply_state_current "$src"
  run apply_state_drift "$src"
  [ "$status" -eq 1 ]
  echo "a = 2" > "$HOME/.testrc"
  run apply_state_drift "$src"
  [ "$status" -eq 0 ]
  [[ "$output" == *".testrc"* ]]
}

@test "a full apply ends with a per-step timing summary (#338)" {
  run "$REPO/bin/dotfiles" apply
  [ "$status" -eq 0 ]
  [[ "$output" == *"Apply timing:"* ]]
  [[ "$output" =~ chezmoi\ apply\ [0-9]+s ]]
  [[ "$output" =~ doctor\ [0-9]+s ]]
}

@test "--pull adds the pull step to the timing summary (#338)" {
  git -C "$REPO" remote add origin "$REPO" 2>/dev/null || true
  git -C "$REPO" fetch --quiet origin
  git -C "$REPO" branch --quiet --set-upstream-to=origin/HEAD 2>/dev/null || git -C "$REPO" branch --quiet --set-upstream-to="origin/$(git -C "$REPO" branch --show-current)"
  run "$REPO/bin/dotfiles" apply --pull
  [ "$status" -eq 0 ]
  [[ "$output" =~ pull\ [0-9]+s ]]
}
