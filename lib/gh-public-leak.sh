#!/bin/bash
# gh public leak guard. bin/gh sources this file and calls
# `gh_public_leak_guard "$@"` for write-shaped argv only (see
# _gh_is_write_shaped in bin/gh), before any exec or pass-through.
#
# Git hooks never see the text that gh publishes: PR and issue titles,
# bodies and comments, release notes and asset names, squash-merge
# messages, gist files, repo and label descriptions, and gh api fields or
# --input JSON. This guard blocks that text when it carries a private
# reference and the target is public on github.com.
#
# Order of work:
#   1. Parse argv and resolve the target host. No file, stdin, or network.
#   2. A host other than github.com returns 0 here, so GitHub Enterprise
#      posts are never scanned and never cause a network call.
#   3. Collect the raw text before the bin/gh strip pass: flag values,
#      file contents (not path operands), and stdin. Stdin is buffered to
#      a temp file and fd 0 is re-pointed at it, so gh still reads it.
#   4. Run the matchers. No finding returns 0 with no network call.
#   5. Confirm the target is public: config/public-push-remotes.txt
#      first, then the GitHub API. A failed lookup counts as public.
#   6. Exit 1. The message names the field, the class, and the target
#      only. It never prints the matched text or a pattern.
#
# Deliberate post: DOTFILES_ALLOW_GH_PRIVATE_REFS=1. MINSKY_PIPELINE does
# not skip the guard.
#
# State scope: `_ghpl_*` shell variables in one bin/gh process. The temp
# dir is removed before the guard returns or exits. Helpers set result
# variables instead of printing, to keep process forks low.

case "${BASH_SOURCE[0]}" in
  */*) _ghpl_dir="${BASH_SOURCE[0]%/*}" ;;
  *) _ghpl_dir=. ;;
esac

_ghpl_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Sets _ghpl_auth (hosts gh can use, one per line: hosts.yml keys, plus
# github.com when a github.com token is in the environment) and
# _ghpl_dh (the host gh uses when argv and the checkout name none:
# GH_HOST, else the only signed-in host, else github.com).
_ghpl_load_hosts() {
  local hosts_file="${GH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/gh}/hosts.yml"
  _ghpl_auth=""
  if [ -f "$hosts_file" ]; then
    _ghpl_auth="$(awk '/^[^[:space:]#][^:]*:/ {
      h = $0; sub(/:.*/, "", h); gsub(/["'"'"']/, "", h); h = tolower(h)
      if (!(h in seen)) { seen[h] = 1; print h }
    }' "$hosts_file" 2>/dev/null || true)"
  fi
  if [ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ] && ! _ghpl_auth_has github.com; then
    _ghpl_auth="${_ghpl_auth:+$_ghpl_auth$'\n'}github.com"
  fi
  if [ -n "${GH_HOST:-}" ]; then
    _ghpl_norm_host "$GH_HOST"
    _ghpl_dh="$_ghpl_nh"
  else
    case "$_ghpl_auth" in
      ""|*$'\n'*) _ghpl_dh=github.com ;;
      *) _ghpl_dh="$_ghpl_auth" ;;
    esac
  fi
}

_ghpl_auth_has() {
  case $'\n'"$_ghpl_auth"$'\n' in
    *$'\n'"$1"$'\n'*) return 0 ;;
  esac
  return 1
}

# Sets _ghpl_nh to host "$1" in lower case, without a port, with the
# github.com aliases folded in.
_ghpl_norm_host() {
  _ghpl_nh="${1%%:*}"
  case "$_ghpl_nh" in
    *[A-Z]*) _ghpl_nh="$(_ghpl_lower "$_ghpl_nh")" ;;
  esac
  case "$_ghpl_nh" in
    www.github.com|api.github.com|gist.github.com|ssh.github.com) _ghpl_nh=github.com ;;
  esac
}

# Sets _ghpl_nh for an ssh host. An alias (for example github.com-work)
# resolves to its real host. Known gh hosts skip the ssh lookup.
_ghpl_ssh_host() {
  local real=""
  _ghpl_norm_host "$1"
  if [ "$_ghpl_nh" = github.com ] || _ghpl_auth_has "$_ghpl_nh"; then
    return 0
  fi
  real="$(ssh -G "$1" 2>/dev/null </dev/null | awk '$1 == "hostname" { print $2; exit }' || true)"
  [ -z "$real" ] || _ghpl_norm_host "$real"
}

# Splits a repo reference into _ghpl_rh (host, empty when the reference
# names none) and _ghpl_rs (OWNER/REPO). Accepts OWNER/REPO,
# HOST/OWNER/REPO, URLs, git@HOST:OWNER/REPO, and ssh://git@HOST/OWNER/REPO.
_ghpl_parse_ref() {
  local ref="$1" path="" h="" owner rest repo
  _ghpl_rh=""
  _ghpl_rs=""
  case "$ref" in
    git@*:*)
      h="${ref#git@}"; h="${h%%:*}"; path="${ref#*:}"
      _ghpl_ssh_host "$h"; h="$_ghpl_nh"
      ;;
    ssh://*)
      path="${ref#ssh://}"; h="${path%%/*}"; h="${h#*@}"; h="${h%%:*}"; path="${path#*/}"
      _ghpl_ssh_host "$h"; h="$_ghpl_nh"
      ;;
    http://*|https://*|git://*)
      path="${ref#*://}"; h="${path%%/*}"; h="${h#*@}"; path="${path#*/}"
      ;;
    */*/*) h="${ref%%/*}"; path="${ref#*/}" ;;
    */*) path="$ref" ;;
    *) return 0 ;;
  esac
  if [ -n "$h" ]; then
    _ghpl_norm_host "$h"
    _ghpl_rh="$_ghpl_nh"
  fi
  owner="${path%%/*}"
  rest="${path#*/}"
  [ "$rest" != "$path" ] || return 0
  repo="${rest%%/*}"
  repo="${repo%.git}"
  if [ -n "$owner" ] && [ -n "$repo" ]; then _ghpl_rs="$owner/$repo"; fi
  return 0
}

_ghpl_add_target() {
  _ghpl_th+=("$1")
  _ghpl_ts+=("$2")
}

# Base-repo candidates from the checkout, in gh's order: a remote marked
# gh-resolved wins; else upstream, github, origin, then the rest. Like gh,
# only remotes on hosts gh can use count, when any remote is on one.
_ghpl_cwd_targets() {
  local remotes resolved name url idx kept=0
  local names=() urls=() ordered=() hosts=() slugs=()
  # `git remote -v` prints URLs after insteadOf rewrites, like gh sees them.
  remotes="$(git remote -v 2>/dev/null || true)"
  [ -n "$remotes" ] || return 0
  while IFS=$'\t' read -r name url; do
    case "$url" in
      *" (fetch)") names+=("$name"); urls+=("${url% (fetch)}") ;;
    esac
  done <<< "$remotes"
  [ "${#names[@]}" -gt 0 ] || return 0
  resolved="$(git config --get-regexp '^remote\..*\.gh-resolved$' 2>/dev/null | head -n 1 || true)"
  if [ -n "$resolved" ]; then
    name="${resolved%% *}"; name="${name#remote.}"; name="${name%.gh-resolved}"
    resolved="${resolved#* }"
    for idx in "${!names[@]}"; do
      [ "${names[$idx]}" = "$name" ] || continue
      _ghpl_parse_ref "${urls[$idx]}"
      # Older gh stored OWNER/REPO here instead of "base".
      case "$resolved" in */*) _ghpl_rs="$resolved" ;; esac
      _ghpl_add_target "${_ghpl_rh:-$_ghpl_dh}" "$_ghpl_rs"
      return 0
    done
  fi
  for name in upstream github origin; do
    for idx in "${!names[@]}"; do
      [ "${names[$idx]}" != "$name" ] || ordered+=("$idx")
    done
  done
  for idx in "${!names[@]}"; do
    case "${names[$idx]}" in upstream|github|origin) ;; *) ordered+=("$idx") ;; esac
  done
  for idx in "${ordered[@]}"; do
    _ghpl_parse_ref "${urls[$idx]}"
    [ -n "$_ghpl_rh" ] || continue
    hosts+=("$_ghpl_rh")
    slugs+=("$_ghpl_rs")
  done
  [ "${#hosts[@]}" -gt 0 ] || return 0
  for idx in "${!hosts[@]}"; do
    if _ghpl_auth_has "${hosts[$idx]}" || [ "${hosts[$idx]}" = "$_ghpl_dh" ]; then
      _ghpl_add_target "${hosts[$idx]}" "${slugs[$idx]}"
      kept=1
    fi
  done
  if [ "$kept" = 0 ]; then
    for idx in "${!hosts[@]}"; do _ghpl_add_target "${hosts[$idx]}" "${slugs[$idx]}"; done
  fi
  return 0
}

# ── Argv parsing (no I/O) ────────────────────────────────────────────

# Sets _ghpl_k to the kind of flag "$1" for the current command:
# bool, skip, repo, hostname, method, input, field-raw, field-typed,
# gistfile, public, private, text:<label>, file:<label>, asset:<label>.
# Labels are fixed strings, never user text.
_ghpl_flag_kind() {
  local f="$1"
  _ghpl_k=bool
  if [ "$_ghpl_cmd" = api ]; then
    case "$f" in
      -X|--method) _ghpl_k=method ;;
      -f|--raw-field) _ghpl_k=field-raw ;;
      -F|--field) _ghpl_k=field-typed ;;
      --input) _ghpl_k=input ;;
      --hostname) _ghpl_k=hostname ;;
      -H|--header|-q|--jq|-t|--template|-p|--preview|--cache) _ghpl_k=skip ;;
    esac
    return 0
  fi
  case "$f" in
    -R|--repo) _ghpl_k=repo; return 0 ;;
  esac
  case "$_ghpl_cmd $_ghpl_sub" in
    gist\ *)
      case "$f" in
        -d|--desc) _ghpl_k="text:description" ;;
        -f|--filename|-r|--remove) _ghpl_k="text:gist file name" ;;
        -a|--add) _ghpl_k=gistfile ;;
      esac
      ;;
    repo\ *)
      case "$f" in
        -d|--description) _ghpl_k="text:description" ;;
        -h|--homepage) _ghpl_k="text:homepage" ;;
        --add-topic|--remove-topic) _ghpl_k="text:topic" ;;
        -s|--source) _ghpl_k=skip ;;
        -g|--gitignore|-l|--license|-r|--remote|-t|--team|-p|--template|--default-branch|--squash-merge-commit-message|--visibility)
          _ghpl_k="text:repo setting" ;;
        --public) _ghpl_k=public ;;
        --private|--internal) _ghpl_k=private ;;
      esac
      ;;
    label\ *)
      case "$f" in
        -c|--color) _ghpl_k="text:color" ;;
        -d|--description) _ghpl_k="text:description" ;;
        -n|--name) _ghpl_k="text:label name" ;;
      esac
      ;;
    release\ *)
      case "$f" in
        -t|--title) _ghpl_k="text:title" ;;
        -n|--notes) _ghpl_k="text:notes" ;;
        -F|--notes-file) _ghpl_k="file:notes" ;;
        --discussion-category|--notes-start-tag|--target|--tag) _ghpl_k="text:release setting" ;;
      esac
      ;;
    "pr merge")
      case "$f" in
        -t|--subject) _ghpl_k="text:subject" ;;
        -b|--body) _ghpl_k="text:body" ;;
        -F|--body-file) _ghpl_k="file:body" ;;
        -A|--author-email) _ghpl_k="text:author email" ;;
        --match-head-commit) _ghpl_k=skip ;;
      esac
      ;;
    "pr review")
      case "$f" in
        -b|--body) _ghpl_k="text:body" ;;
        -F|--body-file) _ghpl_k="file:body" ;;
      esac
      ;;
    pr\ *|issue\ *)
      case "$f" in
        -t|--title) _ghpl_k="text:title" ;;
        -b|--body) _ghpl_k="text:body" ;;
        -F|--body-file) _ghpl_k="file:body" ;;
        -c|--comment) _ghpl_k="text:comment" ;;
        --attach) _ghpl_k="asset:attachment" ;;
        --recover) _ghpl_k=skip ;;
        -T|--template|-a|--assignee|-B|--base|-H|--head|-l|--label|-m|--milestone|-p|--project|-r|--reviewer|--reason|--type|--parent|--blocked-by|--blocking|--duplicate-of|--add-assignee|--add-label|--add-project|--add-reviewer|--add-blocked-by|--add-blocking|--add-sub-issue|--remove-assignee|--remove-label|--remove-project|--remove-reviewer|--remove-blocked-by|--remove-blocking|--remove-sub-issue)
          _ghpl_k="text:metadata" ;;
      esac
      ;;
  esac
  return 0
}

_ghpl_item() {
  _ghpl_ik+=("$1")
  _ghpl_il+=("$2")
  _ghpl_iv+=("$3")
}

# Records flag "$1" with value "$2" by its kind in _ghpl_k.
_ghpl_take() {
  local val="$2"
  case "$_ghpl_k" in
    repo) _ghpl_repo_flag="$val" ;;
    hostname) _ghpl_hostname="$val" ;;
    method) _ghpl_method="$val" ;;
    skip) ;;
    input) _ghpl_item input "input" "$val" ;;
    field-raw|field-typed)
      _ghpl_item "$_ghpl_k" "" "$val"
      # A repo created through the API is private only when asked.
      case "$val" in
        private=[Tt][Rr][Uu][Ee]|visibility=[Pp][Rr][Ii][Vv][Aa][Tt][Ee]|visibility=[Ii][Nn][Tt][Ee][Rr][Nn][Aa][Ll])
          _ghpl_newrepo_vis=private ;;
      esac
      ;;
    gistfile) _ghpl_item gistfile "" "$val" ;;
    text:*) _ghpl_item text "${_ghpl_k#text:}" "$val" ;;
    file:*) _ghpl_item file "${_ghpl_k#file:}" "$val" ;;
    asset:*) _ghpl_item asset "${_ghpl_k#asset:}" "$val" ;;
  esac
  return 0
}

_ghpl_positional() {
  local arg="$1"
  _ghpl_npos=$((_ghpl_npos + 1))
  case "$_ghpl_cmd" in
    api)
      if [ "$_ghpl_npos" = 1 ]; then
        _ghpl_endpoint="$arg"
        _ghpl_item text "endpoint" "$arg"
      else
        _ghpl_item text "argument" "$arg"
      fi
      ;;
    pr|issue)
      case "$arg" in
        http://*/*/*/pull/*|https://*/*/*/pull/*|http://*/*/*/issues/*|https://*/*/*/issues/*)
          [ -n "$_ghpl_url_ref" ] || _ghpl_url_ref="$arg" ;;
      esac
      _ghpl_item text "argument" "$arg"
      ;;
    release)
      if [ "$_ghpl_npos" = 1 ]; then
        _ghpl_item text "tag" "$arg"
      else
        _ghpl_item asset "asset name" "$arg"
      fi
      ;;
    gist)
      if [ "$_ghpl_sub" = edit ] && [ "$_ghpl_npos" = 1 ]; then
        case "$arg" in http://*|https://*) _ghpl_url_ref="$arg" ;; esac
      else
        _ghpl_gist_pos=$((_ghpl_gist_pos + 1))
        _ghpl_item gistfile "" "$arg"
      fi
      ;;
    repo)
      [ "$_ghpl_npos" != 1 ] || _ghpl_pos_ref="$arg"
      [ "$_ghpl_sub" != create ] || _ghpl_item text "repo name" "$arg"
      ;;
    label)
      if [ "$_ghpl_npos" = 1 ]; then
        _ghpl_item text "label name" "$arg"
      else
        _ghpl_item text "argument" "$arg"
      fi
      ;;
    *) _ghpl_item text "argument" "$arg" ;;
  esac
  return 0
}

_ghpl_parse() {
  local args=("$@") n="$#" i=1 arg flag val rest c end_opts=0
  _ghpl_cmd="${1:-}"
  _ghpl_sub=""
  _ghpl_ik=(); _ghpl_il=(); _ghpl_iv=()
  _ghpl_repo_flag=""; _ghpl_hostname=""; _ghpl_method=""; _ghpl_endpoint=""
  _ghpl_url_ref=""; _ghpl_pos_ref=""; _ghpl_newrepo_vis=""
  _ghpl_npos=0; _ghpl_gist_pos=0
  [ "$_ghpl_cmd" != api ] || _ghpl_sub=api
  while [ "$i" -lt "$n" ]; do
    arg="${args[$i]}"
    i=$((i + 1))
    if [ "$end_opts" = 1 ] || [ "$arg" = "-" ] || [ "${arg#-}" = "$arg" ]; then
      if [ -z "$_ghpl_sub" ]; then
        _ghpl_sub="$arg"
        [ "$_ghpl_sub" != new ] || _ghpl_sub=create
      else
        _ghpl_positional "$arg"
      fi
      continue
    fi
    case "$arg" in
      --) end_opts=1 ;;
      --*=*)
        flag="${arg%%=*}"
        val="${arg#*=}"
        _ghpl_flag_kind "$flag"
        case "$_ghpl_k" in
          public) [ "$val" = false ] || _ghpl_newrepo_vis=public ;;
          private) [ "$val" = false ] || _ghpl_newrepo_vis=private ;;
          bool) ;;
          *) _ghpl_take "$flag" "$val" ;;
        esac
        ;;
      --*)
        _ghpl_flag_kind "$arg"
        case "$_ghpl_k" in
          public) _ghpl_newrepo_vis=public ;;
          private) _ghpl_newrepo_vis=private ;;
          bool) ;;
          *)
            val="${args[$i]:-}"
            i=$((i + 1))
            _ghpl_take "$arg" "$val"
            ;;
        esac
        ;;
      *)
        # A short-flag cluster: the first flag that takes a value consumes
        # the rest of the cluster, or the next argument.
        rest="${arg#-}"
        while [ -n "$rest" ]; do
          c="${rest:0:1}"
          rest="${rest:1}"
          _ghpl_flag_kind "-$c"
          [ "$_ghpl_k" != bool ] || continue
          if [ -n "$rest" ]; then
            val="${rest#=}"
          else
            val="${args[$i]:-}"
            i=$((i + 1))
          fi
          _ghpl_take "-$c" "$val"
          break
        done
        ;;
    esac
  done
  return 0
}

# ── Target ───────────────────────────────────────────────────────────

# Fills _ghpl_th/_ghpl_ts with the write targets and sets _ghpl_kind:
# repo (check visibility), public (gists, graphql, no repo), or newrepo.
_ghpl_resolve_targets() {
  local h ep ref idx rest
  _ghpl_th=(); _ghpl_ts=(); _ghpl_kind=repo
  case "$_ghpl_cmd" in
    api)
      h="$_ghpl_dh"
      ep="$_ghpl_endpoint"
      case "$ep" in
        http://*|https://*)
          ep="${ep#*://}"; h="${ep%%/*}"; ep="${ep#*/}"
          case "$ep" in api/v3/*) ep="${ep#api/v3/}" ;; esac
          ;;
      esac
      [ -z "$_ghpl_hostname" ] || h="$_ghpl_hostname"
      _ghpl_norm_host "$h"
      h="$_ghpl_nh"
      ep="${ep#/}"
      ep="${ep%%\?*}"
      case "$ep" in
        repos/*/*)
          ref="${ep#repos/}"
          case "$ref" in
            *"{owner}"*|*"{repo}"*|:owner/*|*/:repo*)
              if [ -n "${GH_REPO:-}" ]; then
                _ghpl_parse_ref "$GH_REPO"
                _ghpl_add_target "$h" "$_ghpl_rs"
              else
                _ghpl_cwd_targets
                for idx in "${!_ghpl_th[@]}"; do _ghpl_th[$idx]="$h"; done
                [ "${#_ghpl_th[@]}" -gt 0 ] || _ghpl_add_target "$h" ""
              fi
              ;;
            *)
              rest="${ref#*/}"
              _ghpl_add_target "$h" "${ref%%/*}/${rest%%/*}"
              ;;
          esac
          ;;
        user/repos|orgs/*/repos)
          _ghpl_kind=newrepo
          [ -n "$_ghpl_newrepo_vis" ] || _ghpl_newrepo_vis=public
          _ghpl_add_target "$h" ""
          ;;
        *) _ghpl_kind=public; _ghpl_add_target "$h" "" ;;
      esac
      ;;
    gist)
      _ghpl_kind=public
      h="$_ghpl_dh"
      if [ -n "$_ghpl_url_ref" ]; then
        h="${_ghpl_url_ref#*://}"
        h="${h%%/*}"
      fi
      _ghpl_norm_host "$h"
      _ghpl_add_target "$_ghpl_nh" ""
      ;;
    repo)
      if [ "$_ghpl_sub" = create ]; then
        _ghpl_kind=newrepo
        _ghpl_parse_ref "$_ghpl_pos_ref"
        _ghpl_add_target "${_ghpl_rh:-$_ghpl_dh}" "$_ghpl_rs"
      else
        ref="${_ghpl_pos_ref:-${GH_REPO:-}}"
        if [ -n "$ref" ]; then
          _ghpl_parse_ref "$ref"
          _ghpl_add_target "${_ghpl_rh:-$_ghpl_dh}" "$_ghpl_rs"
        else
          _ghpl_cwd_targets
        fi
      fi
      ;;
    *)
      ref="${_ghpl_url_ref:-${_ghpl_repo_flag:-${GH_REPO:-}}}"
      if [ -n "$ref" ]; then
        _ghpl_parse_ref "$ref"
        _ghpl_add_target "${_ghpl_rh:-$_ghpl_dh}" "$_ghpl_rs"
      else
        _ghpl_cwd_targets
      fi
      ;;
  esac
  [ "${#_ghpl_th[@]}" -gt 0 ] || _ghpl_add_target "$_ghpl_dh" ""
  return 0
}

# True when any target is on github.com. Drops the other targets.
_ghpl_keep_github_targets() {
  local idx hs=() ss=()
  for idx in "${!_ghpl_th[@]}"; do
    if [ "${_ghpl_th[$idx]}" = github.com ]; then
      hs+=("github.com")
      ss+=("${_ghpl_ts[$idx]}")
    fi
  done
  [ "${#hs[@]}" -gt 0 ] || return 1
  _ghpl_th=("${hs[@]}")
  _ghpl_ts=("${ss[@]}")
  return 0
}

# Sets _ghpl_target (for the message) and _ghpl_unconfirmed. Returns 1
# when every github.com target is private, so the write may go through.
_ghpl_confirm_public() {
  local slug visibility
  _ghpl_unconfirmed=0
  case "$_ghpl_kind" in
    public)
      _ghpl_target="github.com"
      return 0
      ;;
    newrepo)
      slug="${_ghpl_ts[0]}"
      _ghpl_target="github.com${slug:+/$slug}"
      case "$_ghpl_newrepo_vis" in
        private) return 1 ;;
        public) return 0 ;;
      esac
      _ghpl_unconfirmed=1
      return 0
      ;;
  esac
  for slug in "${_ghpl_ts[@]}"; do
    _ghpl_target="github.com${slug:+/$slug}"
    if [ -z "$slug" ]; then
      _ghpl_unconfirmed=1
      return 0
    fi
    if grep -qixF -- "github.com/$slug" "$_ghpl_dir/../config/public-push-remotes.txt" 2>/dev/null; then
      return 0
    fi
    visibility="$("$REAL_GH" api --hostname github.com "repos/$slug" --jq .visibility </dev/null 2>/dev/null || true)"
    case "$visibility" in
      private|internal) continue ;;
      public) return 0 ;;
    esac
    _ghpl_unconfirmed=1
    return 0
  done
  return 1
}

# ── Text collection (reads files and stdin) ──────────────────────────

_ghpl_new_piece() {
  printf -v _ghpl_pf '%s/p%04d' "$_ghpl_tmp" "${#_ghpl_pl[@]}"
  _ghpl_pl+=("$1")
  : > "$_ghpl_pf"
}

_ghpl_text() {
  _ghpl_new_piece "$1"
  printf '%s\n' "$2" > "$_ghpl_pf"
}

_ghpl_buffer_stdin() {
  [ -z "$_ghpl_stdin" ] || return 0
  _ghpl_stdin="$_ghpl_tmp/stdin"
  cat > "$_ghpl_stdin" || true
  exec 0<"$_ghpl_stdin"
}

# Adds the contents of file "$2" ("-" is stdin) under label "$1".
_ghpl_file() {
  local path="$2"
  if [ "$path" = "-" ]; then
    _ghpl_buffer_stdin
    path="$_ghpl_stdin"
  fi
  [ -f "$path" ] || return 0
  _ghpl_new_piece "$1"
  cat "$path" > "$_ghpl_pf" 2>/dev/null || true
}

# A release asset or attachment: "<path>#<label>". The file name and the
# label are published, not the contents.
_ghpl_asset() {
  local val="$2" path alt=""
  path="${val%%#*}"
  [ "$path" = "$val" ] || alt="${val#*#}"
  if [ -e "$path" ]; then
    _ghpl_text "$1" "${path##*/}"$'\n'"$alt"
  else
    _ghpl_text "$1" "$val"
  fi
}

_ghpl_gistfile() {
  local val="$1" f matched=0
  if [ "$val" = "-" ]; then
    _ghpl_file "gist file" -
    return 0
  fi
  if [ -f "$val" ]; then
    _ghpl_file "gist file" "$val"
    _ghpl_text "gist file name" "${val##*/}"
    return 0
  fi
  # gh expands glob patterns itself.
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    matched=1
    _ghpl_file "gist file" "$f"
    _ghpl_text "gist file name" "${f##*/}"
  done < <(compgen -G "$val" 2>/dev/null || true)
  [ "$matched" = 1 ] || _ghpl_text "gist file name" "$val"
}

_ghpl_field() {
  local typed="$1" kv="$2" key val label before src
  key="${kv%%=*}"
  val=""
  [ "$key" = "$kv" ] || val="${kv#*=}"
  key="${key%%\[*}"
  label="field"
  case "$key" in
    body|title|message|description|name|note|query|content|homepage|subject|tag_name|commit_message|commit_title|text|summary|path|branch)
      label="field $key" ;;
  esac
  before="${#_ghpl_pl[@]}"
  if [ "$typed" = 1 ] && [ "${val#@}" != "$val" ]; then
    _ghpl_file "$label" "${val#@}"
  else
    _ghpl_text "$label" "$kv"
  fi
  # The contents API takes base64. Scan the decoded file too.
  if [ "$key" = content ] && [ "${#_ghpl_pl[@]}" -gt "$before" ]; then
    src="$_ghpl_pf"
    _ghpl_new_piece "$label (decoded)"
    sed 's/^content=//' "$src" | base64 --decode > "$_ghpl_pf" 2>/dev/null || true
  fi
}

_ghpl_input() {
  local path="$1"
  if [ "$path" = "-" ]; then
    _ghpl_buffer_stdin
    path="$_ghpl_stdin"
  fi
  [ -f "$path" ] || return 0
  _ghpl_new_piece "input"
  cat "$path" > "$_ghpl_pf" 2>/dev/null || true
  command -v jq >/dev/null 2>&1 || return 0
  # Decoded strings catch JSON escapes such as \/ and /, and
  # decoded `content` catches base64 file bodies.
  _ghpl_new_piece "input"
  jq -r '.. | strings' < "$path" > "$_ghpl_pf" 2>/dev/null || true
  _ghpl_new_piece "input (decoded content)"
  { jq -r '.. | objects | .content? | strings' < "$path" 2>/dev/null || true; } \
    | base64 --decode > "$_ghpl_pf" 2>/dev/null || true
}

_ghpl_collect() {
  local idx kind label val
  _ghpl_pl=()
  for idx in "${!_ghpl_ik[@]}"; do
    kind="${_ghpl_ik[$idx]}"
    label="${_ghpl_il[$idx]}"
    val="${_ghpl_iv[$idx]}"
    case "$kind" in
      text) _ghpl_text "$label" "$val" ;;
      file) _ghpl_file "$label" "$val" ;;
      asset) _ghpl_asset "$label" "$val" ;;
      gistfile) _ghpl_gistfile "$val" ;;
      field-raw) _ghpl_field 0 "$val" ;;
      field-typed) _ghpl_field 1 "$val" ;;
      input) _ghpl_input "$val" ;;
    esac
  done
  # gh gist create with no file operand reads stdin.
  if [ "$_ghpl_cmd $_ghpl_sub" = "gist create" ] && [ "$_ghpl_gist_pos" = 0 ] && [ ! -t 0 ]; then
    _ghpl_file "gist file" -
  fi
  return 0
}

# ── Matchers ─────────────────────────────────────────────────────────

# Generic markers that need no private pattern: lib/private-ref-markers.awk.

# Prints "<piece file><TAB><class>" for every private reference in the
# collected pieces. A few processes in all, not a few per piece.
_ghpl_scan() {
  local f pattern emails secret_args=()
  local email_re='[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]+'
  if [ -n "${OSS_READINESS_INTERNAL_PATTERN:-}" ]; then
    while IFS= read -r f; do
      printf '%s\tprivate-pattern match\n' "$f"
    done < <(grep -laiE -- "$OSS_READINESS_INTERNAL_PATTERN" "$_ghpl_tmp"/p* 2>/dev/null || true)
  fi
  if [ -n "${OSS_READINESS_PRIVATE_EMAIL_PATTERN:-}" ]; then
    while IFS= read -r f; do
      # No pipe into grep -q: under pipefail an early exit reads as a miss.
      emails="$(grep -aoE "$email_re" "$f" 2>/dev/null || true)"
      if grep -qE -- "$OSS_READINESS_PRIVATE_EMAIL_PATTERN" <<< "$emails"; then
        printf '%s\tprivate email\n' "$f"
      fi
    done < <(grep -laE "$email_re" "$_ghpl_tmp"/p* 2>/dev/null || true)
  fi
  awk -v home="${HOME:-}" -v me="${HOME##*/}" -v ent="${_ghpl_auth//$'\n'/ }" -f "$_ghpl_dir/private-ref-markers.awk" \
    "$_ghpl_tmp"/p* 2>/dev/null || true
  for pattern in ${OSS_READINESS_SECRET_PATTERNS[@]+"${OSS_READINESS_SECRET_PATTERNS[@]}"}; do
    secret_args+=(-e "$pattern")
  done
  if [ "${#secret_args[@]}" -gt 0 ]; then
    while IFS= read -r f; do
      printf '%s\tsecret\n' "$f"
    done < <(grep -laE "${secret_args[@]}" "$_ghpl_tmp"/p* 2>/dev/null || true)
  fi
  return 0
}

_ghpl_load_patterns() {
  local repo="${_ghpl_ts[0]:-}"
  repo="${repo##*/}"
  [ -f "$_ghpl_dir/oss-readiness.sh" ] || return 0
  # shellcheck source=lib/oss-readiness.sh
  . "$_ghpl_dir/oss-readiness.sh"
  { [ -n "$repo" ] && oss_readiness_load_private_env "$repo"; } >/dev/null 2>&1 ||
    oss_readiness_load_private_env dotfiles >/dev/null 2>&1 || true
}

# Prints the github.com login from gh's hosts.yml in lower case, or nothing.
_ghpl_github_login() {
  local hosts_file="${GH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/gh}/hosts.yml"
  awk '/^[^[:space:]#]/ { h = $0; sub(/:.*/, "", h); gsub(/["'"'"']/, "", h); inh = (tolower(h) == "github.com"); next }
    inh && /^[[:space:]]+user:/ { u = $0; sub(/^[[:space:]]+user:[[:space:]]*/, "", u); gsub(/["'"'"']/, "", u); print tolower(u); exit }' \
    "$hosts_file" 2>/dev/null || true
}

# Succeeds when the owner writes to one of their own public repos
# (config/public-push-remotes.txt), and sets _ghpl_target to it. A token
# with no known login counts as the owner.
_ghpl_owner_public_write() {
  local slug login
  declare -F oss_readiness_is_owner_public >/dev/null || return 1
  login="$(_ghpl_github_login)"
  if [ -n "$login" ] &&
     ! oss_readiness_owner_public_repos | cut -d/ -f2 | grep -qxF -- "$login"; then
    return 1
  fi
  for slug in "${_ghpl_ts[@]}"; do
    [ -n "$slug" ] || continue
    if oss_readiness_is_owner_public "github.com/$slug"; then
      _ghpl_target="github.com/$slug"
      return 0
    fi
  done
  return 1
}

_ghpl_cleanup() {
  [ -z "${_ghpl_tmp:-}" ] || rm -rf "$_ghpl_tmp"
  _ghpl_tmp=""
}

gh_public_leak_guard() {
  local hits f class idx line report=""
  [ "${DOTFILES_ALLOW_GH_PRIVATE_REFS:-}" != 1 ] || return 0
  _ghpl_load_hosts
  _ghpl_parse "$@"
  _ghpl_resolve_targets
  _ghpl_keep_github_targets || return 0

  _ghpl_stdin=""
  _ghpl_tmp="$(mktemp -d "${TMPDIR:-/tmp}/gh-leak.XXXXXX")"
  trap _ghpl_cleanup EXIT
  _ghpl_collect
  # A graphql call writes only through a mutation.
  if [ "${_ghpl_endpoint#/}" = graphql ] &&
     ! grep -qsE '(^|[^A-Za-z0-9_])mutation([^A-Za-z0-9_]|$)' "$_ghpl_tmp"/p*; then
    _ghpl_cleanup; trap - EXIT
    return 0
  fi
  _ghpl_load_patterns
  # The owner's own public repos need an armed pattern file. A missing or
  # outdated file blocks the write instead of skipping the pattern scan.
  if compgen -G "$_ghpl_tmp/p*" >/dev/null && _ghpl_owner_public_write &&
     ! _ghpl_env_problem="$(oss_readiness_check_private_env)"; then
    {
      echo "gh wrapper: blocked a write to public $_ghpl_target: $_ghpl_env_problem."
      echo "The pattern file is local-only and never goes through a repo. See SECURITY.md \"Private pattern file\"."
    } >&2
    _ghpl_cleanup
    exit 1
  fi
  hits="$(_ghpl_scan)"
  if [ -z "$hits" ] || ! _ghpl_confirm_public; then
    _ghpl_cleanup; trap - EXIT
    return 0
  fi
  # Report in field order, one line per field and class.
  while IFS=$'\t' read -r f class; do
    idx="${f##*/p}"
    line="  - ${_ghpl_pl[$((10#$idx))]}: $class"
    case $'\n'"$report" in
      *$'\n'"$line"$'\n'*) ;;
      *) report="$report$line"$'\n' ;;
    esac
  done < <(printf '%s\n' "$hits" | sort -t $'\t' -k1,1 -s)
  {
    echo "gh wrapper: blocked a write to public $_ghpl_target. The text has a private reference:"
    printf '%s' "$report"
    [ "$_ghpl_unconfirmed" = 0 ] || echo "  (could not confirm the target's visibility, so it counts as public)"
    echo "Replace each one with a generic placeholder: ~ for the home dir, github.example.com for a host, PROJ-123 for a ticket."
    echo "If a human checked the text and wants it public, rerun with DOTFILES_ALLOW_GH_PRIVATE_REFS=1."
  } >&2
  _ghpl_cleanup
  exit 1
}
