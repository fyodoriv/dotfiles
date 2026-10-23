#!/usr/bin/env bats
# Tests for the stable dotfiles compatibility entry point. AgentBrew owns the
# managed MCP client and project-memory implementation. The entry point adds
# a change-time fast path, a stamp, a lock, and --background (issue #284).

setup() {
  REPO_ROOT="$BATS_TEST_DIRNAME/.."
  SCRIPT="$REPO_ROOT/bin/dotfiles-memory-sync-projects"

  # Scratch HOME: the fast path reads ~/.claude/projects and writes its stamp
  # under ~/.local/state, so never touch the real ones.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  unset XDG_STATE_HOME XDG_CACHE_HOME AGENTBREW_CLAUDE_PROJECTS_DIR \
    DOTFILES_CLAUDE_PROJECTS_DIR DOTFILES_MEMORY_MCP_URL DOTFILES_MEMORY_SYNC_TIMEOUT
  PROJECTS="$HOME/.claude/projects"
  STAMP="$HOME/.local/state/dotfiles/memory-sync-projects.stamp"
  LEDGER="$HOME/.local/state/agentbrew/memory-project-sync.json"
  LOG_FILE="$HOME/.local/share/dotfiles/logs/memory-sync-projects.log"
  LOCK_DIR="$HOME/.cache/agentbrew/memory-sync-projects.lock"

  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$STUB_BIN"
  AGENTBREW_LOG="$BATS_TEST_TMPDIR/agentbrew.log"
  export AGENTBREW_LOG
  # Logs every call. `--check` exits STUB_CHECK_EXIT (0 = no stale store) and
  # rewrites the ledger's stores when STUB_CHECK_LEDGER_EDIT is set. A sync
  # rewrites the ledger like AgentBrew (stores from STUB_LEDGER_STORES),
  # sleeps STUB_SYNC_SLEEP seconds to stand in for a slow daemon, appends to
  # STUB_SYNC_EDIT if set, and exits STUB_SYNC_EXIT.
  cat <<'STUB' > "$STUB_BIN/agentbrew"
#!/bin/bash
printf '%s|%s|%s|%s\n' \
  "$*" \
  "${DOTFILES_CLAUDE_PROJECTS_DIR:-}" \
  "${DOTFILES_MEMORY_MCP_URL:-}" \
  "${DOTFILES_MEMORY_SYNC_TIMEOUT:-}" \
  >> "$AGENTBREW_LOG"
ledger="$HOME/.local/state/agentbrew/memory-project-sync.json"
write_ledger() {
  mkdir -p "${ledger%/*}"
  printf '{"version":1,"lastAttemptedAt":"%s","status":"ok","stores":%s}\n' "$RANDOM" "$1" > "$ledger"
}
stores='{"s1":{"fingerprint":"f1","fileCount":1,"lastSyncedAt":"t1","chunksStored":0}}'
[ -n "${STUB_LEDGER_STORES:-}" ] && stores="$STUB_LEDGER_STORES"
case " $* " in
  *" --check "*)
    [ -n "${STUB_CHECK_LEDGER_EDIT:-}" ] && write_ledger '{}'
    exit "${STUB_CHECK_EXIT:-0}"
    ;;
esac
write_ledger "$stores"
sleep "${STUB_SYNC_SLEEP:-0}"
if [ -n "${STUB_SYNC_EDIT:-}" ]; then printf 'edited mid-sync\n' >> "$STUB_SYNC_EDIT"; fi
echo "memory-sync: stub synced"
exit "${STUB_SYNC_EXIT:-0}"
STUB
  chmod +x "$STUB_BIN/agentbrew"
  export DOTFILES_MEMORY_AGENTBREW_BIN="$STUB_BIN/agentbrew"
}

# make_store <project-dir-name> <file>... — a populated memory store.
make_store() {
  local project="$1"
  shift
  mkdir -p "$PROJECTS/$project/memory"
  for file in "$@"; do
    printf 'fact %s\n' "$file" > "$PROJECTS/$project/memory/$file"
  done
}

# set_age <seconds> <path>... — move mtimes into the past.
set_age() {
  local seconds="$1"
  shift
  perl -e 'my $t = time - shift; utime($t, $t, @ARGV) == @ARGV or die "utime failed\n"' -- "$seconds" "$@"
}

age_projects() {
  local paths=()
  while IFS= read -r path; do paths+=("$path"); done < <(find "$PROJECTS")
  set_age "$1" "${paths[@]}"
}

sync_calls() {
  grep -c '^memory sync-projects|' "$AGENTBREW_LOG" 2>/dev/null || true
}

# Two stores, aged two hours, then one full sync writes the stamp.
synced_stores() {
  make_store "-Users-me-apps-travel" a.md b.md
  make_store "-Users-me-apps-tooling" c.md
  age_projects 7200
  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$STAMP" ]
  rm -f "$AGENTBREW_LOG"
}

@test "script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "forwards sync arguments to AgentBrew" {
  run "$SCRIPT" --dry-run --quiet --json
  [ "$status" -eq 0 ]
  grep -qx 'memory sync-projects --dry-run --quiet --json|||' "$AGENTBREW_LOG"
}

@test "forwards the compatibility project-memory environment aliases" {
  export DOTFILES_CLAUDE_PROJECTS_DIR="/tmp/claude-projects"
  export DOTFILES_MEMORY_MCP_URL="http://127.0.0.1:19876/mcp"
  export DOTFILES_MEMORY_SYNC_TIMEOUT="45"

  run "$SCRIPT" --check

  [ "$status" -eq 0 ]
  grep -qx 'memory sync-projects --check|/tmp/claude-projects|http://127.0.0.1:19876/mcp|45' "$AGENTBREW_LOG"
}

@test "forwards help to the canonical command" {
  run "$SCRIPT" --help

  [ "$status" -eq 0 ]
  grep -qx 'memory sync-projects --help|||' "$AGENTBREW_LOG"
  [[ "$output" == *"--background"* ]]
}

@test "skips without blocking when AgentBrew is unavailable" {
  export DOTFILES_MEMORY_AGENTBREW_BIN="$STUB_BIN/missing-agentbrew"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"memory sync skipped: agentbrew is not available"* ]]
}

@test "a missing stamp runs AgentBrew, then writes the stamp after a clean check" {
  make_store "-Users-me-apps-travel" a.md
  age_projects 7200

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"no full-sync stamp yet"* ]]
  [[ "$output" == *"memory-sync: stub synced"* ]]
  [[ "$output" == *"AgentBrew sync took"* ]]
  [ "$(sync_calls)" -eq 1 ]
  grep -qx 'memory sync-projects --check|||' "$AGENTBREW_LOG"
  # Hashes of the store set and the ledger's stores; no paths in the stamp.
  [ "$(wc -l < "$STAMP" | tr -d ' ')" -eq 2 ]
  [ "$(grep -cvE '^[0-9a-f]{64}$' "$STAMP")" -eq 0 ]
}

@test "unchanged stores return fast without starting AgentBrew or the daemon" {
  synced_stores
  local started=$SECONDS

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ $((SECONDS - started)) -lt 5 ]
  [ ! -e "$AGENTBREW_LOG" ]
  [[ "$output" =~ "memory-sync: travel — up to date (2 files, "[0-9.]+" ms)" ]]
  [[ "$output" =~ "memory-sync: tooling — up to date (1 files, "[0-9.]+" ms)" ]]
  [[ "$output" == *"0/2 stores synced (2 up to date; no change since the last full sync, AgentBrew not started"* ]]
}

@test "--quiet fast path prints only the summary" {
  synced_stores

  run "$SCRIPT" --quiet

  [ "$status" -eq 0 ]
  [ ! -e "$AGENTBREW_LOG" ]
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" == "memory-sync: 0/2 stores synced (2 up to date;"* ]]
}

@test "a store edited after its last sync runs AgentBrew" {
  synced_stores
  printf 'new fact\n' >> "$PROJECTS/-Users-me-apps-travel/memory/a.md"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" =~ "memory-sync: travel — changed since the last full sync (2 files, "[0-9.]+" ms)" ]]
  [[ "$output" == *"1/2 stores changed"* ]]
  [ "$(sync_calls)" -eq 1 ]
}

@test "a deleted memory file runs AgentBrew" {
  synced_stores
  rm "$PROJECTS/-Users-me-apps-travel/memory/b.md"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"travel — changed since the last full sync (1 files"* ]]
  [ "$(sync_calls)" -eq 1 ]
}

@test "a file overwritten with an old mtime runs AgentBrew" {
  synced_stores
  printf 'restored fact\n' > "$BATS_TEST_TMPDIR/old.md"
  set_age 86400 "$BATS_TEST_TMPDIR/old.md"
  cp -p "$BATS_TEST_TMPDIR/old.md" "$PROJECTS/-Users-me-apps-travel/memory/a.md"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"travel — changed since the last full sync"* ]]
  [ "$(sync_calls)" -eq 1 ]
}

@test "a new store runs AgentBrew" {
  synced_stores
  make_store "-Users-me-apps-new" d.md

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"the set of stores changed since the last full sync"* ]]
  [ "$(sync_calls)" -eq 1 ]
}

@test "a renamed project directory runs AgentBrew" {
  synced_stores
  mv "$PROJECTS/-Users-me-apps-travel" "$PROJECTS/-Users-me-apps-trips"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"the set of stores changed since the last full sync"* ]]
  [ "$(sync_calls)" -eq 1 ]
}

@test "a new project directory without memory keeps the fast path" {
  synced_stores
  mkdir -p "$PROJECTS/-Users-me-apps-fresh-worktree"
  printf '{}\n' > "$PROJECTS/-Users-me-apps-fresh-worktree/session.jsonl"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"AgentBrew not started"* ]]
  [ ! -e "$AGENTBREW_LOG" ]
}

@test "a deleted AgentBrew ledger runs AgentBrew" {
  synced_stores
  rm "$LEDGER"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"the AgentBrew sync ledger changed since the last full sync"* ]]
  [ "$(sync_calls)" -eq 1 ]
}

@test "a ledger rewritten with older store entries runs AgentBrew" {
  synced_stores
  printf '{"version":1,"lastAttemptedAt":"x","status":"ok","stores":{"s1":{"fingerprint":"old","fileCount":1,"lastSyncedAt":"t0","chunksStored":0}}}\n' > "$LEDGER"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"the AgentBrew sync ledger changed since the last full sync"* ]]
  [ "$(sync_calls)" -eq 1 ]
}

@test "a ledger rewrite with the same store entries keeps the fast path" {
  synced_stores
  printf '{"stores":{"s1":{"lastSyncedAt":"t1","chunksStored":0,"fileCount":1,"fingerprint":"f1"}},"status":"degraded","lastAttemptedAt":"later","version":1}\n' > "$LEDGER"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"AgentBrew not started"* ]]
  [ ! -e "$AGENTBREW_LOG" ]
}

@test "a ledger that changes during the check writes no stamp" {
  make_store "-Users-me-apps-travel" a.md
  age_projects 7200

  STUB_CHECK_LEDGER_EDIT=1 run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ ! -e "$STAMP" ]
}

@test "a failed AgentBrew sync passes its exit code and writes no stamp" {
  make_store "-Users-me-apps-travel" a.md
  age_projects 7200

  STUB_SYNC_EXIT=3 run "$SCRIPT"

  [ "$status" -eq 3 ]
  [ ! -e "$STAMP" ]
  [ -z "$(find "$HOME/.local/state/dotfiles" -name '*.next.*')" ]
}

@test "a sync already holding the lock makes a second run skip" {
  make_store "-Users-me-apps-travel" a.md
  mkdir -p "$LOCK_DIR"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"an AgentBrew sync is already running; skipped"* ]]
  [ ! -e "$AGENTBREW_LOG" ]
  [ -d "$LOCK_DIR" ]
}

@test "an uncreatable lock does not stop the sync" {
  make_store "-Users-me-apps-travel" a.md
  printf 'not a directory\n' > "$HOME/.cache"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" != *"already running"* ]]
  [ "$(sync_calls)" -eq 1 ]
}

@test "a lock older than 15 minutes is taken over and released" {
  make_store "-Users-me-apps-travel" a.md
  mkdir -p "$LOCK_DIR"
  set_age 1000 "$LOCK_DIR"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(sync_calls)" -eq 1 ]
  [ ! -e "$LOCK_DIR" ]
}

@test "a retargeted memory symlink runs AgentBrew" {
  mkdir -p "$PROJECTS/-Users-me-apps-linked" "$BATS_TEST_TMPDIR/one" "$BATS_TEST_TMPDIR/two"
  printf 'one\n' > "$BATS_TEST_TMPDIR/one/a.md"
  printf 'two\n' > "$BATS_TEST_TMPDIR/two/a.md"
  ln -s "$BATS_TEST_TMPDIR/one" "$PROJECTS/-Users-me-apps-linked/memory"
  run "$SCRIPT"
  [ -f "$STAMP" ]
  rm -f "$AGENTBREW_LOG"
  ln -sfn "$BATS_TEST_TMPDIR/two" "$PROJECTS/-Users-me-apps-linked/memory"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"linked — changed since the last full sync"* ]]
  [ "$(sync_calls)" -eq 1 ]
}

@test "a file with a future mtime keeps the fast path" {
  make_store "-Users-me-apps-travel" a.md
  set_age -31536000 "$PROJECTS/-Users-me-apps-travel/memory/a.md"
  run "$SCRIPT"
  [ -f "$STAMP" ]
  rm -f "$AGENTBREW_LOG"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"AgentBrew not started"* ]]
  [ ! -e "$AGENTBREW_LOG" ]
}

@test "a store edited during the sync runs AgentBrew again next time" {
  make_store "-Users-me-apps-travel" a.md
  age_projects 7200
  STUB_SYNC_EDIT="$PROJECTS/-Users-me-apps-travel/memory/a.md" run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "$STAMP" ]
  rm -f "$AGENTBREW_LOG"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"travel — changed since the last full sync"* ]]
  [ "$(sync_calls)" -eq 1 ]
}

@test "a stamp dated in the future runs AgentBrew" {
  synced_stores
  set_age -3600 "$STAMP"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"the full-sync stamp is dated in the future"* ]]
  [ "$(sync_calls)" -eq 1 ]
}

@test "a deleted stamp runs AgentBrew" {
  synced_stores
  rm "$STAMP"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"no full-sync stamp yet"* ]]
  [ "$(sync_calls)" -eq 1 ]
  [ -f "$STAMP" ]
}

@test "a stamp for another projects directory does not count" {
  synced_stores
  printf '/somewhere/else\n' > "$STAMP"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(sync_calls)" -eq 1 ]
}

@test "a stamp older than 12 hours runs AgentBrew" {
  synced_stores
  age_projects 50400
  set_age 46800 "$STAMP"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"the last full sync is over 12 hours old"* ]]
  [ "$(sync_calls)" -eq 1 ]
}

@test "a degraded sync writes no stamp, so the next run syncs again" {
  make_store "-Users-me-apps-travel" a.md
  age_projects 7200
  export STUB_CHECK_EXIT=1

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [ ! -e "$STAMP" ]
  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(sync_calls)" -eq 2 ]
  [ ! -e "$STAMP" ]
  [ -z "$(find "$HOME/.local/state/dotfiles" -name '*.next.*')" ]
}

@test "--background returns at once and the detached run syncs and logs" {
  make_store "-Users-me-apps-travel" a.md
  age_projects 7200
  local started=$SECONDS

  # No `3>&-`: the detached run must close inherited fds itself, or bats
  # would wait for it here.
  STUB_SYNC_SLEEP=3 run "$SCRIPT" --background

  [ "$status" -eq 0 ]
  [ $((SECONDS - started)) -lt 3 ]
  [[ "$output" == *"AgentBrew sync runs in the background (pid "* ]]
  [[ "$output" == *"log: $LOG_FILE"* ]]
  for _ in $(seq 100); do
    [ -f "$STAMP" ] && break
    sleep 0.1
  done
  [ -f "$STAMP" ]
  [ "$(sync_calls)" -eq 1 ]
  grep -q "background run started" "$LOG_FILE"
  grep -q "memory-sync: stub synced" "$LOG_FILE"
}

@test "two --background runs start one AgentBrew sync" {
  make_store "-Users-me-apps-travel" a.md
  age_projects 7200
  STUB_SYNC_SLEEP=2 run "$SCRIPT" --background
  [ "$status" -eq 0 ]
  STUB_SYNC_SLEEP=2 run "$SCRIPT" --background
  [ "$status" -eq 0 ]

  for _ in $(seq 100); do
    [ -f "$STAMP" ] && [ ! -e "$LOCK_DIR" ] && grep -q "already running" "$LOG_FILE" && break
    sleep 0.1
  done
  [ -f "$STAMP" ]
  grep -q "an AgentBrew sync is already running; skipped" "$LOG_FILE"
  [ "$(sync_calls)" -eq 1 ]
  [ ! -e "$LOCK_DIR" ]
}

@test "--background with nothing changed stays on the foreground fast path" {
  synced_stores

  run "$SCRIPT" --background

  [ "$status" -eq 0 ]
  [[ "$output" == *"AgentBrew not started"* ]]
  [[ "$output" != *"background"* ]]
  [ ! -e "$AGENTBREW_LOG" ]
  [ ! -e "$LOG_FILE" ]
}

@test "without perl it runs the full AgentBrew sync" {
  [ ! -e /bin/perl ] || skip "/bin has perl on this system"
  synced_stores

  PATH="$STUB_BIN:/bin" run "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(sync_calls)" -eq 1 ]
}
