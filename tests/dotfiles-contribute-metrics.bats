#!/usr/bin/env bats
# dotfiles contribute / dotfiles metrics: thin wrappers over agentbrew.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  STUB_LOG="$TEST_DIR/agentbrew.log"
  cat > "$TEST_DIR/agentbrew" <<'STUB'
#!/bin/bash
printf 'cwd=%s args=%s\n' "$PWD" "$*" >> "$STUB_LOG"
if [ "$1" = "metrics" ] && [[ " $* " == *" --share "* ]]; then
  printf '## agentbrew metrics snapshot (7 days)\n\n- agentbrew 0.0.0\n'
elif [ "$1" = "metrics" ]; then
  printf 'agentbrew metrics — last 7 days (local only, nothing is uploaded)\n'
fi
STUB
  cat > "$TEST_DIR/sampler" <<'STUB'
#!/bin/bash
printf 'last 24h: 10 rows\npeak load1 9.00 at 2026-10-16T08:00:00 (top: secret-proc:9.0)\noverload rows (load1 > 20): 0\npeak CPU busy 40%% at 2026-10-16T08:00:00\n'
STUB
  chmod +x "$TEST_DIR/agentbrew" "$TEST_DIR/sampler"
  export STUB_LOG DOTFILES_AGENTBREW_BIN="$TEST_DIR/agentbrew" DOTFILES_LOAD_SAMPLER_BIN="$TEST_DIR/sampler"
}

teardown() { rm -rf "$TEST_DIR"; }

@test "contribute runs agentbrew contribute from the dotfiles checkout and passes flags through" {
  run env DOTFILES_DIR="$REPO" bash "$REPO/bin/dotfiles-contribute" --dry-run --draft
  [ "$status" -eq 0 ]
  grep -qx "cwd=$REPO args=contribute --dry-run --draft" "$STUB_LOG"
}

@test "contribute --repo <path> opens the PR from that checkout" {
  mkdir -p "$TEST_DIR/skill-repo"
  run env DOTFILES_DIR="$REPO" bash "$REPO/bin/dotfiles-contribute" --repo "$TEST_DIR/skill-repo" --dry-run
  [ "$status" -eq 0 ]
  grep -q "cwd=$TEST_DIR/skill-repo args=contribute --dry-run" "$STUB_LOG"
}

@test "metrics shows agentbrew metrics plus the full machine load report" {
  run env DOTFILES_DIR="$REPO" bash "$REPO/bin/dotfiles-metrics" --days 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing is uploaded"* ]]
  [[ "$output" == *"Machine load (last 1 days)"* ]]
  [[ "$output" == *"peak load1"* ]]
  grep -q "args=metrics --days 1" "$STUB_LOG"
}

@test "metrics --share writes aggregates only (no process names)" {
  run env DOTFILES_DIR="$REPO" bash "$REPO/bin/dotfiles-metrics" --share "$TEST_DIR/m.md"
  [ "$status" -eq 0 ]
  grep -q '^## agentbrew metrics snapshot' "$TEST_DIR/m.md"
  grep -q '^- overload rows' "$TEST_DIR/m.md"
  ! grep -q 'secret-proc' "$TEST_DIR/m.md"
}

@test "metrics rejects a non-numeric --days" {
  run env DOTFILES_DIR="$REPO" bash "$REPO/bin/dotfiles-metrics" --days soon
  [ "$status" -eq 2 ]
}
