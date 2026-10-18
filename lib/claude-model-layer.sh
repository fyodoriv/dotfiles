#!/bin/bash
# This Mac's Claude model/effort override as an Agentfile layer (defaultModel,
# defaultEffort). run_after_claude-settings-model.sh --print-override resolves
# it from claude_model / claude_effort chezmoi data or DOTFILES_CLAUDE_*.
# run_after_agentbrew-sync.sh merges it last so agentbrew's model sync writes
# the same pair as the dotfiles pin; the agentbrew doctor module rebuilds the
# same merge to check the global Agentfile. Only overridden keys are written,
# so an overlay Agentfile's defaultModel/defaultEffort still apply otherwise.

# claude_model_layer_write OUT — returns 1 when this Mac overrides nothing.
claude_model_layer_write() {
  local out="$1" pin="$DOTFILES_DIR/.chezmoiscripts/run_after_claude-settings-model.sh" model effort
  [ -f "$pin" ] || return 1
  IFS='|' read -r model effort < <(bash "$pin" --print-override 2>/dev/null) || return 1
  [ -n "$model" ] || [ -n "$effort" ] || return 1
  : > "$out"
  [ -z "$model" ] || printf 'defaultModel: %s\n' "$model" >> "$out"
  [ -z "$effort" ] || printf 'defaultEffort: %s\n' "$effort" >> "$out"
}
