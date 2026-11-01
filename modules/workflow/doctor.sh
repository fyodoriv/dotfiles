#!/bin/bash
# Doctor checks for workflow module

# ── One LaunchAgent per job ───────────────────────────────────────────
# A legacy or hand-installed copy of a managed agent runs the job twice.
# `dotfiles apply` removes the copies that lib/launchagent-duplicates.sh
# proves are duplicates; the same-name twins below need a human look.
if [ -f "$DOTFILES_DIR/lib/launchagent-duplicates.sh" ]; then
  # shellcheck source=../../lib/launchagent-duplicates.sh
  source "$DOTFILES_DIR/lib/launchagent-duplicates.sh"
  # dotfiles-doctor runs each fix in a new process (bash -c).
  export -f launchagent_argv launchagent_duplicates launchagent_remove_duplicates
  check "launchagents.no_duplicate_jobs" "no LaunchAgent duplicates a managed dotfiles job" \
    "[ -z \"\$(launchagent_duplicates \"\$HOME/Library/LaunchAgents\" \"$DOTFILES_DIR\")\" ]" \
    "launchagent_remove_duplicates \"\$HOME/Library/LaunchAgents\" \"$DOTFILES_DIR\""
  check_advisory "launchagents.no_same_name_twins" "no other LaunchAgent shares a managed agent's name" \
    "[ -z \"\$(launchagent_suffix_twins \"\$HOME/Library/LaunchAgents\")\" ]" \
    "launchctl bootout and delete the twin plist that launchagent_suffix_twins lists (keep the com.dotfiles one)"
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

  # Core option chrome.dock_guard false (with a headed purpose Chrome) turns
  # the Dock guard off on purpose; checking and reloading it would fight the
  # overlay that turned it off (#300).
  if [ "$short" = "chrome-dock-guard" ] && [ -f "$DOTFILES_DIR/lib/chrome-purpose-options.sh" ]; then
    # shellcheck source=../../lib/chrome-purpose-options.sh
    source "$DOTFILES_DIR/lib/chrome-purpose-options.sh"
    _wf_opt() { if declare -F plugin_option >/dev/null; then plugin_option "$1" 2>/dev/null || echo "$2"; else echo "$2"; fi; }
    if ! chrome_dock_guard_enabled "${DOTFILES_CHROME_DOCK_GUARD:-$(_wf_opt chrome.dock_guard true)}" \
      "${DOTFILES_CHROME_PURPOSE_HEADED:-$(_wf_opt chrome.purpose_headed false)}"; then
      $LIST_MODE || skipped "chrome-dock-guard agent off on purpose (core option chrome.dock_guard)"
      continue
    fi
  fi

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

# Spotlight exclusions. The marker alone proves nothing: some macOS versions
# index a marked dir anyway, so the check also probes the index
# (lib/spotlight-probe.sh). The fix writes the marker; when Spotlight still
# indexes the dir, the fix fails and the description names the manual step.
# shellcheck source=../../lib/spotlight-probe.sh
source "$DOTFILES_DIR/lib/spotlight-probe.sh"
for dir in "${DOTFILES_REPOS_DIR:-$HOME/apps}" "$HOME/.nvm" "$HOME/.gradle" "$HOME/.cache" "$HOME/.npm" "$HOME/.yarn" "$HOME/.docker" "$HOME/.pyenv" "$HOME/.local" "$HOME/.config" "$HOME/Library/Caches"; do
  [ ! -d "$dir" ] && continue
  local_name="$(basename "$dir")"
  check "spotlight.$local_name" "$dir out of the Spotlight index (if still indexed: System Settings → Spotlight → Search Privacy)" \
    "[ -f '$dir/.metadata_never_index' ] && spotlight_dir_unindexed '$dir'" \
    "touch '$dir/.metadata_never_index' 2>/dev/null && source '$DOTFILES_DIR/lib/spotlight-probe.sh' && spotlight_dir_unindexed '$dir'"
done

# Agent worktrees: a `.metadata_never_index` marker does not stop Spotlight
# there, a `.noindex` folder name does (lib/agent-worktrees-noindex.sh).
if [ -f "$DOTFILES_DIR/lib/agent-worktrees-noindex.sh" ]; then
  # shellcheck source=../../lib/agent-worktrees-noindex.sh
  source "$DOTFILES_DIR/lib/agent-worktrees-noindex.sh"
  # dotfiles-doctor runs each fix in a new process (bash -c).
  export -f agent_worktrees_dir agent_worktrees_noindexed agent_worktrees_noindex_fix
  # Core option spotlight.exclude_worktrees (default true; issue #145):
  # a company plugin may turn it off, for example when MDM owns Spotlight.
  _wf_exclude_worktrees=true
  if declare -F plugin_option >/dev/null; then
    _wf_exclude_worktrees="$(plugin_option spotlight.exclude_worktrees 2>/dev/null || echo true)"
  fi
  if [ "$_wf_exclude_worktrees" = false ]; then
    skipped "agent worktrees left in the Spotlight index (option spotlight.exclude_worktrees: false)"
  elif [ -d "$(dirname "$(agent_worktrees_dir)")" ]; then
    check "spotlight.agent_worktrees" "$(agent_worktrees_dir) is a symlink to a Spotlight-skipped .noindex folder" \
      "agent_worktrees_noindexed" \
      "agent_worktrees_noindex_fix"
  fi
  unset _wf_exclude_worktrees
fi

# Secrets-in-zshrc check removed — covered by security module (dotfiles audit)

# PATH check moved to shell/doctor.sh (shell.dotfiles_on_path)
