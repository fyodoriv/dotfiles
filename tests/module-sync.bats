#!/usr/bin/env bats
# Functional tests for modules/sync/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME"
  mkdir -p "$TEST_DOTFILES"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"

  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"
  touch "$OVERRIDES_FILE"
  FIX_MODE=false
  LIST_MODE=false
  pass_count=0
  fail_count=0
  fix_count=0
  skip_count=0

  pass()    { pass_count=$((pass_count + 1)); }
  fail()    { fail_count=$((fail_count + 1)); }
  fixed()   { fix_count=$((fix_count + 1)); }
  skipped() { skip_count=$((skip_count + 1)); }

  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }

  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="$4"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if eval "$test_cmd" >/dev/null 2>&1; then
      pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then
      if eval "$fix_cmd" >/dev/null 2>&1; then fixed "$desc"; else fail "$desc"; fi
    else
      fail "$desc"
    fi
  }

  # Mock launchctl
  launchctl() { return 1; }

  # Init a git repo in dotfiles dir for the clean check
  git -C "$TEST_DOTFILES" init -q
  export GIT_CONFIG_GLOBAL="$TEST_DIR/gitconfig"
  touch "$GIT_CONFIG_GLOBAL"
  git config --global user.name "Test"
  git config --global user.email "test@test.com"
  echo "# init" > "$TEST_DOTFILES/README.md"
  git -C "$TEST_DOTFILES" add . && git -C "$TEST_DOTFILES" commit -q -m "init" --no-gpg-sign

  # Stats file for sync.recent
  export DOTFILES_STATS_FILE="$TEST_DIR/stats.jsonl"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "sync: clean check passes when no uncommitted changes" {
  source "$BATS_TEST_DIRNAME/../modules/sync/doctor.sh"
  # sync.clean should pass (repo is clean)
  [ "$pass_count" -ge 1 ]
}

@test "sync: clean check fails with uncommitted changes" {
  echo "dirty" > "$TEST_DOTFILES/newfile.txt"
  source "$BATS_TEST_DIRNAME/../modules/sync/doctor.sh"
  # sync.clean should fail
  [ "$fail_count" -ge 1 ]
}

@test "sync: clean check uses the applied checkout when development differs" {
  local applied="$TEST_DIR/applied"
  mkdir -p "$applied"
  git -C "$applied" init -q
  echo "# applied" > "$applied/README.md"
  git -C "$applied" add README.md
  git -C "$applied" commit -q -m "init applied" --no-gpg-sign
  echo "dirty development checkout" > "$TEST_DOTFILES/newfile.txt"
  local now_ts
  now_ts=$(date -u "+%Y-%m-%dT%H:%M:%SZ")
  echo "{\"task\":\"sync\",\"timestamp\":\"$now_ts\"}" > "$DOTFILES_STATS_FILE"
  launchctl() { printf 'Label\n'; }
  DOTFILES_LINK_DIR="$applied"
  source "$BATS_TEST_DIRNAME/../modules/sync/doctor.sh"
  [ "$fail_count" -eq 0 ]
}

@test "sync: recent check passes with fresh sync timestamp" {
  local now_ts
  now_ts=$(date -u "+%Y-%m-%dT%H:%M:%SZ")
  echo "{\"task\":\"sync\",\"timestamp\":\"$now_ts\"}" > "$DOTFILES_STATS_FILE"
  source "$BATS_TEST_DIRNAME/../modules/sync/doctor.sh"
  # sync.recent should pass
  [ "$pass_count" -ge 1 ]
}

@test "sync: recent check fails when no stats file" {
  rm -f "$DOTFILES_STATS_FILE"
  source "$BATS_TEST_DIRNAME/../modules/sync/doctor.sh"
  # sync.recent should fail (no stats file)
  [ "$fail_count" -ge 1 ]
}

@test "sync: overrides skip checks" {
  echo "sync.launchagent" >> "$OVERRIDES_FILE"
  echo "sync.recent" >> "$OVERRIDES_FILE"
  echo "sync.clean" >> "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/sync/doctor.sh"
  [ "$skip_count" -eq 3 ]
  [ "$fail_count" -eq 0 ]
}
