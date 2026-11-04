#!/usr/bin/env bats
# Guard: Cursor and Grok (xAI) support stays removed (#189).
# See docs/repo-map.md#deprecated-agents--frozen for the owner's note.
#
# Allowed on purpose (defensive, not support):
# - lib/strip-agent-attribution.sh strips Cursor attribution trailers.
# - CURSOR_AGENT detection in the gh/git wrappers and shell guards.
# - lib/local-ai-agent.py and the tooling-checkup audit treat ~/.cursor as a
#   protected or generated path; they never write there.

REPO="$BATS_TEST_DIRNAME/.."

# Code and config that dotfiles installs or runs. Docs are not scanned.
_code_paths() {
  local p
  for p in .chezmoiscripts agent-hooks bin config dot_config home launchagents \
    lib modules skills/*/scripts Agentfile.yaml .chezmoi.yaml.tmpl \
    .chezmoiignore macos.sh macos-apps.sh macos-visual.sh; do
    [ -e "$REPO/$p" ] && printf '%s\n' "$REPO/$p"
  done
}

@test "no Cursor LaunchAgent comes back" {
  run bash -c "ls '$REPO'/launchagents | grep -i cursor"
  [ "$status" -ne 0 ] || { echo "Cursor LaunchAgent found: $output"; return 1; }
  run grep -rIl -e 'Cursor\.app' -e 'cursor-at-login' -e 'cursor-priority' \
    "$REPO/launchagents" "$REPO/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  [ "$status" -ne 0 ] || { echo "Cursor reference in LaunchAgents: $output"; return 1; }
}

@test "no ~/.cursor write path comes back" {
  run grep -rIn -E '(~|\$HOME|\$\{HOME\}|homeDir \}\})/\.cursor' $(_code_paths) \
    --exclude=strip-agent-attribution.sh \
    --exclude=local-ai-agent.py --exclude=audit_agent_config.py
  [ "$status" -ne 0 ] || { echo "~/.cursor path found: $output"; return 1; }
}

@test "no tracked Cursor output paths outside the guard and removal note" {
  run git -C "$REPO" grep -in '\.cursor/' -- . \
    ':(exclude)tests/no-cursor-grok.bats' ':(exclude)docs/repo-map.md'
  [ "$status" -eq 1 ] || { echo "$output"; return 1; }
}

@test "retired Cursor context gets no dedicated browser session" {
  run env -i PATH=/usr/bin:/bin CURSOR_AGENT=1 TERM_SESSION_ID=fixture bash -c '
    source "$1"
    printf "%s" "${AGENT_BROWSER_SESSION:-}"
  ' _ "$REPO/lib/agent-browser-session-env.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no use_cursor switch or no-Cursor Agentfile layer comes back" {
  run grep -rIn -i -e 'use_cursor' -e 'agentfile-no-cursor' $(_code_paths) "$REPO/tests" \
    --exclude=no-cursor-grok.bats
  [ "$status" -ne 0 ] || { echo "use_cursor found: $output"; return 1; }
  [ ! -e "$REPO/config/agentfile-no-cursor.yaml" ]
}

@test "no Cursor doctor module, settings, or chezmoi scripts come back" {
  [ ! -e "$REPO/modules/cursor" ]
  [ ! -e "$REPO/cursor" ]
  [ ! -e "$REPO/bin/cursor-at-login" ]
  [ ! -e "$REPO/bin/cursor-priority" ]
  run bash -c "ls '$REPO'/.chezmoiscripts | grep -i cursor"
  [ "$status" -ne 0 ] || { echo "Cursor chezmoi script found: $output"; return 1; }
}

@test "topgrade keeps the Cursor steps disabled and adds no Cursor command" {
  local cfg="$REPO/dot_config/topgrade.toml.tmpl"
  local disable
  disable="$(awk '/^disable = \[/,/^\]/' "$cfg")"
  [[ "$disable" == *'"cursor"'* ]]
  [[ "$disable" == *'"cursor_agent"'* ]]
  run bash -c "awk '/^\[commands\]/,/^\[[a-z_]+\]\$/' '$cfg' | grep -v '^#' | grep -i cursor"
  [ "$status" -ne 0 ] || { echo "Cursor topgrade command found: $output"; return 1; }
}

@test "no Grok or xAI support comes back" {
  run grep -rIn -i -E '\bgrok\b|api\.x\.ai|\bxai\b|xai[-_]api' $(_code_paths)
  [ "$status" -ne 0 ] || { echo "Grok/xAI reference found: $output"; return 1; }
}

@test "the owner's note stays in the agent guide, repo map, and README" {
  local note="Cursor and Grok support was removed on purpose on 2026-10-19, because the author is certain that the companies behind these tools support war crimes in Ukraine. This is the author’s position. Please do not add support for these tools back. Slava Ukraini!"
  grep -Fq "$note" "$REPO/AGENTS.md"
  grep -Fq "$note" "$REPO/docs/repo-map.md"
  grep -Fq "$note" "$REPO/README.md"
}
