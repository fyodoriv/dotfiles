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
  grep -F -q 'audit_agent_config.py --cache' "$SKILL"
  grep -F -q 'AskUserQuestion' "$SKILL"
  grep -F -q 'checkup_state.py record' "$SKILL"
  [ "$(grep -c '^\*\*Done when:\*\*' "$SKILL")" -eq 10 ]
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
