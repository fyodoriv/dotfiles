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

# Patch-ids of the default branch's last 200 commits, computed once per run.
FP_CACHE="" FP_DONE=0
default_fingerprints() {
  local default="$1" cand
  [ "$FP_DONE" -eq 1 ] && return 0
  FP_CACHE="$(git log -n 200 --format=%H "$default" | while read -r cand; do
    git show "$cand" | git patch-id --stable | cut -d' ' -f1
  done)"
  FP_DONE=1
}

branch_is_merged() {
  local branch="$1" tip default name base pid out
  git show-ref --verify --quiet "refs/heads/$branch" || return 1
  tip="$(git rev-parse "refs/heads/$branch")" || return 1
  default="$(default_ref)" || return 1
  name="${default#refs/remotes/origin/}"
  # Never trust a default branch that carries the name of the branch to delete.
  [ "$name" != "$branch" ] || return 1
  if git merge-base --is-ancestor "$tip" "$default" 2>/dev/null; then return 0; fi
  base="$(git merge-base "$default" "$tip" 2>/dev/null)" || return 1
  pid="$(git diff "$base" "$tip" | git patch-id --stable | cut -d' ' -f1)"
  if [ -n "$pid" ]; then
    default_fingerprints "$default"
    if grep -qx -- "$pid" <<<"$FP_CACHE"; then return 0; fi
  fi
  # Only a PR merged into the default branch counts (not a side branch). Save
  # gh's answer first: grep -q would stop reading early and kill a big answer.
  out="$(gh_with_timeout pr list --state merged --head "$branch" --base "$name" \
    --json headRefOid --jq '.[].headRefOid' 2>/dev/null)" || return 1
  grep -qx -- "$tip" <<<"$out"
}

is_git_word() { case "$1" in [gG][iI][tT]) return 0 ;; esac; return 1; }
is_branch_word() { case "$1" in [bB][rR][aA][nN][cC][hH]) return 0 ;; esac; return 1; }

# True when the word is a long option that git would read as --delete (or
# --force): git accepts any unambiguous prefix. Every prefix of delete counts
# (--d, --de); force needs 4 letters (--fo and --for clash with --format).
is_long_prefix() {
  local name="${1#--}" min=1
  [ "$2" = force ] && min=4
  [ "${#name}" -ge "$min" ] || return 1
  case "$2" in "$name"*) return 0 ;; esac
  return 1
}

# True when the command could force-delete a branch: the old literal text
# anywhere, or a git word, then global options, then "branch" (or an alias
# option that could rename a subcommand to it), then delete flags (-D, -d with
# -f, --delete with --force or their prefixes, glued letters like -Dr or -fd).
# Words are normalized first (quotes and backslashes dropped, path stripped),
# so 'git', g''it, \git, /usr/bin/git and git \branch are all seen. The strict
# parser below then rejects every such form, so they block.
looks_like_branch_delete() {
  local -a w
  local i n j k opt norm hasD hasd hasf unk
  case "$command" in
    *[gG][iI][tT]" "[bB][rR][aA][nN][cC][hH]" -D"*) return 0 ;;
  esac
  norm="${command//\'/}"
  norm="${norm//\"/}"
  norm="${norm//\\/}"
  # shellcheck disable=SC2206
  w=($norm)
  n=${#w[@]}
  for ((i = 0; i < n; i++)); do
    is_git_word "${w[i]##*/}" || continue
    hasD=0 hasd=0 hasf=0 unk=0
    j=$((i + 1))
    # Skip global options that may precede the subcommand. -c, --config-env and
    # unknown options can define an alias for branch, so they count as a match.
    while [ "$j" -lt "$n" ]; do
      case "${w[j]}" in
        -C|--git-dir|--work-tree|--namespace) j=$((j + 2)) ;;
        -c|--config-env) unk=1; j=$((j + 2)) ;;
        --git-dir=*|--work-tree=*|--namespace=*|--no-pager|-p|--paginate) j=$((j + 1)) ;;
        -*) unk=1; j=$((j + 1)) ;;
        *) break ;;
      esac
    done
    if [ "$j" -lt "$n" ] && { is_branch_word "${w[j]}" || [ "$unk" -eq 1 ]; }; then
      for ((k = j + 1; k < n; k++)); do
        opt="${w[k]}"
        case "$opt" in
          --*)
            if is_long_prefix "$opt" delete; then hasd=1; fi
            if is_long_prefix "$opt" force; then hasf=1; fi ;;
          -?*)
            case "$opt" in *D*) hasD=1 ;; esac
            case "$opt" in *d*) hasd=1 ;; esac
            case "$opt" in *f*) hasf=1 ;; esac ;;
        esac
      done
      if [ "$hasD" -eq 1 ] || { [ "$hasd" -eq 1 ] && [ "$hasf" -eq 1 ]; }; then return 0; fi
    fi
  done
  return 1
}

# True when the command is one plain git call that force-deletes branches and
# every branch named is proven merged, in the repo the command acts on.
# Anything unusual fails closed.
branch_delete_allowed() {
  local rest word seen=0 name_re='^[A-Za-z0-9._/-]+$' dir_re='^[A-Za-z0-9._/-]+$'
  local -a w
  local i n opt dflag=0 Dflag=0 fflag=0 gitdir=""
  # A chained command (; & | newline) may hide a second delete, and a backslash
  # can continue the line. Fail closed on any of them, anywhere in the command.
  # A redirect to /dev/null or stderr-to-stdout never changes which branches go,
  # but only as its own word: glued to a name (m2>&1) it stays and fails below.
  rest=" $command "
  for _ in 1 2 3; do
    rest="${rest// 2>&1 / }"
    rest="${rest// 2>\/dev\/null / }"
    rest="${rest// >\/dev\/null / }"
  done
  case "$rest" in *[\;\&\|\\$'\n']*) return 1 ;; esac
  # shellcheck disable=SC2206
  w=($rest)
  n=${#w[@]}
  [ "$n" -ge 3 ] || return 1
  # Nothing may come before git (a cd, GIT_DIR=..., another command).
  is_git_word "${w[0]}" || return 1
  if [ -n "$hook_cwd" ]; then cd "$hook_cwd" 2>/dev/null || return 1; fi
  i=1
  # Global options: only -C <dir> and --git-dir[=]<dir> are understood.
  while [ "$i" -lt "$n" ]; do
    opt="${w[i]}"
    case "$opt" in
      -C)
        [ $((i + 1)) -lt "$n" ] || return 1
        [[ "${w[i+1]}" =~ $dir_re ]] || return 1
        cd "${w[i+1]}" 2>/dev/null || return 1
        i=$((i + 2)) ;;
      --git-dir)
        [ $((i + 1)) -lt "$n" ] || return 1
        [[ "${w[i+1]}" =~ $dir_re ]] || return 1
        gitdir="${w[i+1]}"; i=$((i + 2)) ;;
      --git-dir=*)
        gitdir="${opt#--git-dir=}"
        [[ "$gitdir" =~ $dir_re ]] || return 1
        i=$((i + 1)) ;;
      -*) return 1 ;;
      *) break ;;
    esac
  done
  { [ "$i" -lt "$n" ] && is_branch_word "${w[i]}"; } || return 1
  if [ -n "$gitdir" ]; then
    gitdir="$(cd "$gitdir" 2>/dev/null && pwd -P)" || return 1
    export GIT_DIR="$gitdir"
  fi
  i=$((i + 1))
  for ((; i < n; i++)); do
    word="${w[i]}"
    case "$word" in
      --) continue ;;
      --delete) dflag=1; continue ;;
      --force) fflag=1; continue ;;
      --*)
        # A shortened long option (--del, --forc) is the same option.
        if is_long_prefix "$word" delete; then dflag=1; continue; fi
        if is_long_prefix "$word" force; then fflag=1; continue; fi
        return 1 ;;
      -D) Dflag=1; continue ;;
      -d) dflag=1; continue ;;
      -f) fflag=1; continue ;;
      -df|-fd) dflag=1; fflag=1; continue ;;
      -Df|-fD) Dflag=1; fflag=1; continue ;;
    esac
    # Strict allow list: no braces, quotes, expansions, globs, or other flags
    # (-Dr and -r would touch remote-tracking refs).
    [[ "$word" =~ $name_re ]] || return 1
    case "$word" in -*) return 1 ;; esac
    seen=1
    branch_is_merged "$word" || return 1
  done
  { [ "$Dflag" -eq 1 ] || { [ "$dflag" -eq 1 ] && [ "$fflag" -eq 1 ]; }; } || return 1
  [ "$seen" -eq 1 ]
}

case "$command" in
  *"git reset --hard"*)   block "git reset --hard" ;;
  *"git clean -f"*)       block "git clean -f" ;;
  *"git checkout ."*)     block "git checkout ." ;;
  *"git restore ."*)      block "git restore ." ;;
esac

# Checked last so a merged-branch delete never masks another blocked command.
# The subcommand is parsed, so "git -C <dir> branch", "-d -f", "--delete --force",
# "-fd", and a flag after the branch name are checked like the plain form.
if looks_like_branch_delete; then
  branch_delete_allowed || block "git branch -D"
fi

exit 0
