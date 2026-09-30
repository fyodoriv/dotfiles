#!/usr/bin/env bats
# Drift detector for the three layers that must agree on Devin's pinned model.
#
# Per AGENTS.md § Model Configuration, three layers carry the literal
# `gpt-5-5-xhigh-priority` and must stay in lockstep — any single edit that
# bumps one without the others creates a confusing partial state where
# Devin reports one model in fresh shells and another from non-interactive
# sessions (or vice versa).
#
# Layer 1: $DEVIN_MODEL env var in home/zshrc.ai-tools (deployed by chezmoi)
# Layer 2: agent.model fix payload in modules/devin/doctor.sh (the literal
#          the fix-mode writes when ~/.config/devin/config.json drifts)
# Layer 3: minsky's per-persona ANTHROPIC_MODEL override (only when the
#          minsky repo is checked out alongside dotfiles; skipped cleanly
#          if it isn't)
#
# The doctor's `devin.model_default` check already validates layer 2 at
# runtime; this bats test pins all three at the source level so a stale
# edit in any one of them gets caught by `make check` before it ships.

load test_helper

# The literal every layer must agree on. Update here ONLY when bumping the
# cross-agent default-model policy (see dotfiles AGENTS.md § Model
# Configuration). The agentbrew templates/AGENTS.md broadcast also references
# this value — bump both.
EXPECTED_MODEL="gpt-5-5-xhigh-priority"

@test "devin model: home/zshrc.ai-tools exports DEVIN_MODEL=$EXPECTED_MODEL" {
  local zshrc="$BATS_TEST_DIRNAME/../home/zshrc.ai-tools"
  [ -f "$zshrc" ]
  # Match `export DEVIN_MODEL="gpt-5-5-xhigh-priority"` allowing either quote.
  grep -qE '^[[:space:]]*export DEVIN_MODEL=("|'"'"')'"$EXPECTED_MODEL"'\1' "$zshrc"
}

@test "devin model: modules/devin/doctor.sh fix payload writes $EXPECTED_MODEL" {
  local doctor="$BATS_TEST_DIRNAME/../modules/devin/doctor.sh"
  [ -f "$doctor" ]
  # The Python heredoc inside _devin_set_default_model carries the literal
  # twice — once in the assignment line and once in the regex check above
  # it. Both must match.
  grep -qF '"agent", {})["model"] = "'"$EXPECTED_MODEL"'"' "$doctor"
  grep -qF '"'"$EXPECTED_MODEL"'"' "$doctor"
}

@test "devin model: modules/devin/doctor.sh model-check regex pins $EXPECTED_MODEL" {
  local doctor="$BATS_TEST_DIRNAME/../modules/devin/doctor.sh"
  # _devin_model_is_default greps ~/.config/devin/config.json for the
  # literal. The same literal must appear in that grep pattern.
  grep -qE '"model"\[\[:space:\]\]\*:\[\[:space:\]\]\*"'"$EXPECTED_MODEL"'"' "$doctor"
}

@test "devin model: README's use_ai_tools row references $EXPECTED_MODEL" {
  local readme="$BATS_TEST_DIRNAME/../README.md"
  [ -f "$readme" ]
  # Pin the configuration table row so a partial bump (e.g. doctor.sh got
  # updated but the row didn't) is caught by this single consistency test.
  grep -qE '^\| AI tooling \|.*'"$EXPECTED_MODEL" "$readme"
}

@test "devin model: AGENTS.md § Model Configuration table pins $EXPECTED_MODEL for Devin" {
  local agents="$BATS_TEST_DIRNAME/../AGENTS.md"
  [ -f "$agents" ]
  # The Devin row in the per-agent table carries the literal.
  grep -qE '^\| \*\*Devin\*\*.*'"$EXPECTED_MODEL" "$agents"
}

@test "devin model: minsky personaRunner agrees (when minsky repo is present)" {
  # Three valid layouts for the minsky checkout:
  local candidates=(
    "$HOME/apps/minsky"
    "$HOME/apps/tooling/minsky"
    "$BATS_TEST_DIRNAME/../../minsky"
  )
  local minsky_dir=""
  for d in "${candidates[@]}"; do
    if [ -d "$d" ]; then minsky_dir="$d"; break; fi
  done
  # Skip cleanly when minsky isn't checked out — this bats file ships in
  # dotfiles and must not require a minsky clone to pass.
  [ -n "$minsky_dir" ] || skip "minsky repo not checked out (probed: ${candidates[*]})"

  # The personaRunner is the canonical layer-3 host. Find it without hard-
  # coding a specific path so this test survives minsky reshuffles.
  local persona_runner
  persona_runner=$(find "$minsky_dir" -type f \
    \( -name "personaRunner.ts" -o -name "personaRunner.js" \) \
    2>/dev/null | head -1)
  [ -n "$persona_runner" ] || skip "personaRunner not found in $minsky_dir"

  # Two acceptable shapes:
  #   1. The runner pins to $EXPECTED_MODEL directly (e.g. via const)
  #   2. The runner reads $DEVIN_MODEL / process.env.ANTHROPIC_MODEL —
  #      which inherits layer 1's value at runtime
  # We pass on either.
  if grep -qF "$EXPECTED_MODEL" "$persona_runner"; then
    true  # explicit pin
  elif grep -qE "process\.env\.(DEVIN_MODEL|ANTHROPIC_MODEL)" "$persona_runner"; then
    true  # inherits layer 1
  else
    echo "personaRunner ($persona_runner) neither pins $EXPECTED_MODEL nor reads DEVIN_MODEL/ANTHROPIC_MODEL"
    return 1
  fi
}
