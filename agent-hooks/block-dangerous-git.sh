#!/bin/bash
# Blocks destructive git commands before Claude executes them.
# Receives tool input as JSON on stdin.

set -euo pipefail
# No globbing: a branch word like feat/* must stay literal when split below.
set -f
_hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=bootstrap-endpoint-path.sh
source "$_hook_dir/bootstrap-endpoint-path.sh"

input=$(cat)
command="$(printf '%s' "$input" \
  | /usr/bin/plutil -extract tool_input.command raw -o - -- - 2>/dev/null || true)"
hook_cwd="$(printf '%s' "$input" \
  | /usr/bin/plutil -extract cwd raw -o - -- - 2>/dev/null || true)"

block() {
  echo "BLOCKED: '$1' is not permitted. Ask the user to run it manually." >&2
  exit 2
}

# A squash merge leaves the branch commits off the default branch, so the safe
# lowercase delete refuses the branch. Treat a branch as merged only when:
#   1. its tip is the head commit of a MERGED pull request, or
#   2. its tip is already in the default branch, or
#   3. its whole diff is already on the default branch as one commit (same
#      stable patch-id).
# Run gh with a time limit (default 10 s, DOTFILES_GH_TIMEOUT) using gtimeout or
# timeout. With neither binary the PR proof is skipped: a perl alarm cannot stop
# gh (Go ignores SIGALRM), so the local patch-id proof decides alone. A hung or
# missing gh gives no output, so the PR proof fails the same way.
# DOTFILES_TIMEOUT_BIN overrides the lookup (empty = none; used by tests).
gh_with_timeout() {
  local t="${DOTFILES_GH_TIMEOUT:-10}" tmo
  tmo="${DOTFILES_TIMEOUT_BIN-$(command -v gtimeout || command -v timeout || true)}"
  [ -n "$tmo" ] || return 1
  "$tmo" "$t" "${DOTFILES_GH:-gh}" "$@"
}

branch_is_merged() {
  local branch="$1" tip default base pid cand
  tip="$(git rev-parse --verify -q "refs/heads/$branch")" || return 1
  default="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -z "$default" ]; then
    for cand in origin/main origin/master main master; do
      if git rev-parse --verify -q "$cand" >/dev/null; then default="$cand"; break; fi
    done
  fi
  [ -n "$default" ] || return 1
  # Only a PR merged into the default branch counts (not a side branch).
  if gh_with_timeout pr list --state merged --head "$branch" --base "${default#origin/}" \
      --json headRefOid --jq '.[].headRefOid' 2>/dev/null | grep -qx "$tip"; then
    return 0
  fi
  if git merge-base --is-ancestor "$tip" "$default" 2>/dev/null; then return 0; fi
  base="$(git merge-base "$default" "$tip" 2>/dev/null)" || return 1
  pid="$(git diff "$base" "$tip" | git patch-id --stable | cut -d' ' -f1)"
  [ -n "$pid" ] || return 1
  git log -n 200 --format=%H "$base..$default" | while read -r cand; do
    git show "$cand" | git patch-id --stable | cut -d' ' -f1
  done | grep -qx "$pid"
}

# True when every branch named after the force-delete flag is proven merged.
# Any quote, expansion, redirect, or extra flag in the argument list fails closed.
branch_delete_allowed() {
  local rest word seen=0 flag="git branch -D" stripped prefix
  # Fail closed on more than one occurrence: only the first would be checked.
  stripped="${command//"$flag"/}"
  [ $(( (${#command} - ${#stripped}) / ${#flag} )) -eq 1 ] || return 1
  # Fail closed on anything before the command (a cd, GIT_DIR=..., another
  # command): the proof below runs in the hook's folder, not where that would act.
  prefix="${command%%"$flag"*}"
  [ -z "${prefix//[[:space:]]/}" ] || return 1
  rest="${command#*git branch -D}"
  # A backslash can continue the line, so the shell would delete branches this
  # parser cuts off at the newline. Fail closed.
  case "$rest" in *\\*) return 1 ;; esac
  # A redirect to /dev/null or stderr-to-stdout never changes which branches go,
  # but only when it is its own word: glued to a name (m2>&1) it is part of the
  # name m2, so it stays and the check below rejects the ">".
  rest=" $rest "
  for _ in 1 2 3; do
    rest="${rest// 2>&1 / }"
    rest="${rest// 2>\/dev\/null / }"
    rest="${rest// >\/dev\/null / }"
  done
  rest="${rest%%[;&|$'\n']*}"
  if [ -n "$hook_cwd" ]; then cd "$hook_cwd" 2>/dev/null || return 1; fi
  for word in $rest; do
    case "$word" in
      --) continue ;;
      -* | *[\"\'\`\$\(\)\<\>]*) return 1 ;;
    esac
    seen=1
    branch_is_merged "$word" || return 1
  done
  [ "$seen" -eq 1 ]
}

case "$command" in
  *"git reset --hard"*)   block "git reset --hard" ;;
  *"git clean -f"*)       block "git clean -f" ;;
  *"git checkout ."*)     block "git checkout ." ;;
  *"git restore ."*)      block "git restore ." ;;
esac

# Checked last so a merged-branch delete never masks another blocked command.
case "$command" in
  *"git branch -D"*)      branch_delete_allowed || block "git branch -D" ;;
esac

exit 0
