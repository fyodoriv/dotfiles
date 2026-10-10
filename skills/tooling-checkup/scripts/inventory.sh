#!/bin/bash
# Print the outstanding work in each primary tooling checkout, one verdict per
# item. Read-only except for `git fetch`.
#
# Usage: inventory.sh
#
# Environment:
#   TOOLING_ROOT                     parent of the tooling checkouts (default ~/apps/tooling)
#   TOOLING_CHECKUP_BOT_BRANCH_RE    ERE for automation branches that are never outstanding work
#   TOOLING_CHECKUP_NO_FETCH=1       skip `git fetch`
#   TOOLING_CHECKUP_NO_GH=1          skip pull request and security-alert lookups
#
# Verdicts:
#   ship       work that is not on the canonical branch yet
#   salvage    uncommitted files or stashes; look before anything else
#   clean-up   local branch already merged into the canonical branch
#   pipeline   linked worktree under <repo>/.worktrees (an orchestrator owns it)
#   bot        automation branches; not outstanding work (one summary line)
#   skip       dependabot pull requests; not outstanding unless the user names one
#   security   open critical dependabot alert; this counts as outstanding work
#   advisory   summary of open high dependabot alerts; report only
#   unknown    the script could not decide; check by hand

set -uo pipefail

TOOLING_ROOT="${TOOLING_ROOT:-$HOME/apps/tooling}"
BOT_BRANCH_RE="${TOOLING_CHECKUP_BOT_BRANCH_RE:-^(dependabot/|mape-k-ingestion/|observer-dogfood/|tasks-claims$|tasksmd/generated-snapshot$)}"
NO_FETCH="${TOOLING_CHECKUP_NO_FETCH:-0}"
NO_GH="${TOOLING_CHECKUP_NO_GH:-0}"

say() { printf '  %-9s %s\n' "$1" "$2"; }

# Bash regex match: no subprocess per branch (this runs on a loaded machine).
is_bot() { [[ $1 =~ $BOT_BRANCH_RE ]]; }

bots=""
note_bot() { bots="$bots$1"$'\n'; }
flush_bots() {
  [ -n "$bots" ] || return 0
  printf '%s' "$bots" | awk '
    { key = $0; sub(/\/.*/, "/", key); n++; if (!(key in c)) order[++k] = key; c[key]++ }
    END {
      line = ""
      for (i = 1; i <= k; i++) line = line (line ? ", " : "") order[i] " x" c[order[i]]
      printf "  %-9s %d automation branch(es), not outstanding: %s\n", "bot", n, line
    }'
  bots=""
}

github_slug() {
  # git@github.com:owner/repo.git or https://github.com/owner/repo(.git)
  local url="${1%.git}"
  case "$url" in
    *github.com[:/]*/*) printf '%s\n' "${url#*github.com[:/]}" ;;
    *) return 1 ;;
  esac
}

if [ ! -d "$TOOLING_ROOT" ]; then
  echo "inventory: TOOLING_ROOT does not exist: $TOOLING_ROOT" >&2
  exit 2
fi

found=0
for repo in "$TOOLING_ROOT"/*; do
  # A linked worktree has a .git file, not a directory. Primary checkouts only.
  [ -d "$repo/.git" ] || continue
  found=$((found + 1))
  echo "== $(basename "$repo")"

  if [ "$NO_FETCH" != "1" ] && ! git -C "$repo" fetch --prune --quiet origin 2>/dev/null; then
    say unknown "fetch from origin failed; results use the last fetched state"
  fi

  canonical="$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  canonical="${canonical#origin/}"
  if [ -z "$canonical" ]; then
    say unknown "origin/HEAD is not set; run: git -C $repo remote set-head origin --auto"
    continue
  fi
  base="origin/$canonical"

  dirty="$(git -C "$repo" status --porcelain | wc -l | tr -d ' ')"
  [ "$dirty" -gt 0 ] && say salvage "main checkout has $dirty uncommitted path(s)"

  stashes="$(git -C "$repo" stash list | wc -l | tr -d ' ')"
  [ "$stashes" -gt 0 ] && say salvage "$stashes stash(es)"

  # One git call for every branch: name, commits ahead of base, upstream, and
  # commits not pushed to that upstream.
  locals=" "
  while IFS=$'\t' read -r ref ahead_behind track; do
    [ -n "$ref" ] || continue
    ahead="${ahead_behind%% *}"
    case "$ref" in
      refs/heads/*)
        branch="${ref#refs/heads/}"
        locals="$locals$branch "
        if [ "$ahead" = "0" ]; then
          [ "$branch" = "$canonical" ] || say clean-up "local branch $branch is merged into $canonical"
          continue
        fi
        if is_bot "$branch"; then note_bot "$branch"; continue; fi
        case "$track" in
          -) say ship "branch $branch has $ahead commit(s) not in $canonical (no upstream)" ;;
          *ahead* | *gone*) say ship "branch $branch has $ahead commit(s) not in $canonical (upstream: ${track#u:})" ;;
          *) say ship "branch $branch has $ahead commit(s) not in $canonical (pushed)" ;;
        esac
        ;;
      refs/remotes/origin/*)
        short="${ref#refs/remotes/origin/}"
        case "$short" in HEAD | "$canonical") continue ;; esac
        case "$locals" in *" $short "*) continue ;; esac
        [ "$ahead" = "0" ] && continue
        if is_bot "$short"; then note_bot "$short"; continue; fi
        say ship "remote branch $short has $ahead commit(s) not in $canonical"
        ;;
    esac
  done < <(git -C "$repo" for-each-ref --sort=refname \
    --format="%(refname)%09%(ahead-behind:$base)%09%(if)%(upstream)%(then)u:%(upstream:track,nobracket)%(else)-%(end)" \
    refs/heads refs/remotes/origin)

  # Linked worktrees. git prints real paths, so compare with the real path.
  repo_real="$(cd "$repo" && pwd -P)"
  while IFS= read -r wt; do
    [ "$wt" = "$repo_real" ] && continue
    if [ ! -d "$wt" ]; then
      say unknown "worktree $wt is registered but missing (git worktree prune)"
      continue
    fi
    wt_branch="$(git -C "$wt" branch --show-current 2>/dev/null)"
    wt_dirty="$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    case "$wt" in
      "$repo_real"/.worktrees/*) say pipeline "worktree $wt [${wt_branch:-detached}] belongs to an orchestrator" ;;
      *)
        if [ "$wt_dirty" -gt 0 ]; then
          say salvage "worktree $wt [${wt_branch:-detached}] has $wt_dirty uncommitted path(s)"
        else
          say ship "worktree $wt [${wt_branch:-detached}] is clean; ship or remove its branch"
        fi
        ;;
    esac
  done < <(git -C "$repo" worktree list --porcelain | sed -n 's/^worktree //p')

  if [ "$NO_GH" = "1" ]; then
    flush_bots
    continue
  fi
  if ! command -v gh >/dev/null 2>&1; then
    flush_bots
    say unknown "gh is not installed; pull requests and alerts not checked"
    continue
  fi
  if ! slug="$(github_slug "$(git -C "$repo" remote get-url origin)")"; then
    flush_bots
    say unknown "origin is not a GitHub remote; pull requests not checked"
    continue
  fi

  if prs="$(gh pr list -R "$slug" --state open --limit 100 \
      --json number,title,headRefName,author \
      --jq '.[] | [.number, .author.login, .headRefName, .title] | @tsv' 2>/dev/null)"; then
    deps=0
    while IFS=$'\t' read -r number author head title; do
      [ -n "$number" ] || continue
      case "$author" in
        app/dependabot | dependabot*) deps=$((deps + 1)); continue ;;
      esac
      if is_bot "$head"; then
        note_bot "$head"
      else
        say ship "PR #$number $head: $title"
      fi
    done <<< "$prs"
    flush_bots
    [ "$deps" -gt 0 ] && say skip "$deps dependabot PR(s); not outstanding unless the user names one"
  else
    flush_bots
    say unknown "gh pr list failed for $slug"
  fi

  if alerts="$(gh api --paginate "repos/$slug/dependabot/alerts?state=open&severity=critical,high&per_page=100" \
      --jq '.[] | [.security_advisory.severity, .dependency.package.name, .security_advisory.ghsa_id, (.dependency.scope // "unknown")] | @tsv' 2>/dev/null)"; then
    # Critical alerts are outstanding work: one line each. High alerts get a
    # one-line summary for the report.
    printf '%s\n' "$alerts" | awk -F'\t' '
      $1 == "critical" { printf "  %-9s critical %s %s (%s)\n", "security", $2, $3, $4 }
      $1 == "high" { n++; if ($4 == "runtime") r++; if (!seen[$2]++) pkgs = pkgs (pkgs ? ", " : "") $2 }
      END { if (n) printf "  %-9s %d high alert(s), %d runtime: %s\n", "advisory", n, r, pkgs }'
  else
    say unknown "dependabot alerts API unavailable for $slug"
  fi
done

if [ "$found" -eq 0 ]; then
  echo "inventory: no primary git checkouts under $TOOLING_ROOT" >&2
  exit 2
fi
