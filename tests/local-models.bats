#!/usr/bin/env bats
# bin/local-models keeps only the Ollama models some app reserves in
# `.agents/local-models`. These tests pin what it must keep: reserved models,
# young models, and everything when no reservation exists or Ollama is down.

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../bin/local-models"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME/apps"
  export LOCAL_MODELS_ROOTS="$HOME/apps"
  export LOCAL_MODELS_MANIFESTS="$TEST_DIR/manifests"
  export LOCAL_MODELS_OPENCODE="$TEST_DIR/opencode.json"
  export LOCAL_MODELS_EXTRA="$TEST_DIR/extra"
  export FAKE_STATE="$TEST_DIR/installed"
  export FAKE_LOG="$TEST_DIR/ollama.log"
  # Fake ollama: `list` prints $FAKE_STATE, `rm`/`pull` are logged.
  cat > "$TEST_DIR/ollama" <<'SH'
#!/bin/bash
case "$1" in
  list) [ -f "$FAKE_STATE.down" ] && exit 1
        echo "NAME ID SIZE MODIFIED"; cat "$FAKE_STATE" ;;
  rm|pull) echo "$1 $2" >> "$FAKE_LOG"; printf "SPINNER-NOISE\n" >&2 ;;
esac
SH
  chmod +x "$TEST_DIR/ollama"
  export LOCAL_MODELS_OLLAMA="$TEST_DIR/ollama"
  printf '%s\n' "qwen3:14b abc 9.3 GB 6days" "qwen3.6:27b def 17 GB 6weeks" "llama3.2:3b ghi 2.0 GB 3days" > "$FAKE_STATE"
  model_age qwen3:14b 6; model_age qwen3.6:27b 40; model_age llama3.2:3b 3
}

teardown() { rm -rf "$TEST_DIR"; }

model_age() {
  local d="$LOCAL_MODELS_MANIFESTS/${1%%:*}"
  mkdir -p "$d" && touch -t "$(date -v-"$2"d +%Y%m%d%H%M)" "$d/${1#*:}"
}

reserve() { mkdir -p "$HOME/apps/$1/.agents"; printf '%s\n' "${@:2}" > "$HOME/apps/$1/.agents/local-models"; }

@test "prune refuses when no app reserves anything" {
  run "$SCRIPT" prune --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"refusing to prune"* ]]
  [ ! -f "$FAKE_LOG" ]
}

@test "prune keeps reserved models and removes unreserved ones" {
  reserve app1 "qwen3:14b  # judge model"
  run "$SCRIPT" prune --yes
  [ "$status" -eq 0 ]
  grep -qx "rm qwen3.6:27b" "$FAKE_LOG"
  grep -qx "rm llama3.2:3b" "$FAKE_LOG"
  ! grep -q "qwen3:14b" "$FAKE_LOG"
}

@test "prune without --yes is a dry run" {
  reserve app1 qwen3:14b
  run "$SCRIPT" prune
  [[ "$output" == *"would remove unreserved model: qwen3.6:27b"* ]]
  [ ! -f "$FAKE_LOG" ]
}

@test "prune keeps unreserved models younger than --min-age-days" {
  reserve app1 qwen3:14b
  run "$SCRIPT" prune --yes --min-age-days 14
  grep -qx "rm qwen3.6:27b" "$FAKE_LOG"
  ! grep -q "llama3.2" "$FAKE_LOG"
}

@test "opencode and the extra file reserve models too" {
  reserve app1 qwen3:14b
  echo '{"provider":{"ollama":{"models":{"llama3.2:3b":{}}}}}' > "$LOCAL_MODELS_OPENCODE"
  echo "qwen3.6:27b" > "$LOCAL_MODELS_EXTRA"
  run "$SCRIPT" prune --yes
  [ ! -f "$FAKE_LOG" ]
}

@test "a tag without a version means :latest" {
  echo "nomic-embed-text:latest x 274 MB 1day" >> "$FAKE_STATE"
  reserve app1 qwen3:14b nomic-embed-text qwen3.6:27b llama3.2:3b
  run "$SCRIPT" prune --yes
  [ ! -f "$FAKE_LOG" ]
}

@test "prune skips when Ollama cannot list models" {
  reserve app1 qwen3:14b
  touch "$FAKE_STATE.down"
  run "$SCRIPT" prune --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipping prune"* ]]
  [ ! -f "$FAKE_LOG" ]
}

@test "check fails and names the pull command for a missing reserved model" {
  reserve app1 qwen3:8b
  run "$SCRIPT" check
  [ "$status" -eq 1 ]
  [[ "$output" == *"ollama pull qwen3:8b"* ]]
}

@test "status shows reserved, unreserved and missing models with the unreserved total" {
  reserve app1 qwen3:14b qwen3:8b
  run "$SCRIPT" status
  [[ "$output" == *"qwen3:14b"*"reserved"* ]]
  [[ "$output" == *"qwen3.6:27b"*"NOT reserved"* ]]
  [[ "$output" == *"qwen3:8b"*"MISSING"* ]]
  [[ "$output" == *"unreserved: 19.0 GB, missing: 1"* ]]
}

@test "ensure does nothing when no app reserves a model" {
  run "$SCRIPT" ensure
  [[ "$output" == *"nothing to install"* ]]
  [ ! -f "$FAKE_LOG" ]
}

@test "ensure pulls only the missing reserved models" {
  reserve app1 qwen3:14b qwen3:8b
  run "$SCRIPT" ensure
  [ "$(cat "$FAKE_LOG")" = "pull qwen3:8b" ]
}

@test "reservations in nested worktrees (root/a/b/repo/.agents) count" {
  mkdir -p "$HOME/apps/tooling/wt/repo/.agents"
  printf '%s\n' qwen3:14b qwen3.6:27b llama3.2:3b > "$HOME/apps/tooling/wt/repo/.agents/local-models"
  run "$SCRIPT" prune --yes
  [ ! -f "$FAKE_LOG" ]
}

@test "a symlinked root (like ~/apps/tooling/wt) is followed" {
  mkdir -p "$TEST_DIR/real/repo/.agents"
  printf '%s\n' qwen3:14b qwen3.6:27b llama3.2:3b > "$TEST_DIR/real/repo/.agents/local-models"
  ln -s "$TEST_DIR/real" "$HOME/apps/wt"
  LOCAL_MODELS_ROOTS="$HOME/apps/wt" run "$SCRIPT" prune --yes
  [ ! -f "$FAKE_LOG" ]
}

@test "prune output stays clean: ollama progress on stderr is not logged" {
  reserve app1 qwen3:14b
  run "$SCRIPT" prune --yes
  [ "$status" -eq 0 ]
  [[ "$output" != *"SPINNER-NOISE"* ]]
  [[ "$output" == *"removed unreserved model: qwen3.6:27b"* ]]
}
