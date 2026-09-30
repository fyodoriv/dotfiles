# Shared AGENT_BROWSER_SESSION assignment for agent contexts.
# Sourced from ~/.config/dotfiles/env.sh (all zsh shells via ~/.zshenv) and
# ~/.zshrc.ai-tools so non-interactive agent subprocesses inherit a stable
# per-agent daemon name without loading the full ai-tools wrapper block.
#
# Detection mirrors `bin/gh`'s `_gh_wrapper_is_agent_context` and
# modules/agent-browser/doctor.sh agent_session_isolation.

_dotfiles_assign_agent_browser_session() {
  [ -n "${AGENT_BROWSER_SESSION:-}" ] && return 0

  if [ -n "${DEVIN_SESSION_ID:-}" ]; then
    AGENT_BROWSER_SESSION="devin-${DEVIN_SESSION_ID:0:8}"
  elif [ -n "${CLAUDE_CODE_SSE_PORT:-}" ]; then
    AGENT_BROWSER_SESSION="claude-${CLAUDE_CODE_SSE_PORT}"
  elif [ -n "${CURSOR_AGENT:-}" ]; then
    AGENT_BROWSER_SESSION="cursor-${TERM_SESSION_ID:-$$}"
  elif [ -n "${WINDSURF_AGENT:-}" ]; then
    AGENT_BROWSER_SESSION="windsurf-${TERM_SESSION_ID:-$$}"
  elif [ -n "${CODEX_AGENT:-}" ]; then
    AGENT_BROWSER_SESSION="codex-${TERM_SESSION_ID:-$$}"
  else
    return 0
  fi

  AGENT_BROWSER_SESSION="${AGENT_BROWSER_SESSION:0:24}"
  export AGENT_BROWSER_SESSION
  export _DOTFILES_AGENT_BROWSER_IMPLICIT_SESSION=1
}

_dotfiles_assign_agent_browser_session
