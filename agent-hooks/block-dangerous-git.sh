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

# True when the command could destroy or overwrite a local branch: the old
# literal text anywhere, or a git word, then global options, then a subcommand
# that can do it:
#   branch   with -D, -d with -f, --delete with --force (or prefixes), -M, -m
#            with -f, or a lone -f/--force (moves a branch);
#   update-ref  with -d, --stdin, or a refs/heads/ word;
#   push     with a "." word (push to this same repo, e.g. ". :<branch>").
# Words are normalized first (quotes and backslashes dropped, path stripped),
# so 'git', g''it, \git, /usr/bin/git and git \branch are all seen. A command
# the shell rewrites before git runs ($'..', ${..}, $(..), backticks, a glob in
# the git path) that also names branch or update-ref and a delete-like flag is
# a match too. The strict parser below then rejects every such form, so they
# block.
looks_like_branch_delete() {
  local -a w rw
  local i n j k opt norm word base hasD hasd hasf hasM hasm unk dyn=0 sub=0 flagish=0
  case "$command" in
    *[gG][iI][tT]" "[bB][rR][aA][nN][cC][hH]" -D"*) return 0 ;;
  esac
  norm="${command//\'/}"
  norm="${norm//\"/}"
  norm="${norm//\\/}"
  # shellcheck disable=SC2206
  w=($norm)
  # shellcheck disable=SC2206
  rw=($command)
  n=${#w[@]}
  # Shell-rewrite spellings: the words below cannot be read, so fail closed.
  case "$command" in
    *\$\'*|*\$\"*|*\$\{*|*\$\(*|*\`*) dyn=1 ;;
  esac
  for word in "${rw[@]}"; do
    base="${word##*/}"
    case "$base" in
      *[\?\*\[]*) [ "${#base}" -le 4 ] && dyn=1 ;;
    esac
    case "$word" in
      \$\'*|\$\{*|\`*) flagish=1 ;;
    esac
  done
  if [ "$dyn" -eq 1 ]; then
    for opt in "${w[@]}"; do
      case "$opt" in update-ref) sub=1 ;; esac
      is_branch_word "$opt" && sub=1
      case "$opt" in
        --*) if is_long_prefix "$opt" delete || is_long_prefix "$opt" force; then flagish=1; fi ;;
        -?*) case "$opt" in *[DdfMm]*) flagish=1 ;; esac ;;
      esac
    done
    if [ "$sub" -eq 1 ] && [ "$flagish" -eq 1 ]; then return 0; fi
  fi
  for ((i = 0; i < n; i++)); do
    is_git_word "${w[i]##*/}" || continue
    hasD=0 hasd=0 hasf=0 hasM=0 hasm=0 unk=0
    j=$((i + 1))
    # Skip global options that may precede the subcommand. -c, --config-env and
    # unknown options can define an alias for a subcommand, so they count.
    while [ "$j" -lt "$n" ]; do
      case "${w[j]}" in
        -C|--git-dir|--work-tree|--namespace) j=$((j + 2)) ;;
        -c|--config-env) unk=1; j=$((j + 2)) ;;
        --git-dir=*|--work-tree=*|--namespace=*|--no-pager|-p|--paginate) j=$((j + 1)) ;;
        -*) unk=1; j=$((j + 1)) ;;
        *) break ;;
      esac
    done
    [ "$j" -lt "$n" ] || continue
    case "${w[j]}" in
      update-ref)
        for ((k = j + 1; k < n; k++)); do
          case "${w[k]}" in -d|--stdin|refs/heads/*|refs/remotes/*) return 0 ;; esac
        done ;;
      push)
        for ((k = j + 1; k < n; k++)); do
          [ "${w[k]}" = "." ] && return 0
        done ;;
    esac
    if is_branch_word "${w[j]}" || [ "$unk" -eq 1 ]; then
      for ((k = j + 1; k < n; k++)); do
        opt="${w[k]}"
        case "$opt" in
          --*)
            if is_long_prefix "$opt" delete; then hasd=1; fi
            if is_long_prefix "$opt" force; then hasf=1; fi ;;
          -?*)
            case "$opt" in *D*) hasD=1 ;; esac
            case "$opt" in *d*) hasd=1 ;; esac
            case "$opt" in *f*) hasf=1 ;; esac
            case "$opt" in *M*) hasM=1 ;; esac
            case "$opt" in *m*) hasm=1 ;; esac ;;
        esac
      done
      if [ "$hasD" -eq 1 ] || { [ "$hasd" -eq 1 ] && [ "$hasf" -eq 1 ]; }; then return 0; fi
      # Moving or renaming over a branch only counts for the branch subcommand.
      if is_branch_word "${w[j]}"; then
        if [ "$hasM" -eq 1 ] || [ "$hasf" -eq 1 ]; then return 0; fi
      fi
    fi
  done
  return 1
}

# A branch that does not exist yet has nothing to lose; an existing one needs
# the merged proof.
target_ok() {
  git show-ref --verify --quiet "refs/heads/$1" || return 0
  branch_is_merged "$1"
}

# True when the command is one plain git call that deletes or overwrites
# branches and every branch it would lose is proven merged, in the repo the
# command acts on. Anything unusual fails closed.
branch_delete_allowed() {
  local rest word seen=0 name_re='^[A-Za-z0-9._/-]+$' dir_re='^[A-Za-z0-9._/-]+$'
  local rev_re='^[A-Za-z0-9._/~^@-]+$' hex_re='^[0-9a-f]{7,64}$'
  local -a w names
  local i n opt dflag=0 Dflag=0 fflag=0 Mflag=0 mflag=0 gitdir="" sub name ref
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
  [ "$i" -lt "$n" ] || return 1
  if [ -n "$gitdir" ]; then
    gitdir="$(cd "$gitdir" 2>/dev/null && pwd -P)" || return 1
    export GIT_DIR="$gitdir"
  fi
  sub="${w[i]}"
  i=$((i + 1))
  case "$sub" in
    update-ref)
      # update-ref [-d] [--no-deref] <refs/...> [<value>]
      for ((; i < n; i++)); do
        word="${w[i]}"
        case "$word" in
          -d|--no-deref) continue ;;
          refs/remotes/*) return 1 ;;
          refs/heads/*)
            name="${word#refs/heads/}"
            [[ "$name" =~ $name_re ]] || return 1
            target_ok "$name" || return 1
            seen=1 ;;
          refs/*)
            [[ "$word" =~ $name_re ]] || return 1
            seen=1 ;;
          *)
            # A value (commit or revision) may follow the ref, never lead.
            [ "$seen" -eq 1 ] || return 1
            { [[ "$word" =~ $hex_re ]] || [[ "$word" =~ $rev_re ]]; } || return 1
            case "$word" in -*) return 1 ;; esac ;;
        esac
      done
      [ "$seen" -eq 1 ]
      return ;;
    push)
      # push . :<branch> ...: only deletions into this same repo are understood.
      [ "${w[i]}" = "." ] || return 1
      i=$((i + 1))
      for ((; i < n; i++)); do
        word="${w[i]}"
        case "$word" in
          :refs/heads/*) name="${word#:refs/heads/}" ;;
          :*) name="${word#:}" ;;
          *) return 1 ;;
        esac
        [[ "$name" =~ $name_re ]] || return 1
        case "$name" in -*) return 1 ;; esac
        target_ok "$name" || return 1
        seen=1
      done
      [ "$seen" -eq 1 ]
      return ;;
    *)
      is_branch_word "$sub" || return 1 ;;
  esac
  names=()
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
      -M) Mflag=1; continue ;;
      -m) mflag=1; continue ;;
      -df|-fd) dflag=1; fflag=1; continue ;;
      -Df|-fD) Dflag=1; fflag=1; continue ;;
    esac
    # Strict allow list: no braces, quotes, expansions, globs, or other flags
    # (-Dr and -r would touch remote-tracking refs).
    [[ "$word" =~ $name_re ]] || return 1
    case "$word" in -*) return 1 ;; esac
    names+=("$word")
  done
  [ "${#names[@]}" -ge 1 ] || return 1
  if [ "$Dflag" -eq 1 ] || { [ "$dflag" -eq 1 ] && [ "$fflag" -eq 1 ]; }; then
    # Delete: every branch named must exist and be proven merged.
    [ "$Mflag" -eq 0 ] && [ "$mflag" -eq 0 ] || return 1
    for name in "${names[@]}"; do
      branch_is_merged "$name" || return 1
    done
    return 0
  fi
  [ "$dflag" -eq 0 ] || return 1
  if [ "$Mflag" -eq 1 ] || { [ "$mflag" -eq 1 ] && [ "$fflag" -eq 1 ]; }; then
    # Rename over the last name: its old tip must be proven merged.
    target_ok "${names[${#names[@]} - 1]}"
    return
  fi
  if [ "$fflag" -eq 1 ] && [ "$mflag" -eq 0 ]; then
    # Move the first name to another commit: its old tip must be proven merged.
    target_ok "${names[0]}"
    return
  fi
  return 1
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
