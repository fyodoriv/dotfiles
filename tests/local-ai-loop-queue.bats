#!/usr/bin/env bats
# Pin lib/local-ai-loop.py's --queue mode: read one-task-per-file specs
# from a directory instead of the repo TASKS.md, pick in lexical filename
# order, filter via pickable(), and delete a spec file only on the fully
# gated success path. First slice of the overnight-grind epic — see
# docs/plans/overnight-grind-queue-reader.md.

REPO_ROOT="$BATS_TEST_DIRNAME/.."

_py() {
  python3 - "$REPO_ROOT" "$@" <<'PY'
import importlib.util, json, sys, os
root = sys.argv[1]
spec = importlib.util.spec_from_file_location(
    "loop", os.path.join(root, "lib", "local-ai-loop.py"),
)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
cmd = sys.argv[2]
if cmd == "read":
    tasks = m.read_queue_dir(sys.argv[3])
    print(json.dumps([
        {"id": t["id"], "priority": t["priority"], "qf": t.get("_queue_file", "")}
        for t in tasks
    ]))
elif cmd == "pickable":
    tasks = [t for t in m.read_queue_dir(sys.argv[3]) if m.pickable(t)]
    print(json.dumps([t["id"] for t in tasks]))
elif cmd == "close":
    tasks = m.read_queue_dir(sys.argv[3])
    m.close_queue_task(tasks[0])
    print("closed: ok")
PY
}

setup() {
  TMP=$(mktemp -d)
  QUEUE="$TMP/tasks-queue"
  mkdir -p "$QUEUE"
}

teardown() { rm -rf "$TMP"; }

_spec() {
  # _spec <filename> <id> [extra-metadata-line]
  local file="$1" id="$2" extra="${3:-}"
  {
    printf '%s\n' "## P0" "" "- [ ] Task $id" "  - **ID**: $id"
    printf '%s\n' "  - **Details**: do the thing for $id"
    if [ -n "$extra" ]; then printf '%s\n' "$extra"; fi
  } > "$QUEUE/$file"
}

@test "queue: specs read in lexical filename order with _queue_file set" {
  _spec "20-second.md" "task-second"
  _spec "10-first.md" "task-first"
  run _py read "$QUEUE"
  [ "$status" -eq 0 ]
  [[ "$output" == '[{"id": "task-first", "priority": "P0", "qf": "'"$QUEUE"'/10-first.md"}, {"id": "task-second", "priority": "P0", "qf": "'"$QUEUE"'/20-second.md"}]' ]]
}

@test "queue: missing and empty dirs read as empty" {
  run _py read "$TMP/nope"
  [ "$status" -eq 0 ]
  [[ "$output" == "[]" ]]
  run _py read "$QUEUE"
  [ "$status" -eq 0 ]
  [[ "$output" == "[]" ]]
}

@test "queue: headerless spec parses via the P0-prefix fallback" {
  printf '%s\n' "- [ ] Headerless task" "  - **ID**: task-headerless" \
    > "$QUEUE/spec.md"
  run _py read "$QUEUE"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"id": "task-headerless", "priority": "P0"'* ]]
}

@test "queue: manual-tagged spec is excluded by pickable()" {
  _spec "a.md" "task-auto"
  _spec "b.md" "task-manual" "  - **Tags**: manual"
  run _py pickable "$QUEUE"
  [ "$status" -eq 0 ]
  [[ "$output" == '["task-auto"]' ]]
}

@test "queue: close_queue_task deletes the spec file" {
  _spec "only.md" "task-done"
  run _py close "$QUEUE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"closed: ok"* ]]
  [ ! -f "$QUEUE/only.md" ]
}

@test "queue: main --dry-run --queue picks from the queue, not TASKS.md" {
  _spec "solo.md" "task-from-queue"
  run python3 "$REPO_ROOT/lib/local-ai-loop.py" \
    --dry-run --queue "$QUEUE" --cwd "$REPO_ROOT" --max-tasks 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"task-from-queue"* ]]
  # No task id from the repo's real TASKS.md may be picked.
  [[ "$output" != *"overnight-grind-summary-csv"* ]]
}

@test "queue: bin usage header documents --queue" {
  grep -q -- "--queue" "$REPO_ROOT/bin/local-ai-loop"
}
