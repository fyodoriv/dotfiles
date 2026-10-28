#!/usr/bin/env bats

load test_helper

# Resolve the path: the audit skips any path with a `tests` part, so
# "tests/.." would make it see 0 skills.
ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
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
  [[ "$output" == *"audit: 1 skill(s)"* ]]
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
  grep -F -q '### Agent time (7 days)' "$SKILL_DIR/reference/report-outline.md"
  grep -F -q 'runs all twelve phases' "$SKILL"
  [ "$(grep -c '^## Phase ' "$SKILL")" -eq 12 ]
  [ "$(grep -c '^\*\*Done when:\*\*' "$SKILL")" -eq 12 ]
}

@test "tooling-checkup monthly pass covers health, cached gate, stories, speed, learnings, and P0s" {
  grep -F -q 'reference/monthly-repo-health.md' "$SKILL"
  grep -F -q 'bin/dotfiles-doctor --quiet' "$SKILL_DIR/reference/monthly-repo-health.md"
  grep -F -q 'Cached gate: `make check`' "$SKILL_DIR/reference/monthly-repo-health.md"
  grep -F -q 'Broken stories: `make e2e`' "$SKILL_DIR/reference/monthly-repo-health.md"
  grep -F -q 'gate-timings.jsonl' "$SKILL_DIR/reference/monthly-repo-health.md"
  grep -F -q 'bin/dotfiles-metrics --table' "$SKILL_DIR/reference/monthly-repo-health.md"
  grep -F -q 'docs/learnings.md' "$SKILL_DIR/reference/monthly-repo-health.md"
  grep -F -q 'Open P0s' "$SKILL_DIR/reference/monthly-repo-health.md"
  grep -F -q 'Repo health (monthly):' "$SKILL_DIR/reference/report-outline.md"
  grep -F -q 'make changelog' "$SKILL_DIR/reference/monthly-repo-health.md"
}

@test "tooling-checkup config hygiene covers duplicates, memory, hooks, and new skills" {
  grep -F -q 'reference/config-hygiene.md' "$SKILL"
  grep -F -q '## One home per fact' "$SKILL_DIR/reference/config-hygiene.md"
  grep -F -q '## Memory hygiene' "$SKILL_DIR/reference/config-hygiene.md"
  grep -F -q '## Hooks' "$SKILL_DIR/reference/config-hygiene.md"
  grep -F -q '## New upstream skills' "$SKILL_DIR/reference/config-hygiene.md"
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

@test "inventory labels draft pull requests so Phase 2 finishes their Pending list" {
  make_tooling_root
  git_q -C "$TOOLING/alpha" remote set-url origin https://github.com/acme/alpha.git
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/gh" <<'EOF2'
#!/bin/sh
case "$1" in
  pr) printf '5\tfyodor\tfeat/ready\topen\tsame\tReady work\n6\tfyodor\twip/parked\tdraft\tsame\tParked work\n' ;;
  api) case "$*" in *" user "*) echo fyodor ;; *) exit 1 ;; esac ;;
  *) exit 1 ;;
esac
EOF2
  chmod +x "$TEST_DIR/bin/gh"

  run env -u BASH_ENV -u ENV PATH="$TEST_DIR/bin:$PATH" TOOLING_ROOT="$TOOLING" TOOLING_CHECKUP_NO_FETCH=1 \
    bash "$SCRIPTS/inventory.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ship      PR #5 feat/ready: Ready work"* ]]
  [[ "$output" == *"ship      draft PR #6 wip/parked: Parked work (finish its ## Pending list)"* ]]
}

# A gh stub that logs "GH_HOST=<value> <args>" for each call. `gh auth status
# --hostname H` passes only for a host listed in FAKE_GH_AUTH_HOSTS.
write_fake_gh() {
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/gh" <<EOF2
#!/bin/sh
echo "GH_HOST=\${GH_HOST:-} \$*" >> "$TEST_DIR/gh.log"
case "\$1 \$2" in
  "auth status")
    case " \${FAKE_GH_AUTH_HOSTS:-} " in *" \$4 "*) exit 0 ;; esac
    exit 1 ;;
  "pr list") printf '7\tfyodor\tfeat/ghe\topen\tsame\tEnterprise work\n' ;;
  "api "*) case "\$*" in *" user "*) echo fyodor ;; esac ;;
  *) exit 1 ;;
esac
EOF2
  chmod +x "$TEST_DIR/bin/gh"
}

# Run the inventory for one checkout whose origin is $1, with the gh stub.
run_inventory_with_origin() {
  make_tooling_root
  git_q -C "$TOOLING/alpha" remote set-url origin "$1"
  write_fake_gh
  run env -u BASH_ENV -u ENV PATH="$TEST_DIR/bin:$PATH" TOOLING_ROOT="$TOOLING" TOOLING_CHECKUP_NO_FETCH=1 \
    bash "$SCRIPTS/inventory.sh"
}

@test "inventory checks pull requests on a GitHub Enterprise ssh origin (issue #256)" {
  FAKE_GH_AUTH_HOSTS="github.example.com" run_inventory_with_origin "git@github.example.com:acme/alpha.git"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ship      PR #7 feat/ghe: Enterprise work"* ]]
  [[ "$output" != *"not a GitHub remote"* ]]
  grep -qxF "GH_HOST= auth status --hostname github.example.com" "$TEST_DIR/gh.log"
  grep -q "^GH_HOST=github.example.com pr list -R acme/alpha " "$TEST_DIR/gh.log"
  grep -q "^GH_HOST= api --hostname github.example.com --paginate repos/acme/alpha/dependabot/alerts" "$TEST_DIR/gh.log"
}

@test "inventory parses https and ssh:// enterprise origins into host and slug" {
  TOOLING_CHECKUP_GH_HOSTS="other.example.com,github.example.com" \
    run_inventory_with_origin "https://github.example.com/acme/alpha.git"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ship      PR #7 feat/ghe: Enterprise work"* ]]
  grep -q "^GH_HOST=github.example.com pr list -R acme/alpha " "$TEST_DIR/gh.log"
  # A host listed in TOOLING_CHECKUP_GH_HOSTS needs no gh auth status call.
  ! grep -q "auth status" "$TEST_DIR/gh.log"

  rm -rf "$TEST_DIR/tooling" "$TEST_DIR/origin.git" "$TEST_DIR/gh.log"
  FAKE_GH_AUTH_HOSTS="github.example.com" \
    run_inventory_with_origin "ssh://git@github.example.com:2222/acme/alpha.git"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ship      PR #7 feat/ghe: Enterprise work"* ]]
  grep -q "^GH_HOST=github.example.com pr list -R acme/alpha " "$TEST_DIR/gh.log"
}

@test "inventory skips a host gh is not logged in to and says how to add it" {
  run_inventory_with_origin "git@git.example.com:acme/alpha.git"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown   origin host git.example.com is not github.com and gh is not logged in to it"* ]]
  [[ "$output" == *"TOOLING_CHECKUP_GH_HOSTS"* ]]
  grep -qxF "GH_HOST= auth status --hostname git.example.com" "$TEST_DIR/gh.log"
  ! grep -q "pr list" "$TEST_DIR/gh.log"
}

@test "inventory sends github.com origins to github.com without an auth check" {
  run_inventory_with_origin "https://github.com/acme/alpha.git"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ship      PR #7 feat/ghe: Enterprise work"* ]]
  grep -q "^GH_HOST=github.com pr list -R acme/alpha " "$TEST_DIR/gh.log"
  grep -q "^GH_HOST= api --hostname github.com --paginate repos/acme/alpha/" "$TEST_DIR/gh.log"
  ! grep -q "auth status" "$TEST_DIR/gh.log"
}

# Two checkouts on an enterprise host, each with its own PR and PRs by other
# people. Mirrors the 2026-10-21 checkup, which listed outside fork PRs
# agentbrew #352 and dotfiles #242 as `ship` (issue #267). FAKE_GH_LOGIN is
# what `gh api user` prints; empty makes that call fail.
run_inventory_with_outside_prs() {
  TOOLING="$TEST_DIR/tooling"
  mkdir -p "$TOOLING" "$TEST_DIR/bin"
  local name
  for name in agentbrew dotfiles; do
    git_q init --bare "$TEST_DIR/$name.git"
    git_q clone "$TEST_DIR/$name.git" "$TOOLING/$name"
    git_q -C "$TOOLING/$name" commit --allow-empty -m "chore: init"
    git_q -C "$TOOLING/$name" push origin HEAD:main
    git_q -C "$TOOLING/$name" remote set-head origin main
    git_q -C "$TOOLING/$name" remote set-url origin "git@github.example.com:owner-me/$name.git"
  done
  cat > "$TEST_DIR/bin/gh" <<'EOF2'
#!/bin/sh
echo "$*" >> "${0%/bin/gh}/gh.log"
case "$*" in
  "api --hostname github.example.com user --jq .login")
    [ -n "$FAKE_GH_LOGIN" ] || exit 1
    echo "$FAKE_GH_LOGIN" ;;
  "pr list -R owner-me/agentbrew "*)
    printf '352\tfork-dev\teval/goal-dashboard\topen\tfork\ttest(run-goal): eval for a dashboard goal\n'
    printf '353\towner-me\tfeat/own-work\topen\tsame\tfeat: own work\n' ;;
  "pr list -R owner-me/dotfiles "*)
    printf '242\tfork-dev\tdocs/keep-awake\tdraft\tfork\tdocs(tasks): keep awake\n'
    printf '243\tteam-mate\tfix/shared-branch\topen\tsame\tfix: a teammate branch\n'
    printf '244\towner-me\tfeat/from-my-fork\topen\tfork\tfeat: pushed from a fork\n' ;;
  "api "*) exit 0 ;;
  *) exit 1 ;;
esac
EOF2
  chmod +x "$TEST_DIR/bin/gh"
  run env -u BASH_ENV -u ENV PATH="$TEST_DIR/bin:$PATH" TOOLING_ROOT="$TOOLING" TOOLING_CHECKUP_NO_FETCH=1 \
    TOOLING_CHECKUP_GH_HOSTS=github.example.com FAKE_GH_LOGIN="${FAKE_GH_LOGIN-owner-me}" \
    bash "$SCRIPTS/inventory.sh"
}

@test "inventory gives other authors' and fork PRs a review verdict, never ship (issue #267)" {
  run_inventory_with_outside_prs
  [ "$status" -eq 0 ]
  [[ "$output" == *"ship      PR #353 feat/own-work: feat: own work"* ]]
  [[ "$output" == *"review    PR #352 eval/goal-dashboard by fork-dev from a fork: test(run-goal): eval for a dashboard goal (owner decides; never merge it)"* ]]
  [[ "$output" == *"review    draft PR #242 docs/keep-awake by fork-dev from a fork: docs(tasks): keep awake (owner decides; never merge it)"* ]]
  [[ "$output" == *"review    PR #243 fix/shared-branch by team-mate: fix: a teammate branch (owner decides; never merge it)"* ]]
  [[ "$output" == *"review    PR #244 feat/from-my-fork by owner-me from a fork: feat: pushed from a fork (owner decides; never merge it)"* ]]
  # Only the own same-repo PR is outstanding work.
  [ "$(grep -c '^  ship ' <<< "$output")" -eq 1 ]
  # gh api user runs once per host, not once per checkout or PR.
  [ "$(grep -c '^api --hostname github.example.com user' "$TEST_DIR/gh.log")" -eq 1 ]
  # Phase 2 tells the agent what to do with a review line.
  grep -F -q '| `review` |' "$SKILL"
}

@test "inventory never says ship for a PR when it cannot read the gh login" {
  FAKE_GH_LOGIN="" run_inventory_with_outside_prs
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown   PR #353 feat/own-work by owner-me: feat: own work (could not read your gh login on github.example.com; check the author by hand)"* ]]
  ! grep -q '^  ship ' <<< "$output"
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
  write_plist com.dotfiles-acme.agent-chrome-heal /bin/sh heal
  write_plist com.acme.sync /bin/sh acme-sync
  write_plist com.dotfiles-lookalike.helper /bin/sh other
  # The labels dotfiles recorded when it installed plugin acme's agents.
  mkdir -p "$TEST_DIR/state/dotfiles/plugins"
  printf 'com.dotfiles-acme.agent-chrome-heal\ncom.acme.sync\n' > "$TEST_DIR/state/dotfiles/plugins/acme.launchagents"
  printf 'PID\tStatus\tLabel\n123\t0\tcom.minsky.daemon\n-\t0\tcom.dotfiles.ok\n-\t78\tcom.example.crashy\n-\t0\tcom.dotfiles-acme.agent-chrome-heal\n' > "$TEST_DIR/launchctl.txt"

  run env BACKGROUND_AUDIT_DIRS="$agents" BACKGROUND_AUDIT_LAUNCHCTL="$TEST_DIR/launchctl.txt" \
    BACKGROUND_AUDIT_TOP=0 DOTFILES_SOURCE="$TEST_DIR/none" XDG_STATE_HOME="$TEST_DIR/state" bash "$SCRIPTS/background_audit.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"remove    third-party com.example.gone unloaded"* ]]
  [[ "$output" == *"duplicate third-party com.example.one"* ]]
  [[ "$output" == *"duplicate third-party com.example.two"* ]]
  [[ "$output" == *"off-rule  minsky      com.minsky.daemon pid=123"* ]]
  [[ "$output" == *"keep      dotfiles    com.dotfiles.ok"* ]]
  [[ "$output" == *"failing   third-party com.example.crashy pid=- last_exit=78"* ]]
  # A dotfiles plugin's job (com.dotfiles-<plugin>.*) is tooling, not third-party (#309).
  [[ "$output" == *"keep      dotfiles-plugin com.dotfiles-acme.agent-chrome-heal"* ]]
  [[ "$output" == *"dotfiles-plugin com.acme.sync"* ]]
  [[ "$output" == *"third-party com.dotfiles-lookalike.helper"* ]]
}

@test "input latency guide checks the Claude scheduling band first" {
  local guide="$SKILL_DIR/reference/input-latency.md"
  grep -q '^1\. \*\*Scheduling band\.\*\*' "$guide"
  grep -q 'PRI 4' "$guide"
  grep -q 'taskpolicy -B -t 0 -l 0 -p' "$guide"
  grep -q 'bin/app-priority' "$guide"
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

@test "time review keeps background subagents out of the ranking and the tasks" {
  command -v node >/dev/null || skip "node not installed"
  make_tooling_root
  make_perf_fixtures
  local now before
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  before="$(python3 -c 'import datetime as d; print((d.datetime.now(d.timezone.utc) - d.timedelta(seconds=60)).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
  # agent:Explore blocked the lead (no lead call during it). agent:general-purpose
  # overlapped a lead call (s1) or was a marked background launch (s2).
  {
    printf '{"ts":"%s","project":"alpha","sid":"s5","key":"agent:Explore","ms":600000}\n' "$now"
    printf '{"ts":"%s","project":"alpha","sid":"s6","key":"agent:Explore","ms":600000}\n' "$now"
    # A parallel subagent ending inside s6's Explore run is not lead work.
    printf '{"ts":"%s","project":"alpha","sid":"s6","key":"agent:Plan","ms":5}\n' "$before"
    printf '{"ts":"%s","project":"alpha","sid":"s1","key":"git status","ms":5}\n' "$before"
    printf '{"ts":"%s","project":"alpha","sid":"s1","key":"agent:general-purpose","ms":600000}\n' "$now"
    printf '{"ts":"%s","project":"alpha","sid":"s2","key":"agent:general-purpose","ms":600000,"bg":true}\n' "$now"
  } > "$PERF_FIXTURES/log/2026-10.jsonl"
  local fg='{"key":"agent:Explore","count":2,"sumMs":1200000,"p95Ms":600000}'
  local bg='{"key":"agent:general-purpose","count":2,"sumMs":1200000,"p95Ms":600000}'
  printf '{"toolMs":2400000,"calls":4,"keys":[%s,%s],"slowest":[{"key":"agent:general-purpose","ms":600001}]}' "$bg" "$fg" \
    > "$PERF_FIXTURES/all.json"
  cp "$PERF_FIXTURES/all.json" "$PERF_FIXTURES/alpha.json"

  run env TOOLING_ROOT="$TOOLING" python3 "$SCRIPTS/agent_time_review.py" --days 7
  [ "$status" -eq 0 ]
  [[ "$output" == *"background subagents (overlap the lead, not ranked): 2x, 20m00s total"* ]]
  [[ "$output" == *"1. agent:Explore: 20m00s total, 2x"* ]]
  [[ "$output" == *"tool time 20m00s over 2 calls"* ]]
  [[ "$output" == *"file    alpha speed-up-agent-explore"* ]]
  [[ "$output" != *"agent:general-purpose"* ]]
  [[ "$output" != *"speed-up-agent-general-purpose"* ]]
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

@test "machine metrics name the owner of unexplained overload from the sampler owners column (#358)" {
  local now=1792153670 samples="$TEST_DIR/load.tsv" ps_file="$TEST_DIR/ps.txt"
  : > "$samples"
  for i in $(seq 0 5); do
    printf '%s\t2026-10-16T08:%02d:00\t35.0\t30.0\t20.0\t10\t40\t1200\t800\tnode:90.1 mds:10.0\t90\t501/400/claude/node /r/node_modules/.bin/vitest run | 502/1/launchd//usr/libexec/mds\n' \
      "$((now - 3600 + i * 30))" "$i" >> "$samples"
  done
  printf '  PID PRI TTY      COMM\n' > "$ps_file"
  run env -u DOTFILES_EXPLAINED_LOAD python3 "$SCRIPTS/machine_metrics.py" --now "$now" --samples "$samples" --ps-file "$ps_file" \
    --state "$TEST_DIR/none.json" --claude-json "$TEST_DIR/none.json" --upgrade-log "$TEST_DIR/none.log" --explained-file "$TEST_DIR/none.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"node (vitest, parent claude) x6"* ]]
  [[ "$output" == *"mds (parent launchd) x6"* ]]
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

@test "AI-work research phase uses the ambition lenses and records seen items" {
  grep -F -q '## Phase 9: AI-work research' "$SKILL"
  grep -F -q 'ai_research.py scan' "$SKILL"
  grep -F -q 'ai_research.py record' "$SKILL"
  grep -F -q '### AI-work research' "$SKILL_DIR/reference/report-outline.md"
  local ref="$SKILL_DIR/reference/ai-work-research.md"
  grep -F -q '| Altitude |' "$ref"
  grep -F -q '| Depth |' "$ref"
  grep -F -q '| Range |' "$ref"
  grep -F -q 'outside judge' "$ref"
  grep -F -q 'outside the agent sandbox' "$ref"
}

@test "AI research scan lists only unseen feed items and record marks them seen" {
  local feeds="$TEST_DIR/feeds" now
  mkdir -p "$feeds"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cat > "$feeds/atom.xml" <<XML
<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry><title>Fresh atom post</title><link rel="alternate" href="https://a.example.com/fresh"/><updated>$now</updated></entry>
  <entry><title>Old atom post</title><link href="https://a.example.com/old"/><updated>2001-01-01T00:00:00Z</updated></entry>
</feed>
XML
  cat > "$feeds/rss.xml" <<XML
<?xml version="1.0"?>
<rss version="2.0"><channel>
  <item><title>Undated rss post</title><link>https://r.example.com/one</link></item>
</channel></rss>
XML
  export TOOLING_CHECKUP_STATE_DIR="$TEST_DIR/state"
  export TOOLING_CHECKUP_AI_FEEDS="atom file://$feeds/atom.xml
rss file://$feeds/rss.xml
broken file://$feeds/missing.xml"

  run python3 "$SCRIPTS/ai_research.py" scan
  [ "$status" -eq 0 ]
  [[ "$output" == *"new: "*" atom | Fresh atom post | https://a.example.com/fresh"* ]]
  [[ "$output" == *"new: undated rss | Undated rss post | https://r.example.com/one"* ]]
  [[ "$output" != *"Old atom post"* ]]
  [[ "$output" == *"source: broken error:"* ]]
  [[ "$output" == *"research: 2 new item(s), 1 feed error(s)"* ]]
  [[ "$output" == *"record: --metric ai_research_new=2"* ]]

  run python3 "$SCRIPTS/ai_research.py" record
  [ "$status" -eq 0 ]
  [[ "$output" == *"recorded: 2 item(s) as seen"* ]]

  run python3 "$SCRIPTS/ai_research.py" scan
  [ "$status" -eq 0 ]
  [[ "$output" == *"research: 0 new item(s)"* ]]
  ! grep -q "$TEST_HOME" "$TEST_DIR/state/ai-research-seen.json"
}

@test "tooling-checkup gets a contributor's own PRs green without merging them" {
  grep -q '^### Your pull requests on tooling repos you do not own' "$SKILL_DIR/SKILL.md"
  grep -q 'gh pr list --repo <owner/repo> --author @me --state open' "$SKILL_DIR/SKILL.md"
  grep -q 'viewerPermission' "$SKILL_DIR/SKILL.md"
}

@test "contributor PR step leaves the owner's checkup and history alone" {
  # The owner's own repos skip the step, so the owner's run is unchanged.
  grep -F -q 'gh api user --jq .login' "$SKILL_DIR/SKILL.md"
  grep -F -q 'Skip a repo you own' "$SKILL_DIR/SKILL.md"
  # A fork checkout lists PRs on its parent repo.
  grep -F -q 'parent' "$SKILL_DIR/SKILL.md"
  # Conflicts merge the default branch in; no force-push.
  ! grep -q 'force-with-lease' "$SKILL_DIR/SKILL.md"
  # The fast path must not skip Phase 2 while a contributor PR is open.
  grep -F -q 'no open pull request of yours' "$SKILL_DIR/SKILL.md"
}

@test "tooling-checkup tries to finish open PRs on the owner's repos" {
  grep -q '^### Open pull requests on your repos' "$SKILL_DIR/SKILL.md"
  grep -F -q '`ship` on a `PR #N` line' "$SKILL_DIR/SKILL.md"
  # A wrap-up draft continues from its Pending list.
  grep -F -q '## Pending' "$SKILL_DIR/SKILL.md"
  ! grep -q 'force-with-lease' "$SKILL_DIR/SKILL.md"
  # Drafts are worked in a worktree; person-only items go to the questionnaire.
  grep -F -q 'in a new worktree (never the live checkout)' "$SKILL_DIR/SKILL.md"
  grep -F -q 'Phase 11' "$SKILL_DIR/SKILL.md"
  grep -F -q 'gh pr ready <n>' "$SKILL_DIR/SKILL.md"
}

@test "tooling-checkup applies before the upgrade and checks the upgrade log" {
  grep -q 'Finish Phase 3 before you start Phase 4' "$SKILL"
  grep -q 'dotfiles-lock-checked --log' "$SKILL"
  grep -q 'dotfiles-lock-checked' "$SKILL_DIR/reference/machine-updates.md"
}

@test "tooling-checkup passes --yes to dotfiles-upgrade (the checkup is the owner's yes)" {
  grep -qF 'bin/dotfiles-upgrade" --yes' "$SKILL_DIR/reference/machine-updates.md"
}

@test "tooling-checkup resolves new-project from its source when not installed" {
  grep -q "\[ -d \"\$NP\" \] || NP=" "$SKILL"
}

@test "tooling-checkup ends with a local HTML page and one in-place dashboard, then asks" {
  local skill="$BATS_TEST_DIRNAME/../skills/tooling-checkup/SKILL.md"
  grep -q "one local HTML page for this run, and one shared tooling health" "$skill"
  grep -q "Never publish a new page per run" "$skill"
  grep -q "dashboard_export.py" "$skill"
  grep -q "dashboard-url" "$skill"
  grep -q "Ask from the page" "$skill"
  [ -f "$SKILL_DIR/dashboard/index.html" ]
  [ -f "$SKILL_DIR/reference/dashboard.md" ]
  run jq -e '[.evals[] | select(.prompt | contains("dashboard-url"))] | length >= 1' "$EVALS"
  [ "$status" -eq 0 ]
}

@test "tooling-checkup times the skip-when-unchanged apply and reports drift" {
  grep -q 'dotfiles apply --if-changed' "$SKILL"
  grep -q 'dotfiles_apply_secs=<n>' "$SKILL"
  grep -q 'each drift line named' "$SKILL"
  run jq -e '[.evals[] | select(.prompt | contains("dotfiles_apply_secs"))] | length >= 1' "$EVALS"
  [ "$status" -eq 0 ]
}

@test "inventory labels a squash-merged branch clean-up: its patch is already in the base (git cherry)" {
  make_tooling_root
  local repo="$TOOLING/alpha"
  git_q -C "$repo" switch -c feat/squashed
  echo one > "$repo/a.txt"; git_q -C "$repo" add a.txt; git_q -C "$repo" commit -m "feat: a"
  git_q -C "$repo" push -u origin feat/squashed
  git_q -C "$repo" switch main
  # The same change lands on main as a new commit (a squash merge).
  echo one > "$repo/a.txt"; git_q -C "$repo" add a.txt; git_q -C "$repo" commit -m "feat: a (#1)"
  git_q -C "$repo" push origin main
  git_q -C "$repo" switch -c feat/real
  echo two > "$repo/b.txt"; git_q -C "$repo" add b.txt; git_q -C "$repo" commit -m "feat: b"
  git_q -C "$repo" switch main

  run env TOOLING_ROOT="$TOOLING" TOOLING_CHECKUP_NO_GH=1 TOOLING_CHECKUP_NO_FETCH=1 bash "$SCRIPTS/inventory.sh"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean-up  branch feat/squashed is already in main (same patch)"* ]]
  [[ "$output" != *"ship      branch feat/squashed"* ]]
  [[ "$output" == *"ship      branch feat/real has 1 commit(s) not in main"* ]]
}

@test "inventory labels a branch clean-up when a merged PR has its tip, with one gh call per repo" {
  make_tooling_root
  local repo="$TOOLING/alpha"
  git_q -C "$repo" remote set-url origin https://github.com/acme/alpha.git
  git_q -C "$repo" remote add store "$TEST_DIR/origin.git"
  for b in feat/merged-a feat/merged-b feat/reused feat/stacked; do
    git_q -C "$repo" switch -c "$b" main
    echo "$b" > "$repo/${b#feat/}.txt"; git_q -C "$repo" add .; git_q -C "$repo" commit -m "feat: $b"
  done
  git_q -C "$repo" switch main
  local a b r
  a="$(git -C "$repo" rev-parse feat/merged-a)"; b="$(git -C "$repo" rev-parse feat/merged-b)"
  r="$(git -C "$repo" rev-parse feat/reused)"
  local s; s="$(git -C "$repo" rev-parse feat/stacked)"
  # feat/merged-b exists only as a remote branch.
  git -C "$repo" update-ref refs/remotes/origin/feat/merged-b "$b"
  git_q -C "$repo" branch -D feat/merged-b
  # feat/reused got a new commit after its PR merged: still work to ship.
  git_q -C "$repo" switch feat/reused
  echo more >> "$repo/reused.txt"; git_q -C "$repo" commit -am "feat: more"
  git_q -C "$repo" switch main
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/gh" <<EOF2
#!/bin/sh
echo "\$*" >> "$TEST_DIR/gh.log"
case "\$*" in
  *"--state merged"*) printf 'feat/merged-a\t$a\tmain\nfeat/merged-b\t$b\tmain\nfeat/reused\t$r\tmain\nfeat/stacked\t$s\tfeat/merged-a\n' ;;
  "pr list"*) ;;
  "api"*" user "*) echo fyodor ;;
  *) exit 1 ;;
esac
EOF2
  chmod +x "$TEST_DIR/bin/gh"

  run env -u BASH_ENV -u ENV PATH="$TEST_DIR/bin:$PATH" TOOLING_ROOT="$TOOLING" TOOLING_CHECKUP_NO_FETCH=1 \
    bash "$SCRIPTS/inventory.sh"
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean-up  branch feat/merged-a was merged in a pull request"* ]]
  [[ "$output" == *"clean-up  remote branch feat/merged-b was merged in a pull request"* ]]
  [[ "$output" == *"ship      branch feat/reused has 2 commit(s) not in main"* ]]
  # Merged into another feature branch, not into main: still work to ship.
  [[ "$output" == *"ship      branch feat/stacked has 1 commit(s) not in main"* ]]
  [ "$(grep -c -- '--state merged' "$TEST_DIR/gh.log")" -eq 1 ]
}

@test "background audit prints the whole path of a process with a space in it (#308)" {
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/ps" <<'EOF'
#!/bin/bash
printf '  501   43.8   204800   01:02 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome\n'
EOF
  chmod +x "$TEST_DIR/bin/ps"
  run env PATH="$TEST_DIR/bin:$PATH" BACKGROUND_AUDIT_DIRS="$TEST_DIR/none" BACKGROUND_AUDIT_LAUNCHCTL="$TEST_DIR/none.txt" \
    BACKGROUND_AUDIT_TOP=1 DOTFILES_SOURCE="$TEST_DIR/none" bash "$SCRIPTS/background_audit.sh"
  echo "$output"
  [[ "$output" == *"pid=501 cpu=43.8% rss_mb=200 up=01:02 /Applications/Google Chrome.app/Contents/MacOS/Google Chrome"* ]]
}

@test "machine metrics match an explained app whose name has a space (#308)" {
  local now=1792153670 samples="$TEST_DIR/load.tsv" ps_file="$TEST_DIR/ps.txt"
  : > "$samples"
  for i in 0 1; do
    printf '%s\t2026-10-16T08:%02d:00\t35.0\t30.0\t20.0\t10\t40\t1200\t800\tGoogle_Chrome:90.1 mds:10.0\t90\n' \
      "$((now - 3600 + i * 30))" "$i" >> "$samples"
  done
  printf '  PID PRI TTY      COMM\n' > "$ps_file"
  printf 'Google Chrome\n' > "$TEST_DIR/explained.txt"
  run env DOTFILES_EXPLAINED_LOAD= python3 "$SCRIPTS/machine_metrics.py" --now "$now" --samples "$samples" --ps-file "$ps_file" \
    --state "$TEST_DIR/none.json" --claude-json "$TEST_DIR/none.json" --upgrade-log "$TEST_DIR/none.log" --explained-file "$TEST_DIR/explained.txt"
  echo "$output"
  [[ "$output" == *"load_overload_rows_explained"*" 2 "* ]]
}

# The skills audit follows the Agent Skills spec (agentskills.io/specification, #315).
@test "audit checks every Agent Skills spec requirement" {
  mk() { mkdir -p "$TEST_DIR/skills/$1"; printf -- '---\n%s\n---\nBody.\n' "$2" > "$TEST_DIR/skills/$1/SKILL.md"; }
  mk -lead $'name: -lead\ndescription: Formats notes. Use when asked for notes.'
  mk a--b $'name: a--b\ndescription: Formats notes. Use when asked for notes.'
  mk other-dir $'name: not-the-dir\ndescription: Formats notes. Use when asked for notes.'
  mk compat "name: compat
description: Formats notes. Use when asked for notes.
compatibility: $(printf 'x%.0s' $(seq 501))"
  mk meta $'name: meta\ndescription: Formats notes. Use when asked for notes.\nmetadata:\n  author: me\n  nested:\n    deep: no'
  mk tools $'name: tools\ndescription: Formats notes. Use when asked for notes.\nallowed-tools:\n  - Read'
  mk big $'name: big\ndescription: Formats notes. Use when asked for notes.'
  awk 'BEGIN { for (i = 0; i < 400; i++) print "word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word word" }' >> "$TEST_DIR/skills/big/SKILL.md"
  mk fine $'name: fine\ndescription: Formats notes. Use when asked for notes.\nlicense: MIT\ncompatibility: Requires git\nmetadata:\n  author: me\n  version: "1.0"\nallowed-tools: Bash(git:*) Read'
  mk flow $'name: flow\ndescription: Formats notes. Use when asked for notes.\nmetadata: {author: jo}'
  mk commented $'name: commented\ndescription: Formats notes. Use when asked for notes.\nmetadata:\n  # who wrote it\n  author: jo'
  mk listval $'name: listval\ndescription: Formats notes. Use when asked for notes.\nmetadata:\n  tags: [a, b]'

  run python3 "$SCRIPTS/audit_agent_config.py" --skills "$TEST_DIR/skills"
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR S017 "*"-lead/SKILL.md"* ]]
  [[ "$output" == *"ERROR S018 "*"a--b/SKILL.md"* ]]
  [[ "$output" == *"ERROR S005 "*"other-dir/SKILL.md"*"[spec: name]"* ]]
  [[ "$output" == *"ERROR S019 "*"compat/SKILL.md"* ]]
  [[ "$output" == *"ERROR S020 "*"meta/SKILL.md"* ]]
  [[ "$output" == *"WARN S021 "*"tools/SKILL.md"* ]]
  [[ "$output" == *"WARN S022 "*"big/SKILL.md"* ]]
  [[ "$output" != *"fine/SKILL.md"* ]]
  [[ "$output" != *"flow/SKILL.md"* ]]
  [[ "$output" != *"commented/SKILL.md"* ]]
  [[ "$output" == *"ERROR S020 "*"listval/SKILL.md"* ]]
}

@test "audit --spec-coverage: every spec requirement has a check, and each rule names its spec section or says it is ours" {
  run python3 "$SCRIPTS/audit_agent_config.py" --spec-coverage
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"spec requirements without a check: 0"* ]]
  [[ "$output" == *"S003"*"spec: name"* ]]
  [[ "$output" == *"S010"*"ours"* ]]
  grep -q 'agentskills.io/specification' "$SKILL_DIR/reference/config-audit.md"
}

@test "state record appends history and backfills the run recorded before it" {
  local bin="$TEST_DIR/bin"
  mkdir -p "$bin" "$TEST_DIR/state"
  printf '#!/bin/sh\necho "1.0.0 (Claude Code)"\n' > "$bin/claude"
  chmod +x "$bin/claude"
  make_tooling_root
  export TOOLING_ROOT="$TOOLING" TOOLING_CHECKUP_STATE_DIR="$TEST_DIR/state"
  printf '{"time":"2026-01-01T00:00:00+00:00","verdict":"healthy","metrics":{"a":"1"}}\n' > "$TEST_DIR/state/last-run.json"

  run env PATH="$bin:/usr/bin:/bin" python3 "$SCRIPTS/checkup_state.py" record --verdict "broken: x" --metric a=2
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$TEST_DIR/state/history.jsonl")" -eq 2 ]
  run jq -r '.verdict' "$TEST_DIR/state/history.jsonl"
  [ "$output" = $'healthy\nbroken: x' ]

  run env PATH="$bin:/usr/bin:/bin" python3 "$SCRIPTS/checkup_state.py" record --verdict "healthy"
  [ "$(wc -l < "$TEST_DIR/state/history.jsonl")" -eq 3 ]
}

# Fixture state for the dashboard exporter: two runs, gate timings, doctor stats.
make_dashboard_fixtures() {
  local s="$TEST_DIR/state"
  mkdir -p "$s"
  cat > "$s/history.jsonl" <<'JSON'
{"time":"2026-10-01T10:00:00+00:00","verdict":"healthy","metrics":{"machine_overload_rows_24h":"5","agent_tool_hours_7d":"10.5"}}
{"time":"2026-10-04T10:00:00+00:00","verdict":"healthy with gaps: token ghp_abcdefghijklmnopqrstuvwxyz0123 in /HOMEPATH/x","metrics":{"machine_overload_rows_24h":"197","odd key!":"3","note":"text"}}
JSON
  sd -s '/HOMEPATH' "$HOME" "$s/history.jsonl" 2>/dev/null || sed -i.bak "s#/HOMEPATH#$HOME#" "$s/history.jsonl"
  cat > "$TEST_DIR/gate.jsonl" <<'JSON'
{"ts":"2026-10-01T09:00:00Z","step":"lint","seconds":12,"status":0}
{"ts":"2026-10-01T09:00:10Z","step":"total","seconds":100,"status":0}
{"ts":"2026-10-01T11:00:10Z","step":"total","seconds":300,"status":2}
{"ts":"2026-10-01T12:00:10Z","step":"total","seconds":200,"status":0}
{"ts":"2026-10-02T12:00:10Z","step":"total","seconds":50,"status":0}
not json
JSON
  cat > "$TEST_DIR/stats.jsonl" <<'JSON'
{"task":"doctor","timestamp":"2026-10-01T08:00:00Z","pass":70,"fail":3,"warn":0,"skip":4}
{"task":"doctor","timestamp":"2026-10-01T20:00:00Z","pass":72,"fail":1,"warn":1,"skip":4}
{"task":"apply","timestamp":"2026-10-01T21:00:00Z"}
JSON
  printf "OSS_READINESS_INTERNAL_PATTERN='secretcorp|hiddenteam'\n" > "$TEST_DIR/pattern.env"
}

run_dashboard_export() {
  python3 "$SCRIPTS/dashboard_export.py" --state-dir "$TEST_DIR/state" --out "$TEST_DIR/out" \
    --gate-timings "$TEST_DIR/gate.jsonl" --doctor-stats "$TEST_DIR/stats.jsonl" \
    --load-samples "$TEST_DIR/none" --perf-dir "$TEST_DIR/none" --pattern-env "$TEST_DIR/pattern.env" "$@"
}

@test "dashboard export writes runs, latest, gate and doctor with a manifest" {
  make_dashboard_fixtures
  run run_dashboard_export
  [ "$status" -eq 0 ]
  run jq -r '[.[] | .id + ":" + (.staleAfterHours // 0 | tostring)] | join(",")' "$TEST_DIR/out/manifest.json"
  [ "$output" = "runs:72,latest:72,gate:0,doctor:0,load:24,agent_time:48" ]
  run jq -r '[.[] | .status + "=" + (.machine_overload_rows_24h | tostring)] | join(",")' "$TEST_DIR/out/runs.json"
  [ "$output" = "healthy=5,gaps=197" ]
  run jq -r '.[0] | [.machine_overload_rows_24h, has("odd key!"), has("note")] | map(tostring) | join(",")' "$TEST_DIR/out/latest.json"
  [ "$output" = "197,false,false" ]
  run jq -c '.' "$TEST_DIR/out/gate.json"
  [ "$output" = '[{"day":"2026-10-01","failed_runs":1,"median_total_s":200,"runs":3},{"day":"2026-10-02","failed_runs":0,"median_total_s":50,"runs":1}]' ]
  run jq -c '.' "$TEST_DIR/out/doctor.json"
  [ "$output" = '[{"day":"2026-10-01","fail":1,"pass":72,"skip":4,"warn":1}]' ]
}

@test "dashboard export falls back to last-run.json before history exists" {
  mkdir -p "$TEST_DIR/state"
  printf '{"time":"2026-10-25T19:10:35+00:00","verdict":"healthy","metrics":{"upgrade_secs":"216"}}\n' > "$TEST_DIR/state/last-run.json"
  printf 'OSS_READINESS_INTERNAL_PATTERN=secretcorp\n' > "$TEST_DIR/pattern.env"
  run python3 "$SCRIPTS/dashboard_export.py" --state-dir "$TEST_DIR/state" --out "$TEST_DIR/out" \
    --gate-timings "$TEST_DIR/none" --doctor-stats "$TEST_DIR/none" --pattern-env "$TEST_DIR/pattern.env"
  [ "$status" -eq 0 ]
  run jq -r '.[0].upgrade_secs' "$TEST_DIR/out/latest.json"
  [ "$output" = "216" ]
  run jq -r 'length' "$TEST_DIR/out/gate.json"
  [ "$output" = "0" ]
}

@test "dashboard export rows hold no token, home path or private-pattern match" {
  make_dashboard_fixtures
  printf '{"time":"2026-10-05T10:00:00+00:00","verdict":"broken: SecretCorp proxy down","metrics":{}}\n' >> "$TEST_DIR/state/history.jsonl"
  run run_dashboard_export
  [ "$status" -eq 0 ]
  ! grep -qiE 'secretcorp|hiddenteam' "$TEST_DIR"/out/*.json
  ! grep -qE 'gh[pousr]_[A-Za-z0-9]{20,}|github_pat_|sk-[A-Za-z0-9_-]{20,}|xox[abprs]-|AKIA[0-9A-Z]{16}' "$TEST_DIR"/out/*.json
  ! grep -qF "$HOME" "$TEST_DIR"/out/*.json
  grep -qF '[redacted]' "$TEST_DIR/out/runs.json"
  # The real private-pattern file, when this machine has one.
  local real_home env_file
  real_home="$(eval echo "~$(id -un)")"
  env_file="$real_home/.config/oss-readiness/oss-readiness.env"
  if [ -f "$env_file" ]; then
    local pattern
    pattern="$(bash -c 'source "$1" >/dev/null 2>&1; printf %s "${OSS_READINESS_INTERNAL_PATTERN:-}"' _ "$env_file")"
    [ -z "$pattern" ] || ! grep -qicE -- "$pattern" "$TEST_DIR"/out/*.json
  fi
}

@test "dashboard export fails closed without the private-pattern file or pattern" {
  make_dashboard_fixtures
  run python3 "$SCRIPTS/dashboard_export.py" --state-dir "$TEST_DIR/state" --out "$TEST_DIR/out" \
    --gate-timings "$TEST_DIR/gate.jsonl" --doctor-stats "$TEST_DIR/stats.jsonl" --pattern-env "$TEST_DIR/none"
  [ "$status" -eq 2 ]
  [[ "$output" == *"nothing written"* ]]
  [ ! -e "$TEST_DIR/out" ]
  printf '# no pattern here\n' > "$TEST_DIR/pattern.env"
  run run_dashboard_export
  [ "$status" -eq 2 ]
  [ ! -e "$TEST_DIR/out" ]
}

@test "dashboard export applies the pattern as POSIX ERE, like the leak gates" {
  make_dashboard_fixtures
  printf "OSS_READINESS_INTERNAL_PATTERN='secret[[:space:]]corp'\n" > "$TEST_DIR/pattern.env"
  printf '{"time":"2026-10-05T10:00:00+00:00","verdict":"broken: Secret Corp proxy down, mail a@b.example","metrics":{}}\n' >> "$TEST_DIR/state/history.jsonl"
  run run_dashboard_export
  [ "$status" -eq 0 ]
  ! grep -qiE 'secret[[:space:]]corp' "$TEST_DIR"/out/*.json
  grep -qF '[private]' "$TEST_DIR/out/latest.json"
  grep -qF '[email]' "$TEST_DIR/out/latest.json"
}

@test "dashboard export adds hourly load and per-project agent time, grouping private projects" {
  make_dashboard_fixtures
  local now=1792975050
  printf '%s\t2026-10-25T20:00:00\t30\t1\t1\t10\t80\t5\t800\tx:1\t50\n' "$((now - 60))" > "$TEST_DIR/load.tsv"
  printf '%s\t2026-10-25T20:30:00\t10\t1\t1\t10\t70\t9\t800\tx:1\t50\n' "$((now - 30))" >> "$TEST_DIR/load.tsv"
  printf '%s\t2026-10-10T20:30:00\t99\t1\t1\t10\t70\t9\t800\tx:1\t50\n' "$((now - 15 * 86400))" >> "$TEST_DIR/load.tsv"
  mkdir -p "$TEST_DIR/perf"
  cat > "$TEST_DIR/perf/2026-10.jsonl" <<'JSON'
{"project":"dotfiles","ts":"2026-10-25T10:00:00Z","tool":"Bash","ms":3600000,"ok":true}
{"project":"dotfiles","ts":"2026-10-25T11:00:00Z","tool":"Bash","ms":1800000,"ok":false}
{"project":"secretcorp-app","ts":"2026-10-25T11:00:00Z","tool":"Read","ms":360000,"ok":true}
{"project":"dotfiles","ts":"2026-10-25T11:00:00Z","ev":"attempt","tool":"Bash"}
{"project":"dotfiles","ts":"2026-09-01T11:00:00Z","tool":"Bash","ms":99,"ok":true}
JSON
  run run_dashboard_export --load-samples "$TEST_DIR/load.tsv" --perf-dir "$TEST_DIR/perf" --now "$now"
  [ "$status" -eq 0 ]
  run jq -c '.' "$TEST_DIR/out/load.json"
  [ "$output" = '[{"hour":"2026-10-25T20:00","max_swap_mb":9,"mean_load1":20,"min_free_mem_pct":70,"overload_samples":1,"peak_load1":30,"samples":2}]' ]
  run jq -c '.' "$TEST_DIR/out/agent_time.json"
  [ "$output" = '[{"calls":2,"day":"2026-10-25","failed_calls":1,"project":"dotfiles","tool_hours":1.5},{"calls":1,"day":"2026-10-25","failed_calls":0,"project":"other","tool_hours":0.1}]' ]
  ! grep -qi secretcorp "$TEST_DIR"/out/*.json
  run jq -r '[.[].id] | join(",")' "$TEST_DIR/out/manifest.json"
  [ "$output" = "runs,latest,gate,doctor,load,agent_time" ]
  grep -q 'data-source="load"' "$SKILL_DIR/dashboard/index.html"
  grep -q 'data-source="agent_time"' "$SKILL_DIR/dashboard/index.html"
}

@test "config hygiene asks before deleting memory, rules, skills, or backups" {
  local ref="$SKILL_DIR/reference/config-hygiene.md"
  grep -F -q "Never delete memory, rule, or skill files without the owner's yes." "$ref"
  grep -F -q '~/.local/state/tooling-checkup/backups/checkup-YYYY-MM-DD/' "$ref"
  grep -F -q 'list the older ones in the Phase 11 questionnaire' "$ref"
  grep -F -q 'one batch, with the backup path' "$ref"
  run grep -F -q 'ls -lt ~/.claude/skills' "$ref"
  [ "$status" -ne 0 ]
  run grep -F -q '~/.claude/backups' "$ref"
  [ "$status" -ne 0 ]
  run grep -F -q 'old checkup backups to prune' "$SKILL"
  [ "$status" -eq 0 ]
  run jq -e '.evals[] | select(.id == 21) | .expectations | any(test("deletes no memory file"; "i"))' "$EVALS"
  [ "$status" -eq 0 ]
}

# Stock-git Mac with a flat ~/apps layout (checkup-scripts-stock-mac-gaps).
make_flat_home() {
  FLAT_HOME="$TEST_DIR/home"
  mkdir -p "$FLAT_HOME/apps"
  git_q init --bare "$TEST_DIR/flat-origin.git"
  for name in agentbrew dotfiles; do
    git_q clone "$TEST_DIR/flat-origin.git" "$FLAT_HOME/apps/$name"
    git_q -C "$FLAT_HOME/apps/$name" commit --allow-empty -m "chore: init"
    git_q -C "$FLAT_HOME/apps/$name" push origin HEAD:main
    git_q -C "$FLAT_HOME/apps/$name" remote set-head origin main
  done
  git_q init "$FLAT_HOME/apps/unrelated"
}

@test "inventory finds agentbrew and dotfiles in a flat ~/apps layout, and only them" {
  make_flat_home
  run env -u TOOLING_ROOT HOME="$FLAT_HOME" TOOLING_CHECKUP_NO_GH=1 TOOLING_CHECKUP_NO_FETCH=1 bash "$SCRIPTS/inventory.sh"
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  [[ "$output" == *"== agentbrew"* && "$output" == *"== dotfiles"* ]]
  [[ "$output" != *"== unrelated"* ]]
}

@test "inventory counts ahead/behind on git older than 2.41 with no fatal line" {
  make_tooling_root
  git_q -C "$TOOLING/alpha" switch -c feat/old-git
  git_q -C "$TOOLING/alpha" commit --allow-empty -m "feat: one"
  git_q -C "$TOOLING/alpha" switch main
  local shim="$TEST_DIR/oldgit"; mkdir -p "$shim"
  local real_git; real_git="$(command -v git)"
  printf '#!/bin/bash\nfor a in "$@"; do case "$a" in *ahead-behind*) echo "fatal: unknown field name: ahead-behind:origin/main" >&2; exit 128 ;; esac; done\nexec %s "$@"\n' "$real_git" > "$shim/git"
  chmod +x "$shim/git"
  run env PATH="$shim:$PATH" TOOLING_ROOT="$TOOLING" TOOLING_CHECKUP_NO_GH=1 bash "$SCRIPTS/inventory.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"fatal:"* ]] || { echo "$output"; return 1; }
  [[ "$output" == *"branch feat/old-git has 1 commit(s) not in main"* ]] || { echo "$output"; return 1; }
}

@test "background audit never uses plutil error text as a job's program" {
  local agents="$TEST_DIR/LaunchAgents" shim="$TEST_DIR/plutil-shim"
  mkdir -p "$agents" "$shim"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict>\n<key>Label</key><string>com.owner.daily</string>\n<key>ProgramArguments</key><array><string>/bin/sh</string><string>daily</string></array>\n</dict></plist>\n' > "$agents/com.owner.daily.plist"
  # Some macOS versions print the plutil error on stdout.
  printf '#!/bin/bash\nfor a in "$@"; do [ "$a" = Program ] && { echo "Could not extract value, error: No value at that key path"; exit 1; }; done\nexec /usr/bin/plutil "$@"\n' > "$shim/plutil"
  chmod +x "$shim/plutil"
  printf 'PID\tStatus\tLabel\n-\t0\tcom.owner.daily\n' > "$TEST_DIR/launchctl.txt"
  run env PATH="$shim:$PATH" BACKGROUND_AUDIT_DIRS="$agents" BACKGROUND_AUDIT_LAUNCHCTL="$TEST_DIR/launchctl.txt" \
    BACKGROUND_AUDIT_TOP=0 DOTFILES_SOURCE="$TEST_DIR/none" XDG_STATE_HOME="$TEST_DIR/state" bash "$SCRIPTS/background_audit.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Could not extract"* ]] || { echo "$output"; return 1; }
  [[ "$output" != *"remove"*"com.owner.daily"* ]] || { echo "$output"; return 1; }
}

@test "config audit counts installed skills when no tooling checkout has skills" {
  local home="$TEST_DIR/skillhome" src="$TEST_DIR/skill-src"
  mkdir -p "$home/.claude/skills" "$src/one" "$src/two"
  for s in one two; do
    printf -- '---\nname: %s\ndescription: Does %s things. Use when the user asks for %s.\n---\nBody.\n' "$s" "$s" "$s" > "$src/$s/SKILL.md"
    ln -s "$src/$s" "$home/.claude/skills/$s"
  done
  run env -u TOOLING_ROOT HOME="$home" python3 "$SCRIPTS/audit_agent_config.py"
  [[ "$output" == *"audit: 2 skill(s)"* ]] || { echo "$output"; return 1; }
}

@test "Phase 7 also looks for new-project in a flat ~/apps/agentbrew checkout" {
  grep -qF 'apps/{tooling/,}agentbrew -E' "$SKILL"
}
