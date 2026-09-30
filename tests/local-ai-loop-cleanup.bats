#!/usr/bin/env bats
# Pin the loop driver's revert_uncommitted cleanup. Surfaced in run-3
# dogfood that task 1's broken bats file polluted task 2's make check.
# Without per-task cleanup, the loop's failure modes compound across
# tasks. See docs/audits/local-ai-failure-modes.md.

REPO_ROOT="$BATS_TEST_DIRNAME/.."

# Helper: invoke revert_uncommitted from a python harness against a
# tmp git repo. Mirrors the loop driver's actual behavior.
_revert_in() {
  local repo_dir="$1"
  python3 - "$repo_dir" "$REPO_ROOT" <<'PY'
import importlib.util, sys, os
repo, root = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location(
    "loop", os.path.join(root, "lib", "local-ai-loop.py"),
)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.revert_uncommitted(repo, "test-task")
PY
}

setup() {
  TMP=$(mktemp -d)
  cd "$TMP"
  git init -q
  git config user.email "test@example.com"
  git config user.name "test"
  # Disable any inherited hooksPath (user has commit-msg + pre-commit
  # hooks installed globally that would reject this test's seed commits).
  git config core.hooksPath /dev/null
  # Seed the repo with one tracked file and a commit.
  echo "original" > tracked.txt
  mkdir -p tests
  echo "ok" > tests/seed.bats
  git add -A
  git commit -q --no-verify -m "feat: initial seed"
}

teardown() {
  cd /
  rm -rf "$TMP"
}

@test "revert_uncommitted: restores modified tracked file" {
  echo "modified" > tracked.txt
  _revert_in "$TMP"
  [ "$(cat tracked.txt)" = "original" ]
}

@test "revert_uncommitted: deletes untracked file in tests/" {
  echo "agent garbage" > tests/broken.bats
  _revert_in "$TMP"
  [ ! -f tests/broken.bats ]
}

@test "revert_uncommitted: deletes untracked file in lib/" {
  mkdir -p lib
  echo "garbage" > lib/hallucinated.py
  _revert_in "$TMP"
  [ ! -f lib/hallucinated.py ]
}

@test "revert_uncommitted: PRESERVES untracked file outside safe prefixes" {
  # Per CLAUDE.md git-safety rules: we don't `git clean -fd` the whole
  # repo because other agents may have legitimate scratch work outside
  # the agent's typical write paths. The deny here proves that.
  mkdir -p scratch
  echo "user scratch — must not be deleted" > scratch/notes.md
  _revert_in "$TMP"
  [ -f scratch/notes.md ]
}

@test "revert_uncommitted: deletes file in docs/ (agent often writes audits)" {
  mkdir -p docs/audits
  echo "garbage" > docs/audits/half-done-audit.md
  _revert_in "$TMP"
  [ ! -f docs/audits/half-done-audit.md ]
}

@test "revert_uncommitted: no-op on clean repo" {
  _revert_in "$TMP"
  # No assertion needed — just verify it doesn't error.
  [ "$(git status --porcelain | wc -l | tr -d ' ')" = "0" ]
}

@test "revert_uncommitted: PRESERVES docs/audits/local-ai-runs.csv (telemetry)" {
  # Failure mode found in run-4 dogfood: revert_uncommitted deleted
  # the cumulative telemetry CSV because it lives under docs/. The
  # CSV must persist across runs.
  mkdir -p docs/audits
  echo "ts,model,outcome" > docs/audits/local-ai-runs.csv
  echo "2026-01-01,m,done" >> docs/audits/local-ai-runs.csv
  _revert_in "$TMP"
  [ -f docs/audits/local-ai-runs.csv ]
  [ "$(wc -l < docs/audits/local-ai-runs.csv | tr -d ' ')" = "2" ]
}
