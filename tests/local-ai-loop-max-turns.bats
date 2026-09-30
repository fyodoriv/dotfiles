#!/usr/bin/env bats
# Pin the estimate_max_turns heuristic in lib/local-ai-loop.py. Turn
# budget scales with task complexity — observed in run-5 that the
# cover-devin task used all 14 turns iterating through the critic's
# feedback and had 0 turns left for make check.

REPO_ROOT="$BATS_TEST_DIRNAME/.."

_budget() {
  local details="$1" files="$2" acceptance="$3"
  python3 - "$details" "$files" "$acceptance" "$REPO_ROOT" <<'PY'
import importlib.util, sys, os
details, files, accept, root = sys.argv[1:5]
spec = importlib.util.spec_from_file_location(
    "loop", os.path.join(root, "lib", "local-ai-loop.py"),
)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
task = {"id": "x", "priority": "P2", "title": "t",
        "details": details, "files": files, "acceptance": accept}
print(m.estimate_max_turns(task))
PY
}

@test "budget: simple task = base 14 turns" {
  run _budget "Short details." "lib/foo.py" "passes make check"
  [ "$status" -eq 0 ]
  [ "$output" = "14" ]
}

@test "budget: long details adds 4" {
  run _budget "$(printf 'x%.0s' {1..500})" "lib/foo.py" "short"
  [ "$status" -eq 0 ]
  [ "$output" = "18" ]
}

@test "budget: many files adds 4" {
  run _budget "short" "a.py, b.py, c.py" "short"
  [ "$status" -eq 0 ]
  [ "$output" = "18" ]
}

@test "budget: long acceptance adds 4" {
  run _budget "short" "one.py" "$(printf 'A%.0s' {1..300})"
  [ "$status" -eq 0 ]
  [ "$output" = "18" ]
}

@test "budget: all three signals cap at 26 (14 + 12)" {
  run _budget \
    "$(printf 'x%.0s' {1..500})" \
    "a.py, b.py, c.py, d.py" \
    "$(printf 'A%.0s' {1..300})"
  [ "$status" -eq 0 ]
  # 14 + 4 + 4 + 4 = 26
  [ "$output" = "26" ]
}

@test "budget: is capped at 28 even with all signals" {
  run _budget \
    "$(printf 'x%.0s' {1..5000})" \
    "a.py, b.py, c.py, d.py, e.py, f.py, g.py" \
    "$(printf 'A%.0s' {1..3000})"
  [ "$status" -eq 0 ]
  # 14 + 4 + 4 + 4 = 26 — still under the 28 cap
  [ "$output" = "26" ]
}
