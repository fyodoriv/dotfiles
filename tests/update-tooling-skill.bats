#!/usr/bin/env bats

load test_helper

ROOT="$BATS_TEST_DIRNAME/.."
SKILL="$ROOT/skills/update-tooling/SKILL.md"
EVALS="$ROOT/skills/update-tooling/evals/evals.json"
AGENTFILE="$ROOT/Agentfile.yaml"

@test "update-tooling skill is installed through the source Agentfile" {
  [ -f "$SKILL" ]
  grep -q '^name: update-tooling$' "$SKILL"
  awk '
    $0 == "skills:" { in_skills = 1; next }
    in_skills && /^[^[:space:]#][^:]*:/ { exit }
    in_skills && $0 ~ /^[[:space:]]*-[[:space:]]+update-tooling([[:space:]]|$)/ {
      found = 1
    }
    END { exit !found }
  ' "$AGENTFILE"
}

@test "update-tooling has behavior evals" {
  [ -f "$EVALS" ]
  run jq -e '
    .skill_name == "update-tooling"
    and (.evals | type == "array")
    and (.evals | length >= 5)
  ' "$EVALS"

  [ "$status" -eq 0 ]
}

@test "update-tooling keeps refreshes fast-forward-only and non-destructive" {
  grep -F -q 'git -C "$repo" merge --ff-only "$upstream"' "$SKILL"
  grep -F -q '`git pull --rebase`' "$SKILL"
  grep -F -q 'git reset' "$SKILL"
  grep -F -q 'git checkout .' "$SKILL"
  grep -F -q 'git clean' "$SKILL"
  grep -F -q 'dirty, has no upstream, is on a non-canonical branch, is' "$SKILL"
  grep -F -q 'PULL_REMOTE=origin' "$SKILL"
  grep -F -q '`upstream` equals `$PULL_REMOTE/$canonical_branch`' "$SKILL"
}

@test "update-tooling applies and verifies the right machine layers" {
  grep -F -q 'env -u DOTFILES_DIR "$DOTFILES_APPLIED/bin/dotfiles-sync"' "$SKILL"
  grep -F -q 'env -u DOTFILES_DIR "$APPLIED_AGENTBREW" sync --pull --no-recommended --agentfile "$HOME/.config/agentbrew/Agentfile.yaml"' "$SKILL"
  grep -F -q 'env -u DOTFILES_DIR "$APPLIED_AGENTBREW" mcp probe --deep' "$SKILL"
  grep -F -q 'env -u DOTFILES_DIR "$APPLIED_AGENTBREW" measure context' "$SKILL"
  grep -F -q 'env -u DOTFILES_DIR "$DOTFILES_APPLIED/bin/dotfiles-reload-launchagents"' "$SKILL"
  grep -F -q 'CDP9223=ok' "$SKILL"
  grep -F -q 'MINSKY_STATE_DIR:-$HOME/.minsky}/autostart-enabled' "$SKILL"
  grep -F -q 'agentbrew_updated=true' "$SKILL"
}

@test "update-tooling refreshes the detached applied AgentBrew build safely" {
  grep -F -q 'AGENTBREW_APPLIED="${AGENTBREW_APPLIED:-$TOOLING_ROOT/agentbrew}"' "$SKILL"
  grep -F -q 'git -C "$AGENTBREW_APPLIED" fetch origin main' "$SKILL"
  grep -F -q 'git -C "$AGENTBREW_APPLIED" merge --ff-only origin/main' "$SKILL"
  grep -F -q '(cd "$AGENTBREW_APPLIED" && npm run build)' "$SKILL"
  grep -F -q 'command -v agentbrew' "$SKILL"
  grep -F -q '[ ! -e "$AGENTBREW_APPLIED/.git" ]' "$SKILL"
  grep -F -q 'APPLIED_AGENTBREW="$AGENTBREW_APPLIED/dist/cli.js"' "$SKILL"
  grep -F -q 'global agentbrew differs from applied build' "$SKILL"
  grep -F -q 'preserved applied AgentBrew checkout: dirty' "$SKILL"
  grep -F -q 'preserved applied AgentBrew checkout: ahead or diverged' "$SKILL"
}

@test "update-tooling respects endpoint safe mode and unsets DOTFILES_DIR" {
  grep -F -q 'endpoint-node-publisher-blocked' "$SKILL"
  grep -F -q 'Do not invoke `agentbrew` to inspect the catalog in this mode.' "$SKILL"
  grep -F -q '"$AGENTBREW_APPLIED/src/catalog.yaml"' "$SKILL"
  grep -F -q 'yq -r' "$SKILL"
  grep -F -q 'env -u DOTFILES_DIR agentbrew sync --only skills --no-recommended --agentfile "$HOME/.config/agentbrew/Agentfile.yaml"' "$SKILL"
  grep -F -q 'missing from `skills:`' "$SKILL"
  grep -F -q 'skipped AgentBrew runtime checks' "$SKILL"
  ! grep -F -q 'export DOTFILES_DIR="$TOOLING_ROOT/dotfiles"' "$SKILL"
  run jq -e '
    .evals
    | map(select(.id == 6 or .id == 7))
    | length == 2
  ' "$EVALS"
  [ "$status" -eq 0 ]
}

@test "update-tooling keeps LaunchAgent mutations in the applied checkout" {
  grep -F -q 'Only `$DOTFILES_APPLIED` may mutate or reload Home LaunchAgents.' "$SKILL"
  grep -F -q 'never starts an' "$SKILL"
  grep -F -q 'unloaded job' "$SKILL"
  grep -F -q 'Node-backed jobs alone while endpoint safe mode is active' "$SKILL"
  grep -F -q 'declared release whitelist' "$SKILL"
}

@test "update-tooling keeps task selection dynamic and unowned work untouched" {
  grep -F -q 'Do not claim, edit, or complete a task' "$SKILL"
  grep -F -q 'Do not hard-code task IDs in this skill' "$SKILL"
  grep -F -q 'Do not use the legacy `bin/tooling-sync`' "$SKILL"
  grep -F -q 'does not commit, rebase, force-push' "$SKILL"
}

@test "update-tooling never runs a sync that installs the catalog recommended set" {
  # A bare `agentbrew sync` installs every catalog `recommended: true` skill,
  # even ones the Agentfile removed. Each runnable sync line must opt out.
  local bad
  bad="$(grep -iE '^ *(cd [^&]*&& )?(env -u DOTFILES_DIR )?"?[$a-z_]*agentbrew[a-z_]*"? sync( |$)' "$SKILL" | grep -v -- '--no-recommended' || true)"
  [ -z "$bad" ]
}
