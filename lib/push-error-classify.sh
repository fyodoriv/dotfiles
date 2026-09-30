#!/bin/bash
# push-error-classify.sh — map raw git push/pull stderr → concise human reason.
#
# Used by bin/dotfiles-sync (and the doctor's sync module) to replace the
# legacy "(offline?)" catch-all so LaunchAgent logs are actually useful when
# something goes wrong. Pure function; safe to source repeatedly.

_classify_push_error() {
  local err="$1"
  case "$err" in
    *"Could not resolve host"*|*"Network is unreachable"*|*"Operation timed out"*|*"Failed to connect"*)
      echo "offline or DNS failure" ;;
    *"Permission denied"*|*"Authentication failed"*|*"could not read Username"*|*"could not read Password"*)
      echo "auth (token expired or missing)" ;;
    *"non-fast-forward"*|*"failed to push some refs"*|*"rejected"*)
      echo "non-fast-forward (remote has changes — pull/rebase first)" ;;
    *"protected branch"*|*"required status check"*|*"GH006"*|*"GH013"*|*"required check"*)
      echo "branch protection (push directly blocked — use a PR)" ;;
    *"pre-receive hook declined"*|*"pre-push hook"*)
      echo "pre-receive/pre-push hook declined" ;;
    *"shallow update not allowed"*)
      echo "shallow clone — unshallow before pushing" ;;
    "")
      echo "no stderr captured" ;;
    *)
      # First non-blank line, trimmed to 160 chars, is usually the real cause.
      local first_line
      first_line=$(printf '%s\n' "$err" | grep -v '^[[:space:]]*$' | head -1 | cut -c1-160)
      echo "${first_line:-unknown error}" ;;
  esac
}
