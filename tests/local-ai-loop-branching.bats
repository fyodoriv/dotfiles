#!/usr/bin/env bats
# Pin lib/local-ai-loop.py's per-task dogfood branches (queue mode): each
# task runs on dogfood/<task-id>; a fully gated success fast-forwards the
# starting branch; a failure leaves it untouched and logs a rollback note.
# Third slice of the overnight-grind epic (overnight-grind-branch-per-task).

REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  TMP=$(mktemp -d)
  REPO="$TMP/repo"
  QUEUE="$TMP/queue"
  mkdir -p "$REPO/bin" "$QUEUE"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
  # make check fails while lib/broken.txt exists.
  printf 'check:\n\t@test ! -f lib/broken.txt\n' > "$REPO/Makefile"
  # Agent stub: the prompt names the task id. "good-*" writes a deliverable;
  # "bad-check-*" writes a file that breaks make check; "bad-agent-*" fails.
  cat > "$REPO/bin/local-ai-agent" <<'STUB'
#!/bin/bash
prompt="$*"
mkdir -p lib
case "$prompt" in
  *good-one*) echo one > lib/good-one.txt ;;
  *good-two*) echo two > lib/good-two.txt ;;
  *bad-check*) echo x > lib/broken.txt ;;
  *bad-agent*) echo y > lib/partial.txt; exit 1 ;;
esac
exit 0
STUB
  chmod +x "$REPO/bin/local-ai-agent"
  git -C "$REPO" init -q -b main
  git -C "$REPO" add Makefile bin/local-ai-agent
  git -C "$REPO" commit -q -m init
}

teardown() { rm -rf "$TMP"; }

_spec() {  # _spec <file> <id>
  printf '%s\n' "## P1" "" "- [ ] Task $2" "  - **ID**: $2" "  - **Details**: do $2" > "$QUEUE/$1"
}

_loop() {
  run env -u BASH_ENV python3 "$REPO_ROOT/lib/local-ai-loop.py" --cwd "$REPO" --queue "$QUEUE" \
    --deadline 5m --max-tasks 5 "$@"
}

@test "branching: a gated success merges its dogfood branch into the starting branch" {
  _spec 10.md good-one
  _loop
  [ "$status" -eq 0 ]
  [[ "$output" == *"working on branch dogfood/good-one"* ]]
  [[ "$output" == *"merged dogfood/good-one into main"* ]]
  [ "$(git -C "$REPO" branch --show-current)" = "main" ]
  git -C "$REPO" log --format=%s -1 main | grep -qx "chore(local-ai-loop): good-one"
  [ -f "$REPO/lib/good-one.txt" ]
  ! git -C "$REPO" rev-parse --verify --quiet refs/heads/dogfood/good-one
  [ ! -e "$QUEUE/10.md" ]
}

@test "branching: failures leave the starting branch untouched and log a rollback note" {
  _spec 10.md bad-check
  _spec 20.md bad-agent
  _spec 30.md good-two
  local before
  before="$(git -C "$REPO" rev-parse main)"
  _loop
  [ "$status" -eq 2 ]
  [[ "$output" == *"rollback: abandoned dogfood/bad-check (check-failed); main unchanged"* ]]
  [[ "$output" == *"rollback: abandoned dogfood/bad-agent (agent-failed); main unchanged"* ]]
  # The failures left nothing behind; the later success still merged.
  [ ! -e "$REPO/lib/broken.txt" ]
  [ ! -e "$REPO/lib/partial.txt" ]
  [ "$(git -C "$REPO" rev-parse main~1)" = "$before" ]
  git -C "$REPO" log --format=%s -1 main | grep -qx "chore(local-ai-loop): good-two"
  [ "$(git -C "$REPO" branch --show-current)" = "main" ]
  # Failed specs stay for the next run; CSV records each outcome.
  [ -e "$QUEUE/10.md" ] && [ -e "$QUEUE/20.md" ] && [ ! -e "$QUEUE/30.md" ]
  local csv="$REPO/docs/audits/local-ai-loop-runs.csv"
  grep -q ',bad-check,queue,check-failed,' "$csv"
  grep -q ',bad-agent,queue,agent-failed,' "$csv"
  grep -q ',good-two,queue,completed,' "$csv"
}

@test "branching: --single-branch runs on the current branch with no dogfood branch" {
  _spec 10.md good-one
  _loop --single-branch
  [ "$status" -eq 0 ]
  [[ "$output" != *"dogfood/"* ]]
  git -C "$REPO" log --format=%s -1 main | grep -qx "chore(local-ai-loop): good-one"
}

@test "branching: the loop never uses destructive git commands" {
  ! grep -nE 'reset", "--hard|"clean", "-f|checkout", "\."' "$REPO_ROOT/lib/local-ai-loop.py"
}
