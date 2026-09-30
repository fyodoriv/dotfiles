#!/usr/bin/env bats
# Pin invariants of bin/local-ai-agent + lib/local-ai-agent.py that
# don't require Ollama to be running. The runtime behaviour
# (model→tool_calls→bash→done) is exercised manually with `local-ai-
# agent "..."`; here we lock down the static surface so structural
# regressions show up in CI.

REPO_ROOT="$BATS_TEST_DIRNAME/.."
WRAPPER="$REPO_ROOT/bin/local-ai-agent"
LIB="$REPO_ROOT/lib/local-ai-agent.py"
FM="$REPO_ROOT/docs/audits/local-ai-failure-modes.md"

@test "agent: wrapper exists, is executable, has the help shape" {
  [ -x "$WRAPPER" ]
  head -5 "$WRAPPER" | grep -q '^#!/bin/bash'
  head -20 "$WRAPPER" | grep -q '^# Usage:'
}

@test "agent: lib file declares the three tools (bash, write_file, done)" {
  grep -qE '"name": "bash"' "$LIB"
  grep -qE '"name": "write_file"' "$LIB"
  grep -qE '"name": "done"' "$LIB"
}

@test "agent: lib file declares the verify_cli_claims tool" {
  # Iteration A: mitigates hallucinated-flag failure mode. Must stay.
  grep -qE '"name": "verify_cli_claims"' "$LIB"
}

@test "agent: lib file loads the failure-modes file at import time" {
  grep -q '_load_failure_modes' "$LIB"
  grep -q 'docs/audits/local-ai-failure-modes.md\|local-ai-failure-modes.md' "$LIB"
  [ -f "$FM" ]
}

@test "agent: failure-modes file has all the patterns we shipped lessons for" {
  # Each of these headings was added as a real lesson learned. If any
  # gets accidentally dropped, the agent loses that guardrail silently.
  grep -qE '^## .*sed' "$FM"
  grep -qE '^## .*write_file' "$FM"
  grep -qE '^## .*[Hh]allucinated' "$FM"
  grep -qE '^## .*ail' "$FM"   # "...fails twice..." / "...failure..." family
}

@test "agent: num_predict is at least 2048 (raised from 512 after task 1)" {
  # Task 1/5 hit a 512 cap mid-write. Don't let it regress below 2048.
  grep -E '"num_predict":' "$LIB" | grep -qE ':\s*([2-9][0-9]{3}|[1-9][0-9]{4,})'
}

@test "agent: --max-turns default is at least 12 (raised from 10 after task 5)" {
  # Task 5/5 ran out of turns at 10. Don't regress.
  grep -E 'add_argument.*--max-turns' "$LIB" | grep -qE 'default=([1-9][0-9]{1,}|1[2-9]|[2-9][0-9])'
  # Be more specific: parse out the default and check it's >= 12.
  local default
  default=$(python3 -c "
import re
with open('$LIB') as f:
    src = f.read()
m = re.search(r'add_argument\(\"--max-turns\".*?default=(\d+)', src, re.DOTALL)
print(m.group(1) if m else '')
")
  [ -n "$default" ]
  [ "$default" -ge 12 ]
}

@test "agent: system prompt warns about macOS sed quirk" {
  grep -E '"' "$LIB" | grep -iqE "sed.*macos|bsd.*sed|sed -i ''"
}

@test "agent: system prompt instructs to call verify_cli_claims after write_file" {
  # The post-write verify rule needs to be in the prompt itself, not
  # only in the failure-modes file. Otherwise the agent forgets.
  grep -A 2 'verify_cli_claims' "$LIB" | grep -qE 'after.*write_file|IMMEDIATELY'
}

@test "agent: record-lesson script exists and points at the failure-modes file" {
  local rec="$REPO_ROOT/bin/local-ai-record-lesson"
  [ -x "$rec" ]
  grep -q 'local-ai-failure-modes.md' "$rec"
}
