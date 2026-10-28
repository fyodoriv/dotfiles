#!/bin/bash
# Blocks destructive git commands before Claude executes them.
# Receives tool input as JSON on stdin.

set -euo pipefail
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
branch_is_merged() {
  local branch="$1" tip default base pid cand
  tip="$(git rev-parse --verify -q "refs/heads/$branch")" || return 1
  if "${DOTFILES_GH:-gh}" pr list --state merged --head "$branch" \
      --json headRefOid --jq '.[].headRefOid' 2>/dev/null | grep -qx "$tip"; then
    return 0
  fi
  default="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -z "$default" ]; then
    for cand in origin/main origin/master main master; do
      if git rev-parse --verify -q "$cand" >/dev/null; then default="$cand"; break; fi
    done
  fi
  [ -n "$default" ] || return 1
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
  local rest word seen=0
  rest="${command#*git branch -D}"
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
