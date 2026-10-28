#!/bin/bash
# Blocks destructive git commands before Claude executes them.
# Receives tool input as JSON on stdin.

set -euo pipefail
# No globbing: a branch word like feat/* must stay literal when split below.
set -f
# SECONDS counts the hook's whole run; it caps the total time spent in gh.
SECONDS=0
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
#   1. its tip is already in the default branch, or
#   2. its whole diff is already on the default branch as one commit (same
#      stable patch-id), or
#   3. its tip is the head commit of a MERGED pull request into the default
#      branch (gh is asked last, only for branches 1 and 2 do not prove).

# Run gh under gtimeout or timeout. The time for ALL gh calls together is capped
# (DOTFILES_GH_BUDGET, default 15 s); one call gets at most DOTFILES_GH_TIMEOUT
# (default 10 s). With no timeout binary the PR proof is skipped, because a perl
# alarm cannot stop gh (Go ignores SIGALRM). A hung, missing, or over-budget gh
# gives no output, so the PR proof fails and the branch stays blocked.
# DOTFILES_TIMEOUT_BIN overrides the lookup (empty = none; used by tests).
gh_with_timeout() {
  local t="${DOTFILES_GH_TIMEOUT:-10}" budget="${DOTFILES_GH_BUDGET:-15}" tmo left
  tmo="${DOTFILES_TIMEOUT_BIN-$(command -v gtimeout || command -v timeout || true)}"
  [ -n "$tmo" ] || return 1
  left=$(( budget - SECONDS ))
  [ "$left" -gt 0 ] || return 1
  [ "$t" -le "$left" ] || t="$left"
  "$tmo" "$t" "${DOTFILES_GH:-gh}" "$@"
}

# Print the default branch ref (refs/remotes/origin/<name>) or fail closed. A
# forged origin/HEAD that points outside refs/remotes/origin/ is refused.
default_ref() {
  local target cand
  if target="$(git symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null)"; then
    case "$target" in
      refs/remotes/origin/?*) printf '%s\n' "$target"; return 0 ;;
      *) return 1 ;;
    esac
  fi
  for cand in main master; do
    if git show-ref --verify --quiet "refs/remotes/origin/$cand"; then
      printf 'refs/remotes/origin/%s\n' "$cand"; return 0
    fi
  done
  return 1
}

branch_is_merged() {
  local branch="$1" tip default name base pid cand
  git show-ref --verify --quiet "refs/heads/$branch" || return 1
  tip="$(git rev-parse "refs/heads/$branch")" || return 1
  default="$(default_ref)" || return 1
  name="${default#refs/remotes/origin/}"
  # Never trust a default branch that carries the name of the branch to delete.
  [ "$name" != "$branch" ] || return 1
  if git merge-base --is-ancestor "$tip" "$default" 2>/dev/null; then return 0; fi
  base="$(git merge-base "$default" "$tip" 2>/dev/null)" || return 1
  pid="$(git diff "$base" "$tip" | git patch-id --stable | cut -d' ' -f1)"
  if [ -n "$pid" ] && git log -n 200 --format=%H "$base..$default" | while read -r cand; do
    git show "$cand" | git patch-id --stable | cut -d' ' -f1
  done | grep -qx "$pid"; then
    return 0
  fi
  # Only a PR merged into the default branch counts (not a side branch).
  gh_with_timeout pr list --state merged --head "$branch" --base "$name" \
    --json headRefOid --jq '.[].headRefOid' 2>/dev/null | grep -qx "$tip"
}

# True when the command is one plain force-delete and every branch named after
# it is proven merged. Anything unusual fails closed.
branch_delete_allowed() {
  local rest word seen=0 flag="git branch -D" stripped prefix name_re='^[A-Za-z0-9._/-]+$'
  # The flag must be spelled exactly (git matches case-insensitively on some
  # file systems, but the parser below does not).
  case "$command" in *"$flag"*) ;; *) return 1 ;; esac
  # Fail closed on more than one occurrence: only the first would be checked.
  stripped="${command//"$flag"/}"
  [ $(( (${#command} - ${#stripped}) / ${#flag} )) -eq 1 ] || return 1
  # Fail closed on anything before the command (a cd, GIT_DIR=..., another
  # command): the proof below runs in the hook's folder, not where that would act.
  prefix="${command%%"$flag"*}"
  [ -z "${prefix//[[:space:]]/}" ] || return 1
  rest="${command#*"$flag"}"
  # A redirect to /dev/null or stderr-to-stdout never changes which branches go,
  # but only when it is its own word: glued to a name (m2>&1) it is part of the
  # name m2, so it stays and the name check below rejects the ">".
  rest=" $rest "
  for _ in 1 2 3; do
    rest="${rest// 2>&1 / }"
    rest="${rest// 2>\/dev\/null / }"
    rest="${rest// >\/dev\/null / }"
  done
  # A chained command (; & | newline) may hide a second delete after it, and a
  # backslash can continue the line. Fail closed on any of them.
  case "$rest" in *[\;\&\|\\$'\n']*) return 1 ;; esac
  if [ -n "$hook_cwd" ]; then cd "$hook_cwd" 2>/dev/null || return 1; fi
  for word in $rest; do
    [ "$word" = "--" ] && continue
    # Strict allow list: no braces, quotes, expansions, globs, or flags.
    [[ "$word" =~ $name_re ]] || return 1
    case "$word" in -*) return 1 ;; esac
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
# "git branch" is matched in any letter case (git does so on case-insensitive
# file systems); the flag stays capital D. The exact-case parser then fails closed.
case "$command" in
  *[gG][iI][tT]" "[bB][rR][aA][nN][cC][hH]" -D"*)
    branch_delete_allowed || block "git branch -D" ;;
esac

exit 0
