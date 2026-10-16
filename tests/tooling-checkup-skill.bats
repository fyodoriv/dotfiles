#!/usr/bin/env bats

load test_helper

ROOT="$BATS_TEST_DIRNAME/.."
SKILL_DIR="$ROOT/skills/tooling-checkup"
SKILL="$SKILL_DIR/SKILL.md"
EVALS="$SKILL_DIR/evals/evals.json"
SCRIPTS="$SKILL_DIR/scripts"
AGENTFILE="$ROOT/Agentfile.yaml"

git_q() {
  git -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false \
    -c core.hooksPath=/dev/null -c init.defaultBranch=main "$@" >/dev/null 2>&1
}

# A tooling root with one primary checkout, an origin, and a sibling repo that
# is not a direct child checkout.
make_tooling_root() {
  TOOLING="$TEST_DIR/tooling"
  mkdir -p "$TOOLING"
  git_q init --bare "$TEST_DIR/origin.git"
  git_q clone "$TEST_DIR/origin.git" "$TOOLING/alpha"
  git_q -C "$TOOLING/alpha" commit --allow-empty -m "chore: init"
  git_q -C "$TOOLING/alpha" push origin HEAD:main
  git_q -C "$TOOLING/alpha" remote set-head origin main
}

@test "tooling-checkup is installed through the source Agentfile" {
  [ -f "$SKILL" ]
  grep -q '^name: tooling-checkup$' "$SKILL"
  awk '
    $0 == "skills:" { in_skills = 1; next }
    in_skills && /^[^[:space:]#][^:]*:/ { exit }
    in_skills && $0 ~ /^[[:space:]]*-[[:space:]]+tooling-checkup([[:space:]]|$)/ { found = 1 }
    END { exit !found }
  ' "$AGENTFILE"
}

@test "tooling-checkup has behavior evals" {
  run jq -e '
    .skill_name == "tooling-checkup"
    and (.evals | length >= 8)
    and (.evals | all(.prompt != "" and (.expectations | length >= 3)))
  ' "$EVALS"
  [ "$status" -eq 0 ]
}

@test "tooling-checkup passes its own best-practice audit" {
  run python3 "$SCRIPTS/audit_agent_config.py" --skills "$SKILL_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 error(s), 0 warning(s)"* ]]
  [ "$(wc -l < "$SKILL")" -lt 500 ]
}

@test "tooling-checkup keeps its scope and safety rules" {
  grep -F -q 'directly under `$TOOLING_ROOT`' "$SKILL"
  grep -F -q 'Dependabot is not outstanding work.' "$SKILL"
  grep -F -q '**critical** dependabot alert' "$SKILL"
  grep -F -q 'Automation branches are not outstanding work.' "$SKILL"
  grep -F -q 'Never delete a plist; move it.' "$SKILL"
  grep -F -q 'Minsky never starts on its own.' "$SKILL"
  grep -F -q 'lifts the `update-tooling` package' "$SKILL"
  grep -F -q 'disable-model-invocation: true' "$SKILL"
  grep -F -q 'git branch -d`, never `-D`' "$SKILL"
}

@test "tooling-checkup covers every requested phase" {
  grep -F -q 'Read and follow the `update-tooling` skill' "$SKILL"
  grep -F -q 'claude update' "$SKILL"
  grep -F -q 'claude doctor' "$SKILL"
  grep -F -q 'dotfiles-upgrade' "$SKILL"
  grep -F -q 'background_audit.sh' "$SKILL"
  grep -F -q 'echo_latency.py' "$SKILL"
  grep -F -q 'machine_metrics.py --hours 24' "$SKILL"
  grep -F -q 'latency-check: run' "$SKILL"
  grep -F -q 'audit_agent_config.py --cache' "$SKILL"
  grep -F -q 'AskUserQuestion' "$SKILL"
  grep -F -q 'checkup_state.py record' "$SKILL"
  grep -F -q 'agent_time_review.py --days 7' "$SKILL"
  grep -F -q '### Agent time (7 days)' "$SKILL"
  grep -F -q 'runs all eleven phases' "$SKILL"
  [ "$(grep -c '^## Phase ' "$SKILL")" -eq 11 ]
  [ "$(grep -c '^\*\*Done when:\*\*' "$SKILL")" -eq 11 ]
}

@test "tooling-checkup monthly pass covers health, cached gate, stories, speed, learnings, and P0s" {
  grep -F -q 'bin/dotfiles-doctor --quiet' "$SKILL"
  grep -F -q 'Cached gate: `make check`' "$SKILL"
  grep -F -q 'Broken stories: `make e2e`' "$SKILL"
  grep -F -q 'gate-timings.jsonl' "$SKILL"
  grep -F -q 'bin/dotfiles-metrics --table' "$SKILL"
  grep -F -q 'docs/learnings.md' "$SKILL"
  grep -F -q 'Open P0s' "$SKILL"
  grep -F -q 'Repo health (monthly):' "$SKILL"
}

@test "tooling-checkup reference links resolve one level deep" {
  local link
  for link in $(grep -o '](reference/[^)]*)' "$SKILL" | sed 's/^](//; s/)$//'); do
    [ -f "$SKILL_DIR/$link" ]
  done
  [ "$(grep -c '](reference/' "$SKILL")" -ge 4 ]
  ! grep -q '](reference/' "$SKILL_DIR"/reference/*.md
}

@test "tooling-checkup shell scripts pass shellcheck and avoid env shebangs" {
  command -v shellcheck >/dev/null || skip "shellcheck not installed"
  shellcheck -S warning "$SCRIPTS"/*.sh
  ! grep -l '^#!/usr/bin/env' "$SCRIPTS"/*.sh
  for script in "$SCRIPTS"/*.py; do python3 -m py_compile "$script"; done
}

@test "inventory classifies outstanding, merged, bot, and dirty work" {
  make_tooling_root
  local repo="$TOOLING/alpha"
  git_q -C "$repo" switch -c feat/unpushed
  git_q -C "$repo" commit --allow-empty -m "feat: local only"
  git_q -C "$repo" switch main
  git_q -C "$repo" branch merged-already
  git_q -C "$repo" switch -c dependabot/npm/foo
  git_q -C "$repo" commit --allow-empty -m "chore: bump"
  git_q -C "$repo" push origin dependabot/npm/foo
  git_q -C "$repo" switch main
  git_q -C "$repo" branch -D dependabot/npm/foo
  echo dirty > "$repo/untracked.txt"
  mkdir -p "$TOOLING/not-a-repo"

  run env TOOLING_ROOT="$TOOLING" TOOLING_CHECKUP_NO_GH=1 bash "$SCRIPTS/inventory.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"== alpha"* ]]
  [[ "$output" != *"not-a-repo"* ]]
  [[ "$output" == *"ship      branch feat/unpushed has 1 commit(s) not in main (no upstream)"* ]]
  [[ "$output" == *"clean-up  local branch merged-already is merged into main"* ]]
  [[ "$output" == *"bot       1 automation branch(es), not outstanding: dependabot/ x1"* ]]
  [[ "$output" == *"salvage   main checkout has 1 uncommitted path(s)"* ]]
}

@test "inventory skips linked worktrees as checkouts and flags orchestrator worktrees" {
  make_tooling_root
  git_q -C "$TOOLING/alpha" worktree add "$TOOLING/alpha-wt" -b feat/side
  git_q -C "$TOOLING/alpha" worktree add "$TOOLING/alpha/.worktrees/run-1" -b pipeline/run-1

  run env TOOLING_ROOT="$TOOLING" TOOLING_CHECKUP_NO_GH=1 TOOLING_CHECKUP_NO_FETCH=1 bash "$SCRIPTS/inventory.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"== alpha-wt"* ]]
  [[ "$output" == *"pipeline  worktree $(cd "$TOOLING" && pwd -P)/alpha/.worktrees/run-1"* ]]
  [[ "$output" == *"ship      worktree $(cd "$TOOLING" && pwd -P)/alpha-wt [feat/side] is clean"* ]]
}

@test "inventory fails clearly when the tooling root has no checkouts" {
  mkdir -p "$TEST_DIR/empty"
  run env TOOLING_ROOT="$TEST_DIR/empty" bash "$SCRIPTS/inventory.sh"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no primary git checkouts"* ]]
}

@test "audit flags broken skills and instruction files" {
  local bad="$TEST_DIR/skills/Bad_Skill"
  mkdir -p "$bad"
  cat > "$bad/SKILL.md" <<'EOF'
---
name: claude-Bad_Skill
description: I can help you with things.
---
See [missing](reference/missing.md) and docs\guide.md for more.
EOF
  local good="$TEST_DIR/skills/good-skill"
  mkdir -p "$good/reference"
  cat > "$good/SKILL.md" <<'EOF'
---
name: good-skill
description: >
  Formats release notes from merged pull requests. Use when the user asks
  for release notes or a changelog entry.
---
Read [the guide](reference/guide.md).
EOF
  printf '# Guide\n\nShort.\n' > "$good/reference/guide.md"
  local rules="$TEST_DIR/CLAUDE.md"
  {
    echo "Import @./missing-rules.md here. Mail me at someone@example.com."
    echo 'Literal `@./not-an-import.md` stays text.'
    echo "- Run the full test suite before every single commit please."
    echo "- Run the full test suite before every single commit please."
  } > "$rules"

  run python3 "$SCRIPTS/audit_agent_config.py" --skills "$TEST_DIR/skills" --rules "$rules"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR S003"*"claude-Bad_Skill"* ]]
  [[ "$output" == *"ERROR S004"* ]]
  [[ "$output" == *"WARN S010"* ]]
  [[ "$output" == *"WARN S011"* ]]
  [[ "$output" == *"ERROR S013"*"reference/missing.md"* ]]
  [[ "$output" == *"WARN S016"* ]]
  [[ "$output" == *"WARN R002"*"@./missing-rules.md"* ]]
  [[ "$output" != *"not-an-import"* ]]
  [[ "$output" != *"example.com"* ]]
  [[ "$output" == *"WARN R003"*"repeated 2 times"* ]]
  [[ "$output" != *"good-skill/SKILL.md"* ]]
}

@test "audit replays its cache only while inputs are unchanged" {
  local skill="$TEST_DIR/skills/cached-skill"
  mkdir -p "$skill"
  printf -- '---\nname: cached-skill\ndescription: Checks caches. Use when testing.\n---\nBody.\n' > "$skill/SKILL.md"
  export TOOLING_CHECKUP_STATE_DIR="$TEST_DIR/state"

  run python3 "$SCRIPTS/audit_agent_config.py" --cache --skills "$TEST_DIR/skills"
  [ "$status" -eq 0 ]
  [[ "$output" != *"replayed from cache"* ]]
  run python3 "$SCRIPTS/audit_agent_config.py" --cache --skills "$TEST_DIR/skills"
  [[ "$output" == *"replayed from cache"* ]]

  printf -- '---\nname: cached-skill\ndescription: Checks caches.\n---\nBody changed.\n' > "$skill/SKILL.md"
  touch -t 203001010000 "$skill/SKILL.md"
  run python3 "$SCRIPTS/audit_agent_config.py" --cache --skills "$TEST_DIR/skills"
  [[ "$output" != *"replayed from cache"* ]]
  [[ "$output" == *"WARN S011"* ]]
}

@test "state records a run and reports what changed since" {
  local bin="$TEST_DIR/bin"
  mkdir -p "$bin"
  printf '#!/bin/sh\necho "1.0.0 (Claude Code)"\n' > "$bin/claude"
  chmod +x "$bin/claude"
  make_tooling_root
  export TOOLING_ROOT="$TOOLING" TOOLING_CHECKUP_STATE_DIR="$TEST_DIR/state"

  run env PATH="$bin:/usr/bin:/bin" python3 "$SCRIPTS/checkup_state.py" diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"first run"* ]]
  [[ "$output" == *"version claude: 1.0.0 (Claude Code)"* ]]

  run env PATH="$bin:/usr/bin:/bin" python3 "$SCRIPTS/checkup_state.py" record \
    --verdict "healthy" --metric claude_echo_p95_ms=250
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/state/last-run.json" ]
  ! grep -q "$TEST_HOME" "$TEST_DIR/state/last-run.json"

  printf '#!/bin/sh\necho "1.1.0 (Claude Code)"\n' > "$bin/claude"
  git_q -C "$TOOLING/alpha" commit --allow-empty -m "feat: newer"
  run env PATH="$bin:/usr/bin:/bin" python3 "$SCRIPTS/checkup_state.py" diff
  [ "$status" -eq 0 ]
  [[ "$output" == *"last verdict: healthy"* ]]
  [[ "$output" == *"last metric claude_echo_p95_ms: 250"* ]]
  [[ "$output" == *"changed version claude: 1.0.0 (Claude Code) -> 1.1.0 (Claude Code)"* ]]
  [[ "$output" == *"changed repo alpha:"* ]]
}

@test "pty helpers capture terminal-only output and time key echo" {
  run python3 "$SCRIPTS/pty_capture.py" --timeout 10 --quiet 1 -- sh -c 'test -t 1 && printf "\033[1mtty-ok\033[0m\n"'
  [ "$status" -eq 0 ]
  [ "$output" = "tty-ok" ]

  run python3 "$SCRIPTS/echo_latency.py" --chars 5 --interval 0.02 --settle 0.2 -- cat
  [ "$status" -eq 0 ]
  [[ "$output" == 'echo-latency command="cat" n=5 median_ms='* ]]
  [[ "$output" == *"timeouts=0"* ]]
}

@test "background audit classifies jobs without touching launchd" {
  local agents="$TEST_DIR/LaunchAgents"
  mkdir -p "$agents"
  write_plist() {
    cat > "$agents/$1.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$1</string>
<key>ProgramArguments</key><array><string>$2</string><string>$3</string></array>
</dict></plist>
EOF
  }
  write_plist com.example.gone /nonexistent/bin/tool run
  write_plist com.example.one /bin/sh same-args
  write_plist com.example.two /bin/sh same-args
  write_plist com.minsky.daemon /bin/sh minsky
  write_plist com.dotfiles.ok /bin/sh ok
  write_plist com.example.crashy /bin/sh crash
  printf 'PID\tStatus\tLabel\n123\t0\tcom.minsky.daemon\n-\t0\tcom.dotfiles.ok\n-\t78\tcom.example.crashy\n' > "$TEST_DIR/launchctl.txt"

  run env BACKGROUND_AUDIT_DIRS="$agents" BACKGROUND_AUDIT_LAUNCHCTL="$TEST_DIR/launchctl.txt" \
    BACKGROUND_AUDIT_TOP=0 DOTFILES_SOURCE="$TEST_DIR/none" bash "$SCRIPTS/background_audit.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"remove    third-party com.example.gone unloaded"* ]]
  [[ "$output" == *"duplicate third-party com.example.one"* ]]
  [[ "$output" == *"duplicate third-party com.example.two"* ]]
  [[ "$output" == *"off-rule  minsky      com.minsky.daemon pid=123"* ]]
  [[ "$output" == *"keep      dotfiles    com.dotfiles.ok"* ]]
  [[ "$output" == *"failing   third-party com.example.crashy pid=- last_exit=78"* ]]
}

@test "input latency guide checks the Claude scheduling band first" {
  local guide="$SKILL_DIR/reference/input-latency.md"
  grep -q '^1\. \*\*Scheduling band\.\*\*' "$guide"
  grep -q 'PRI 4' "$guide"
  grep -q 'taskpolicy -B -t 0 -l 0 -p' "$guide"
  grep -q 'bin/cursor-priority' "$guide"
}

# Fake agentbrew perf CLI: prints $PERF_FIXTURES/<all|project>.json for `report`.
make_perf_fixtures() {
  PERF_FIXTURES="$TEST_DIR/perf"
  mkdir -p "$PERF_FIXTURES/log"
  cat > "$PERF_FIXTURES/agent-perf.mjs" <<'JS'
import fs from 'fs'
const a = process.argv.slice(2)
const i = a.indexOf('--project')
const name = i === -1 ? 'all' : a[i + 1]
process.stdout.write(fs.readFileSync(`${process.env.PERF_FIXTURES}/${name}.json`, 'utf8'))
JS
  cat > "$PERF_FIXTURES/session-report.mjs" <<'JS'
process.stdout.write(JSON.stringify({ overall: { sessions: 4, hours: { active: 3.5, wall_clock: 9 },
  input_tokens: { total: 5e6, pct_cached: 90 }, output_tokens: 2e5 },
  top_prompts: [{ text: 'SECRET-PROMPT-TEXT' }] }))
JS
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # Tool rows: each recurring step appears in 2 sessions, so it can become a task.
  {
    printf '{"ts":"%s","project":"alpha","sid":"s1","key":"npm ci","ms":5}\n' "$now"
    printf '{"ts":"%s","project":"alpha","sid":"s2","key":"npm ci","ms":5}\n' "$now"
    printf '{"ts":"%s","project":"other","sid":"s1","key":"until <arg>","ms":5}\n' "$now"
    printf '{"ts":"%s","project":"other","sid":"s3","key":"until <arg>","ms":5}\n' "$now"
    printf '{"ts":"%s","project":"other","sid":"s1","key":"npm test","ms":5}\n' "$now"
    printf '{"ts":"%s","project":"other","sid":"s2","key":"npm test","ms":5}\n' "$now"
    printf '{"ts":"2001-01-01T00:00:00Z","project":"ancient","sid":"s9","key":"npm ci","ms":5}\n'
  } > "$PERF_FIXTURES/log/2026-10.jsonl"
  local npm='{"key":"npm ci","count":14,"sumMs":840000,"p50Ms":60000,"p95Ms":70000,"maxMs":70000,"failures":0}'
  local poll='{"key":"until <arg>","count":3,"sumMs":900000,"p50Ms":300000,"p95Ms":300000,"maxMs":300000,"failures":0}'
  local quick='{"key":"git status","count":9,"sumMs":900,"p50Ms":100,"p95Ms":120,"maxMs":120,"failures":0}'
  printf '{"toolMs":1740900,"calls":26,"failures":0,"keys":[%s,%s,%s],"slowest":[{"key":"until <arg>","ms":300000}],"previous":{"toolMs":870450,"toolMsChangePct":100}}' \
    "$npm" "$poll" "$quick" > "$PERF_FIXTURES/all.json"
  printf '{"toolMs":840900,"calls":23,"keys":[%s,%s]}' "$npm" "$quick" > "$PERF_FIXTURES/alpha.json"
  printf '{"toolMs":900000,"calls":3,"keys":[%s]}' "$poll" > "$PERF_FIXTURES/other.json"
  export PERF_FIXTURES AGENT_PERF_SCRIPT="$PERF_FIXTURES/agent-perf.mjs" \
    SESSION_REPORT_SCRIPT="$PERF_FIXTURES/session-report.mjs" AGENT_PERF_DIR="$PERF_FIXTURES/log" \
    TOOLING_CHECKUP_STATE_DIR="$TEST_DIR/state"
}

@test "time review lists slow recurring steps, fixes, tasks, and metrics" {
  command -v node >/dev/null || skip "node not installed"
  make_tooling_root
  make_perf_fixtures

  run env TOOLING_ROOT="$TOOLING" python3 "$SCRIPTS/agent_time_review.py" --days 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"tool time 29m00s over 26 calls (0 failed); previous window 14m30s (+100%)"* ]]
  [[ "$output" == *"sessions 4, active 3.5 h"* ]]
  [[ "$output" == *"1. until <arg>: 15m00s total, 3x"* ]]
  [[ "$output" == *"fix: polling loop"* ]]
  [[ "$output" == *"fix: repeated full install"* ]]
  [[ "$output" == *"slowest single call: until <arg> 5m00s"* ]]
  [[ "$output" == *"file    alpha speed-up-npm-ci: npm ci costs 2m00s/day"* ]]
  [[ "$output" == *"inspect other speed-up-until-arg"* ]]
  [[ "$output" != *"git status costs"* ]]
  [[ "$output" != *"ancient"* ]]
  [[ "$output" != *"SECRET-PROMPT-TEXT"* ]]
  [[ "$output" == *"--metric agent_tool_hours_7d=0.48"* ]]
  [[ "$output" == *"--metric slowest_step_p95_s=300.0"* ]]
  [[ "$output" == *"--metric 'top_step_key=until <arg>'"* ]]
  [[ "$output" == *"agent_active_hours_7d: none -> 3.5"* ]]
}

@test "time review suggests a task only for a step seen in 2+ sessions" {
  command -v node >/dev/null || skip "node not installed"
  make_tooling_root
  make_perf_fixtures
  local now
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  # alpha "npm ci": 3 calls, all in one session. other "until <arg>": 2 sessions.
  {
    printf '{"ts":"%s","project":"alpha","sid":"only","key":"npm ci","ms":5}\n' "$now" "$now" "$now"
    printf '{"ts":"%s","project":"other","sid":"s1","key":"until <arg>","ms":5}\n' "$now"
    printf '{"ts":"%s","project":"other","sid":"s2","key":"until <arg>","ms":5}\n' "$now"
  } > "$PERF_FIXTURES/log/2026-10.jsonl"

  run env TOOLING_ROOT="$TOOLING" python3 "$SCRIPTS/agent_time_review.py" --days 7 --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq '[.tasks[] | select(.sessions < 2)] | length')" -eq 0 ]
  [ "$(printf '%s' "$output" | jq '[.tasks[] | select(.key == "npm ci")] | length')" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.tasks[] | select(.key == "until <arg>") | .sessions')" -eq 2 ]

  run env TOOLING_ROOT="$TOOLING" python3 "$SCRIPTS/agent_time_review.py" --days 7
  [ "$status" -eq 0 ]
  [[ "$output" != *"speed-up-npm-ci"* ]]
  [[ "$output" == *"inspect other speed-up-until-arg"*"in 2 sessions"* ]]
}

@test "time review marks filed tasks and reports non-tooling projects only" {
  command -v node >/dev/null || skip "node not installed"
  make_tooling_root
  make_perf_fixtures
  printf '#### speed-up-npm-ci\n' > "$TOOLING/alpha/TASKS.md"
  printf '{"toolMs":900000,"calls":3,"keys":[{"key":"npm test","count":3,"sumMs":900000,"p95Ms":300000}]}' \
    > "$PERF_FIXTURES/other.json"

  run env TOOLING_ROOT="$TOOLING" python3 "$SCRIPTS/agent_time_review.py" --days 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"filed   alpha speed-up-npm-ci"* ]]
  [[ "$output" == *"report  other speed-up-npm-test"*"fix: full gate or test run"* ]]

  run env TOOLING_ROOT="$TOOLING" AGENT_PERF_SCRIPT="$TEST_DIR/missing.mjs" python3 "$SCRIPTS/agent_time_review.py"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no agent-perf data"* ]]
}

@test "machine metrics flag overload and skip the echo test without a lag signal" {
  local now=1792153670 samples="$TEST_DIR/load.tsv" ps_file="$TEST_DIR/ps.txt"
  : > "$samples"
  for i in $(seq 0 11); do
    printf '%s\t2026-10-16T08:%02d:00\t35.0\t30.0\t20.0\t10\t40\t1200\t800\tnode:90.1 WindowServer:40.2 mds:10.0\t90\n' \
      "$((now - 3600 + i * 30))" "$i" >> "$samples"
  done
  printf '%s\t2026-10-16T09:00:00\t3.0\t3.0\t3.0\t10\t60\t1200\t800\tclaude:5.0\t10\n' "$now" >> "$samples"
  printf '  PID PRI TTY      COMM\n 26082   4 ??       /Users/x/.local/bin/claude\n 3001  31 ttys001  claude\n' > "$ps_file"
  echo '{"metrics": {"claude_echo_p95_ms": "11.5"}}' > "$TEST_DIR/state.json"

  run python3 "$SCRIPTS/machine_metrics.py" --now "$now" --samples "$samples" --ps-file "$ps_file" \
    --state "$TEST_DIR/state.json" --claude-json "$TEST_DIR/none.json" --upgrade-log "$TEST_DIR/none.log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"act     load_overload_rows "*" 12 "*"node x12"* ]]
  [[ "$output" == *"ok      load_overload_rows_explained"*" 0 "* ]]
  [[ "$output" == *"claude_sessions"*" 1 "* ]]
  [[ "$output" == *"ok      claude_background_pri"*" 0 "* ]]
  [[ "$output" == *"latency-check: skip (no trigger)"* ]]
  [[ "$output" == *"--metric machine_overload_rows_24h=12"* ]]
}

@test "machine metrics count overload explained by a known app apart, without act" {
  local now=1792153670 samples="$TEST_DIR/load.tsv" ps_file="$TEST_DIR/ps.txt"
  : > "$samples"
  # 12 rows led by GeForceNOW, 2 led by WindowServer with GeForceNOW second,
  # 3 unexplained rows led by node.
  for i in $(seq 0 11); do
    printf '%s\t2026-10-16T08:%02d:00\t35.0\t30.0\t20.0\t10\t40\t1200\t800\tGeForceNOW:90.1 WindowServer:40.2 mds:10.0\t90\n' \
      "$((now - 3600 + i * 30))" "$i" >> "$samples"
  done
  for i in 12 13; do
    printf '%s\t2026-10-16T08:%02d:00\t35.0\t30.0\t20.0\t10\t40\t1200\t800\tWindowServer:40.2 GeForceNOW:30.1 mds:10.0\t90\n' \
      "$((now - 3600 + i * 30))" "$i" >> "$samples"
  done
  for i in 14 15 16; do
    printf '%s\t2026-10-16T08:%02d:00\t35.0\t30.0\t20.0\t10\t40\t1200\t800\tnode:90.1 git:20.0\t90\n' \
      "$((now - 3600 + i * 30))" "$i" >> "$samples"
  done
  printf '  PID PRI TTY      COMM\n' > "$ps_file"
  local common=(--now "$now" --samples "$samples" --ps-file "$ps_file" --state "$TEST_DIR/none.json"
    --claude-json "$TEST_DIR/none.json" --upgrade-log "$TEST_DIR/none.log" --explained-file "$TEST_DIR/none.txt")

  run env -u DOTFILES_EXPLAINED_LOAD python3 "$SCRIPTS/machine_metrics.py" "${common[@]}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"warn    load_overload_rows "*" 3 "*"node x3"* ]]
  [[ "$output" == *"warn    load_overload_rows_explained"*" 14 "*"GeForceNOW x14"* ]]
  [[ "$output" == *"--metric machine_overload_rows_24h=3"* ]]
  [[ "$output" == *"--metric machine_overload_rows_explained_24h=14"* ]]

  # An empty env list turns the default off: all 17 rows are unexplained.
  run env DOTFILES_EXPLAINED_LOAD= python3 "$SCRIPTS/machine_metrics.py" "${common[@]}"
  [[ "$output" == *"act     load_overload_rows "*" 17 "* ]]

  # The file adds names to the list.
  printf '# streaming and builds\nnode\n' > "$TEST_DIR/explained.txt"
  run env -u DOTFILES_EXPLAINED_LOAD python3 "$SCRIPTS/machine_metrics.py" "${common[@]}" --explained-file "$TEST_DIR/explained.txt"
  [[ "$output" == *"ok      load_overload_rows "*" 0 "* ]]
  [[ "$output" == *"load_overload_rows_explained"*" 17 "* ]]
}

@test "machine metrics trigger the echo test for a PRI 4 terminal session or reported lag" {
  local ps_file="$TEST_DIR/ps.txt"
  printf '  PID PRI TTY      COMM\n 3001   4 ttys001  claude\n' > "$ps_file"
  run python3 "$SCRIPTS/machine_metrics.py" --samples "$TEST_DIR/none.tsv" --ps-file "$ps_file" \
    --state "$TEST_DIR/none.json" --claude-json "$TEST_DIR/none.json" --upgrade-log "$TEST_DIR/none.log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"act     claude_background_pri"*"pids 3001"* ]]
  [[ "$output" == *"latency-check: run (1 session(s) at PRI 4)"* ]]

  printf '  PID PRI TTY      COMM\n' > "$ps_file"
  run python3 "$SCRIPTS/machine_metrics.py" --lag-reported --samples "$TEST_DIR/none.tsv" --ps-file "$ps_file" \
    --state "$TEST_DIR/none.json" --claude-json "$TEST_DIR/none.json" --upgrade-log "$TEST_DIR/none.log" --json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.latency_check.run' <<<"$output")" = "true" ]
  [ "$(jq -r '.latency_check.triggers[0]' <<<"$output")" = "the user reported lag" ]
}
