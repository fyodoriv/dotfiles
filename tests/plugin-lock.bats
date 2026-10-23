#!/usr/bin/env bats
# `dotfiles plugin` commands that change plugin state take ~/.dotfiles.lock,
# the lock apply, sync, doctor, and upgrade share, so a manual command cannot
# race the Sunday `dotfiles upgrade`. A child of the lock holder (the
# upgrade's own `dotfiles plugin update`) inherits the lock through
# DOTFILES_LOCK_HOLDER instead of waiting on its parent.
# Fixture: a local plugin repo with SSH-signed tags; no network.

load test_helper

CLI="$BATS_TEST_DIRNAME/../bin/dotfiles-plugin"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  unset DOTFILES_PLUGINS_LOCK DOTFILES_PLUGINS_HOME AGENT_PLUGINS_ALLOWED_SIGNERS DOTFILES_LOCK DOTFILES_LOCK_HOLDER
  export DOTFILES_PLUGIN_LOCK_WAIT=0
  mkdir -p "$HOME" "$TEST_DIR/stub"
  printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/stub/chezmoi"
  chmod +x "$TEST_DIR/stub/chezmoi"
  export PATH="$TEST_DIR/stub:$PATH"
  ssh-keygen -q -t ed25519 -N '' -C release -f "$TEST_DIR/key"
  KEY="$(cat "$TEST_DIR/key.pub")"
  SRC="$TEST_DIR/dotfiles-acme"
  PLOCK="$XDG_CONFIG_HOME/dotfiles/plugins.lock"
  git init -q "$SRC"
  printf 'schema: 1\nname: acme\nversion: 1.0.0\ncapabilities:\n  sudo: false\ncontributes:\n  doctor_modules: modules/\n' > "$SRC/dotfiles-plugin.yaml"
  mkdir -p "$SRC/modules/acme"
  echo 'check "acme.one" "acme" "true" ""' > "$SRC/modules/acme/doctor.sh"
  gitc add -A
  gitc commit -qm init
  sign v1.0.0
  bash "$CLI" add "$SRC@v1.0.0" --signer "$KEY" --yes >/dev/null
  HOLDER=""
}

teardown() {
  [ -z "$HOLDER" ] || kill "$HOLDER" 2>/dev/null || true
  chmod -R u+w "$TEST_DIR" 2>/dev/null || true
  rm -rf "$TEST_DIR"
}

gitc() { git -C "$SRC" -c user.name=t -c user.email=t@example.com -c core.hooksPath=/dev/null "$@"; }
sign() { git -C "$SRC" -c gpg.format=ssh -c user.signingkey="$TEST_DIR/key.pub" -c user.name=t -c user.email=t@example.com tag -s "$1" -m "$1"; }

# hold_lock: a live scratch process holds ~/.dotfiles.lock as "upgrade".
hold_lock() {
  sleep 60 &
  HOLDER=$!
  printf '%s\nupgrade\n' "$HOLDER" > "$HOME/.dotfiles.lock"
}

@test "every plugin command that changes state refuses while another dotfiles command holds the lock" {
  sed -i.bak 's/^version: .*/version: 1.1.0/' "$SRC/dotfiles-plugin.yaml" && rm -f "$SRC/dotfiles-plugin.yaml.bak"
  gitc commit -qam v1.1.0
  sign v1.1.0
  hold_lock
  before="$(cat "$PLOCK")"
  for args in "update acme --yes" "remove acme --yes" "trust acme --signer $KEY --yes" "add $SRC@v1.1.0 --signer $KEY --yes"; do
    # shellcheck disable=SC2086
    run bash "$CLI" $args
    echo "$args -> $status: $output"
    [ "$status" -ne 0 ]
    [[ "$output" == *"upgrade"*"$HOLDER"* ]]
  done
  [ "$(cat "$PLOCK")" = "$before" ]
  [ -d "$XDG_DATA_HOME/dotfiles/plugins/acme" ]
}

@test "the lock holder's own plugin command runs (DOTFILES_LOCK_HOLDER), as dotfiles upgrade's does" {
  hold_lock
  DOTFILES_LOCK_HOLDER="$HOLDER" run bash "$CLI" remove acme --yes
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(yq -r '.plugins.acme // "gone"' "$PLOCK")" = gone ]
  # The holder's lock is left in place.
  [ "$(head -1 "$HOME/.dotfiles.lock")" = "$HOLDER" ]
}

@test "a free lock is held while the command runs and released after it" {
  # A yq wrapper records who holds the lock each time the command reads YAML.
  real_yq="$(command -v yq)"
  printf '#!/bin/sh\nhead -2 "$HOME/.dotfiles.lock" 2>/dev/null | paste -sd " " - >> "%s/held.log"\nexec "%s" "$@"\n' "$TEST_DIR" "$real_yq" > "$TEST_DIR/stub/yq"
  chmod +x "$TEST_DIR/stub/yq"
  for cmd in "list" "verify" "remove acme --yes"; do
    : > "$TEST_DIR/held.log"
    # shellcheck disable=SC2086
    run bash "$CLI" $cmd
    echo "$cmd -> $status: $output"
    [ "$status" -eq 0 ]
    grep -q "plugin ${cmd%% *}" "$TEST_DIR/held.log"
    [ ! -e "$HOME/.dotfiles.lock" ]
  done
}

@test "a lock that cannot be made stops at once with the reason" {
  mkdir -p "$TEST_DIR/no-write" && chmod 500 "$TEST_DIR/no-write"
  SECONDS=0
  DOTFILES_LOCK="$TEST_DIR/no-write/x/lock" DOTFILES_PLUGIN_LOCK_WAIT=60 run bash "$CLI" list
  echo "$output"
  [ "$status" -ne 0 ]
  [ "$SECONDS" -lt 10 ]
  [[ "$output" == *"cannot take"* ]]
}

@test "Ctrl-C reaches the command, and the lock goes only after it ends" {
  real_yq="$(command -v yq)"
  printf '#!/bin/sh\nsleep 1\nexec "%s" "$@"\n' "$real_yq" > "$TEST_DIR/stub/yq"
  chmod +x "$TEST_DIR/stub/yq"
  bash "$CLI" list > "$TEST_DIR/out" 2>&1 &
  parent=$!
  for _ in $(seq 50); do [ -e "$HOME/.dotfiles.lock" ] && break; sleep 0.1; done
  [ "$(head -1 "$HOME/.dotfiles.lock")" = "$parent" ]
  child="$(pgrep -P "$parent" -f dotfiles-plugin | head -1)"
  [ -n "$child" ]
  kill -INT "$child"
  wait "$parent" || true
  ! kill -0 "$child" 2>/dev/null
  [ ! -e "$HOME/.dotfiles.lock" ]
}

@test "read-only plugin commands do not wait on the lock" {
  hold_lock
  run bash "$CLI" options
  [ "$status" -eq 0 ]
  run bash "$CLI" update acme --dry-run
  echo "$output"
  [[ "$output" != *"$HOLDER"* ]]
}
