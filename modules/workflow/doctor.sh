#!/bin/bash
# Doctor checks for workflow module

# ── One LaunchAgent per job ───────────────────────────────────────────
# A legacy or hand-installed copy of a managed agent runs the job twice.
# `dotfiles apply` removes the copies that lib/launchagent-duplicates.sh
# proves are duplicates; the same-name twins below need a human look.
if [ -f "$DOTFILES_DIR/lib/launchagent-duplicates.sh" ]; then
  # shellcheck source=../../lib/launchagent-duplicates.sh
  source "$DOTFILES_DIR/lib/launchagent-duplicates.sh"
  check "launchagents.no_duplicate_jobs" "no LaunchAgent duplicates a managed dotfiles job" \
    "[ -z \"\$(launchagent_duplicates \"\$HOME/Library/LaunchAgents\" \"$DOTFILES_DIR\")\" ]" \
    "launchagent_remove_duplicates \"\$HOME/Library/LaunchAgents\" \"$DOTFILES_DIR\""
  check_advisory "launchagents.no_same_name_twins" "no other LaunchAgent shares a managed agent's name" \
    "[ -z \"\$(launchagent_suffix_twins \"\$HOME/Library/LaunchAgents\")\" ]" \
    ""
fi

# LaunchAgents — check all deployed com.dotfiles.* agents
for plist in "$HOME"/Library/LaunchAgents/com.dotfiles.*.plist; do
  [ ! -f "$plist" ] && continue
  name="$(basename "$plist" .plist)"
  short="${name#com.dotfiles.}"
  agent_id="agent.$short"
  agent_desc="$short agent active"
  agent_test="launchctl list 2>/dev/null | grep -q '$name'"
  agent_fix="launchctl load \"\$HOME/Library/LaunchAgents/$name.plist\" 2>/dev/null"

  # Endpoint policy intentionally unloads this Node-backed job while the
  # Node.js Foundation publisher remains blocked. Report that safe mode as a
  # skip instead of treating the expected unloaded state as drift.
  if [ "$short" = "dotfiles-upgrade" ] \
    && [ "${DOTFILES_ALLOW_BLOCKED_NODE_PUBLISHER:-0}" != "1" ] \
    && [ -f "$HOME/.local/state/dotfiles/endpoint-node-publisher-blocked" ]; then
    if [ -n "${_known_ids+x}" ]; then
      check "$agent_id" "$agent_desc" "$agent_test" "$agent_fix"
    elif $LIST_MODE; then
      printf "  %-45s %s\n" "$agent_id" "dotfiles-upgrade agent disabled while Node.js publisher is blocked"
    else
      skipped "dotfiles-upgrade agent disabled while Node.js publisher is blocked"
    fi
    continue
  fi

  check "$agent_id" "$agent_desc" "$agent_test" "$agent_fix"
done

# Spotlight exclusions
for dir in "${DOTFILES_REPOS_DIR:-$HOME/apps}" "$HOME/.nvm" "$HOME/.gradle" "$HOME/.cache" "$HOME/.npm" "$HOME/.yarn" "$HOME/.docker" "$HOME/.pyenv" "$HOME/.local" "$HOME/.config" "$HOME/Library/Caches"; do
  [ ! -d "$dir" ] && continue
  local_name="$(basename "$dir")"
  check "spotlight.$local_name" "$dir excluded from Spotlight" \
    "[ -f '$dir/.metadata_never_index' ]" \
    "touch '$dir/.metadata_never_index' 2>/dev/null"
done

# Secrets-in-zshrc check removed — covered by security module (dotfiles audit)

# PATH check moved to shell/doctor.sh (shell.dotfiles_on_path)
