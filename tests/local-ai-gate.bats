#!/usr/bin/env bats
# local_ai_agents=false must keep the local-AI stack off: no LaunchAgents and no
# doctor fixes (which would curl | bash the opencode installer).
# local_ai_agents defaults to use_local_ai OR owner_machine: a new user's Mac
# with use_local_ai off gets none, and the owner's Macs keep opencode serve.

load test_helper

REPO_ROOT="$BATS_TEST_DIRNAME/.."
LA_TMPL="$REPO_ROOT/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"

_load_launchagent_gate() {
  PROFILE=core LOCAL_AI_AGENTS="$1"
  eval "$(sed -n '/^should_skip_agent() {/,/^}/p' "$LA_TMPL")"
}

# Render the template's LOCAL_AI_AGENTS line with the given chezmoi data.
_render_gate_value() {
  local line
  line="$(grep '^LOCAL_AI_AGENTS=' "$LA_TMPL")"
  printf 'data:\n%b' "$1" >"$TEST_DIR/cfg.yaml"
  printf '%s\n' "$line" | chezmoi execute-template --config "$TEST_DIR/cfg.yaml" \
    --source "$TEST_DIR"
}

_init_config() {
  mkdir -p "$TEST_DIR/src"
  cp "$REPO_ROOT/.chezmoi.yaml.tmpl" "$TEST_DIR/src/"
  HOME="$TEST_HOME" chezmoi init --source "$TEST_DIR/src" --config-path "$TEST_DIR/init.yaml" \
    --promptDefaults \
    --promptString "Git commit name for work/default identity=Alex Example" \
    --promptString "Git commit email for work/default identity=$1" >/dev/null 2>&1
}

@test "LaunchAgent gate: local_ai_agents=false skips ollama, opencode-serve and local-ai-warmup" {
  _load_launchagent_gate false
  should_skip_agent ollama
  should_skip_agent opencode-serve
  should_skip_agent local-ai-warmup
}

@test "LaunchAgent gate: local_ai_agents=true keeps the local-AI agents" {
  _load_launchagent_gate true
  ! should_skip_agent ollama
  ! should_skip_agent opencode-serve
  ! should_skip_agent local-ai-warmup
}

@test "LaunchAgent gate value: new user with use_local_ai=false gets false" {
  run _render_gate_value '  owner_machine: false\n  use_local_ai: false\n'
  [ "$status" -eq 0 ]
  [ "$output" = 'LOCAL_AI_AGENTS="false"' ]
}

@test "LaunchAgent gate value: owner with use_local_ai=false keeps the agents" {
  # The owner's saved config has no local_ai_agents key yet.
  run _render_gate_value '  owner_machine: true\n  use_local_ai: false\n'
  [ "$status" -eq 0 ]
  [ "$output" = 'LOCAL_AI_AGENTS="true"' ]
}

@test "LaunchAgent gate value: use_local_ai=true turns the agents on" {
  run _render_gate_value '  owner_machine: false\n  use_local_ai: true\n'
  [ "$output" = 'LOCAL_AI_AGENTS="true"' ]
}

@test "LaunchAgent gate value: local_ai_agents=false wins on the owner's Mac" {
  run _render_gate_value '  owner_machine: true\n  local_ai_agents: false\n'
  [ "$output" = 'LOCAL_AI_AGENTS="false"' ]
}

@test "config: new user's config writes local_ai_agents false" {
  _init_config alex@example.com
  grep -q '^  local_ai_agents: false' "$TEST_DIR/init.yaml"
}

@test "config: owner's config writes local_ai_agents true" {
  _init_config fyodor@sent.com
  grep -q '^  local_ai_agents: true' "$TEST_DIR/init.yaml"
}

@test "local-ai doctor module runs no checks when local_ai_agents=false" {
  calls=0
  check() { calls=$((calls + 1)); }
  check_advisory() { calls=$((calls + 1)); }
  LOCAL_AI_AGENTS=false
  source "$REPO_ROOT/modules/local-ai/doctor.sh"
  [ "$calls" -eq 0 ]
}

@test "local-ai doctor module runs its checks when local_ai_agents=true" {
  calls=0
  check() { calls=$((calls + 1)); }
  check_advisory() { calls=$((calls + 1)); }
  LOCAL_AI_AGENTS=true USE_LOCAL_AI=false
  source "$REPO_ROOT/modules/local-ai/doctor.sh"
  [ "$calls" -gt 0 ]
}

@test "dotfiles-doctor derives LOCAL_AI_AGENTS with the same default as the LaunchAgents" {
  grep -q "LOCAL_AI_AGENTS=.*dig \"local_ai_agents\" (or (dig \"use_local_ai\" false .) (dig \"owner_machine\" false .)) ." \
    "$REPO_ROOT/bin/dotfiles-doctor"
}
