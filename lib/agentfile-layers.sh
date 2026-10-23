#!/usr/bin/env bash
# Optional Agentfile layers that this Mac merges after the base and overlay.
# Shared by .chezmoiscripts/run_after_agentbrew-sync.sh and the agentbrew
# doctor check, so both build the same merge list.
#
# agentfile_optional_layers <dotfiles_dir>
#   Prints one path per line, in merge order:
#   1. config/agentfile-owner-rules.yaml when owner_machine is true
#      (chezmoi data, or DOTFILES_OWNER_MACHINE).
#   2. This Mac's local Agentfile (agentfile_local_layer_path) when it
#      exists and agentfile_local_layer_problems finds no error. It is
#      untracked, so an extra MCP server on one Mac needs no change to the
#      shared Agentfile.yaml (issue #259). Each problem goes to stderr; an
#      error skips only this layer.
agentfile_optional_layers() {
  local dir="$1"
  local owner local_layer problems
  owner="${DOTFILES_OWNER_MACHINE:-$(chezmoi execute-template '{{ dig "owner_machine" true . }}' 2>/dev/null || echo true)}"
  if [ "$owner" = "true" ] && [ -f "$dir/config/agentfile-owner-rules.yaml" ]; then
    printf '%s\n' "$dir/config/agentfile-owner-rules.yaml"
  fi
  local_layer="$(agentfile_local_layer_path)"
  [ -f "$local_layer" ] || return 0
  problems="$(agentfile_local_layer_problems "$local_layer" | grep -v '^note: ' || true)"
  if grep -q '^error: ' <<< "$problems"; then
    printf '⚠ Skipping %s (the other layers still sync):\n' "$local_layer" >&2
    printf '%s\n' "$problems" | sed 's/^/    /' >&2
    return 0
  fi
  if [ -n "$problems" ]; then
    printf '⚠ %s:\n' "$local_layer" >&2
    printf '%s\n' "$problems" | sed 's/^/    /' >&2
  fi
  printf '%s\n' "$local_layer"
}

# Prints the path of this Mac's local Agentfile layer. lib/apply-state.sh
# hashes the same path, so `dotfiles apply --if-changed` sees an edit.
agentfile_local_layer_path() {
  printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/Agentfile.local.yaml"
}

# agentfile_local_layer_problems [<file>]: prints one problem per line,
# "error: …" (the layer is skipped) or "warning: …" (agentbrew ignores that
# key). Prints nothing when the file is fine or absent.
#
# hooks: is an error. agentbrew's merge lets a later layer's hook replace
# every earlier hook with the same event, matcher, and agents, so one local
# Bash hook would drop the shared block-dangerous-git.sh hook. A local layer
# must never remove a shared safety hook, so it may hold no hooks at all.
#
# The authority is agentbrew itself: the file is merged alone with
# `agentbrew agentfile merge` (AGENTFILE_AGENTBREW_CMD, default agentbrew).
# A file it cannot read, or whose merge result has hooks (also ones that
# arrive through a YAML merge key), is an error. mikefarah yq, when present,
# adds clearer messages and the list-key warnings. A check that cannot run
# (no temp file) is an error too, so the layer is skipped, never trusted.
# Without a merge-capable agentbrew it prints "note: checked with yq only";
# a note is not a problem.
agentfile_local_layer_problems() {
  local file="${1:-$(agentfile_local_layer_path)}"
  [ -f "$file" ] || return 0
  { _agentfile_local_agentbrew_check "$file"; _agentfile_local_yq_check "$file"; } | awk '!seen[$0]++'
}

# Merges the file alone with agentbrew.
_agentfile_local_agentbrew_check() {
  local file="$1" ab="${AGENTFILE_AGENTBREW_CMD:-agentbrew}" out err
  if ! _agentfile_can_merge "$ab"; then
    echo "note: checked with yq only (no agentbrew here can merge Agentfiles)"
    return 0
  fi
  if ! out="$(_agentfile_local_tmp)"; then
    echo "error: cannot check this file: no temp file in ${TMPDIR:-/tmp} or ${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
    return 0
  fi
  # shellcheck disable=SC2086
  if ! err="$($ab agentfile merge "$file" --output "$out" 2>&1)"; then
    echo "error: agentbrew cannot read it: $(_agentfile_error_line "$err")"
  elif grep -q '^hooks:' "$out"; then
    _agentfile_local_hooks_error
  fi
  rm -f "$out"
}

# Prints a new temp file: in TMPDIR, else in the user cache folder.
_agentfile_local_tmp() {
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles"
  mktemp "${TMPDIR:-/tmp}/dotfiles-local-agentfile.XXXXXX" 2>/dev/null && return 0
  mkdir -p "$cache" 2>/dev/null && mktemp "$cache/local-agentfile.XXXXXX" 2>/dev/null
}

# _agentfile_error_line <agentbrew output>: its first "Error:" line, without
# color codes (agentbrew may print a status line first).
_agentfile_error_line() {
  local plain
  plain="$(printf '%s\n' "$1" | sed $'s/\x1b\\[[0-9;]*m//g')"
  grep -m1 -E '^[[:space:]]*Error:' <<< "$plain" || tail -1 <<< "$plain"
}

_agentfile_local_hooks_error() {
  echo "error: hooks: is not allowed here. A hook in this file would replace every shared hook with the same event and matcher (block-dangerous-git.sh and others). Remove hooks: from this file."
}

# Clearer messages and warnings with mikefarah yq; silent without it.
_agentfile_local_yq_check() {
  local file="$1" err top key kind flat
  _agentfile_mikefarah_yq || return 0
  if ! err="$(yq -o=json '.' "$file" 2>&1 >/dev/null)"; then
    echo "error: not valid YAML: $(printf '%s\n' "$err" | grep -v 'level=WARN' | head -1)"
    return 0
  fi
  top="$(yq 'type' "$file" 2>/dev/null)"
  if [ "$(printf '%s\n' "$top" | wc -l | tr -d ' ')" -gt 1 ]; then
    echo "error: the file holds more than one YAML document (a --- line); keep one"
    return 0
  fi
  case "$top" in
    '!!map') ;;
    '!!null' | '') return 0 ;;
    *) echo "error: the top level must be keys such as mcp: and skills:, not a ${top#!!}"; return 0 ;;
  esac
  # explode() resolves YAML anchors and merge keys, as agentbrew does. Do it
  # once, keep the result in memory, and ask that copy.
  # yq may print a level=WARN line on stderr; keep stderr out of the copy.
  if ! flat="$(yq -o=json 'explode(.)' "$file" 2>/dev/null)"; then
    echo "error: cannot check this file: $(yq -o=json 'explode(.)' "$file" 2>&1 >/dev/null | grep -v 'level=WARN' | head -1)"
    return 0
  fi
  if [ "$(_agentfile_flat_q 'has("hooks")')" = true ]; then
    _agentfile_local_hooks_error
  fi
  for key in mcp skills sources commands agents excludeAgents memoryPacks; do
    kind="$(K="$key" _agentfile_flat_q '.[strenv(K)] | type')"
    case "$kind" in
      '!!seq' | '!!null' | '') ;;
      *) echo "warning: $key: must be a list (one \"- item\" per line), not a ${kind#!!}; agentbrew ignores it" ;;
    esac
  done
  kind="$(_agentfile_flat_q '.rules | type')"
  case "$kind" in
    '!!str' | '!!null' | '') ;;
    *) echo "warning: rules: must be text, not a ${kind#!!}; agentbrew ignores it" ;;
  esac
  _agentfile_flat_q 'keys | .[]' | while IFS= read -r key; do
    case "$key" in
      mcp | skills | sources | commands | agents | rules | hooks | recommended | excludeAgents | \
        defaultModel | defaultEffort | modelOverrides | task_backend | repo | project | memory | memoryPacks) ;;
      *) echo "warning: $key: agentbrew's merge does not use this key; it is ignored" ;;
    esac
  done
}

# _agentfile_flat_q <expression>: runs a yq expression on $flat (the
# exploded JSON copy in _agentfile_local_yq_check).
_agentfile_flat_q() {
  printf '%s\n' "$flat" | yq -p=json "$1" 2>/dev/null
}

# agentfile_plugin_layers <base Agentfile>: reads "name<TAB>Agentfile" lines
# for company plugins (plugin_agentfile_pairs, lock order) on stdin and
# prints the Agentfiles to merge, one per line.
#
# A plugin may add to the shared layer, never take from it. agentbrew's
# merge lets a later layer replace an earlier hook (same event, matcher, and
# agents) or MCP server (same name), add agents to excludeAgents, which
# turns off all agentbrew sync for them, the shared hooks included, and
# turn on recommended, which installs the whole recommended set (undoing the
# trimmed shared list). So this asks agentbrew itself: it merges the earlier
# layers (the base, then each plugin kept so far) with and without the
# plugin. The plugin's Agentfile is skipped, and stderr names the plugin
# and what it would take, when the merge with it:
# - lacks an earlier hook entry (compared whole: command, if, async,
#   timeout, and every other field), or adds a hook that runs a shared
#   hook's command or prompt for the same event under any matcher or
#   agents list (a second copy, maybe weaker, that still runs);
# - lists an agent in excludeAgents that the earlier merge did not;
# - lacks an earlier MCP server entry (compared whole), that is, the plugin
#   re-defines a shared server under the same name;
# - sets recommended: true when the earlier merge did not;
# - adds a commands: or agents: folder with a *.md file whose name (any
#   letter case; for an agent also its front matter name:) an earlier
#   folder of that kind also has, or a name with non-ASCII letters. agentbrew
#   keeps one command and one agent file per name, and which copy wins
#   depends on the order the folders first reached its state (the later
#   command folder wins, the earlier agent folder wins), so the plugin's
#   copy can replace the shared one;
# - makes a local skill copy (SKILL.md, skill.md, or DESIGN.md, at any
#   depth, in any local sources: folder of the merge) match a skills: entry
#   that did not match before the plugin. agentbrew installs a skills: name
#   without a catalog entry (a built-in skill) by searching every source,
#   and a local source ranks before the built-in. A remote source cannot be
#   read before the sync, so this rule does not cover it.
# A plugin Agentfile agentbrew cannot read, or a check that cannot run,
# skips it too. Model fields (defaultModel, defaultEffort, modelOverrides)
# may change: an overlay sets them on purpose (docs/model-configuration.md).
#
# Without an agentbrew that can merge (AGENTFILE_AGENTBREW_CMD, default
# agentbrew), the sync syncs each Agentfile on its own, and agentbrew then
# sets the hooks to that file's list. There the rule is stricter and read
# from the files: a plugin Agentfile is skipped when it is not one map, uses
# a YAML merge key (yq reads those unlike agentbrew), has any hooks:, excludeAgents:, recommended: true, or an entry for an MCP
# server the base lists (or memory, when the base turns memory on) that is
# not written the same way. The command and agent name rule is the same,
# with the folders read from the base and the plugins kept so far.
# Without mikefarah yq nothing can be checked: every plugin Agentfile is
# skipped.
agentfile_plugin_layers() {
  local base="$1" ab="${AGENTFILE_AGENTBREW_CMD:-agentbrew}" name file before after err reasons
  local -a earlier=() kept=()
  [ -f "$base" ] && earlier=("$base")
  if ! _agentfile_mikefarah_yq; then
    while IFS=$'\t' read -r name file; do
      [ -z "$file" ] || printf '⚠ Skipping the Agentfile of plugin %s: cannot check it without mikefarah yq\n' "$name" >&2
    done
    return 0
  fi
  if ! _agentfile_can_merge "$ab"; then
    while IFS=$'\t' read -r name file; do
      [ -n "$file" ] || continue
      reasons="$(_agentfile_plugin_raw_reasons "$base" "$file" ${kept[@]+"${kept[@]}"})"
      if [ -n "$reasons" ]; then
        printf '⚠ Skipping the Agentfile of plugin %s (%s): without agentfile merge it would take from the shared layer:\n' "$name" "$file" >&2
        printf '%s\n' "$reasons" | sed 's/^/    /' >&2
        continue
      fi
      printf '%s\n' "$file"
      kept+=("$file")
    done
    return 0
  fi
  if ! before="$(_agentfile_local_tmp)" || ! after="$(_agentfile_local_tmp)"; then
    rm -f "${before:-}"
    while IFS=$'\t' read -r name file; do
      [ -z "$file" ] || printf '⚠ Skipping the Agentfile of plugin %s: cannot check it (no temp file)\n' "$name" >&2
    done
    return 0
  fi
  # The merge of the earlier layers; after each kept plugin, its merge.
  : > "$before"
  if [ "${#earlier[@]}" -gt 0 ]; then
    # shellcheck disable=SC2086
    if ! err="$($ab agentfile merge "${earlier[@]}" --output "$before" 2>&1)"; then
      while IFS=$'\t' read -r name file; do
        [ -z "$file" ] || printf '⚠ Skipping the Agentfile of plugin %s: cannot check it: %s\n' "$name" "$(_agentfile_error_line "$err")" >&2
      done
      rm -f "$before" "$after"
      return 0
    fi
  fi
  while IFS=$'\t' read -r name file; do
    [ -n "$file" ] || continue
    # shellcheck disable=SC2086
    if ! err="$($ab agentfile merge ${earlier[@]+"${earlier[@]}"} "$file" --output "$after" 2>&1)"; then
      printf '⚠ Skipping the Agentfile of plugin %s (%s): agentbrew cannot read it: %s\n' \
        "$name" "$file" "$(_agentfile_error_line "$err")" >&2
      continue
    fi
    reasons="$(_agentfile_plugin_merge_reasons "$before" "$after")"
    if [ -n "$reasons" ]; then
      printf '⚠ Skipping the Agentfile of plugin %s (%s): it would take from the shared layer:\n' "$name" "$file" >&2
      printf '%s\n' "$reasons" | sed 's/^/    /' >&2
      continue
    fi
    printf '%s\n' "$file"
    earlier+=("$file")
    cp "$after" "$before"
  done
  rm -f "$before" "$after"
}

# _agentfile_plugin_merge_reasons <earlier merge> <merge with the plugin>:
# prints what the plugin would take from the shared layer, one item per
# line; nothing when it only adds.
_agentfile_plugin_merge_reasons() {
  local before="$1" after="$2" dropped added copies excluded servers kind
  dropped="$(LC_ALL=C comm -23 <(_agentfile_hook_entries "$before") <(_agentfile_hook_entries "$after"))"
  if [ -n "$dropped" ]; then
    echo "its hooks would replace these shared hooks (same event, matcher, and agents):"
    _agentfile_hook_labels "$dropped" | sed 's/^/  /'
  fi
  added="$(LC_ALL=C comm -13 <(_agentfile_hook_entries "$before") <(_agentfile_hook_entries "$after"))"
  if [ -n "$added" ]; then
    # Same event and command (or prompt), under any matcher or agents list:
    # a second copy that may be weaker (async, timeout) and still runs.
    copies="$(LC_ALL=C comm -12 <(_agentfile_hook_keys "$(_agentfile_hook_entries "$before")") \
      <(_agentfile_hook_keys "$added"))"
    if [ -n "$copies" ]; then
      echo "its hooks would add a second copy of these shared hook commands (same event; use your own hook command):"
      printf '%s\n' "$copies" | yq -p=json -r '.[0] + " " + .[1]' 2>/dev/null | grep -v '^---$' | sed 's/^/  /'
    fi
  fi
  excluded="$(LC_ALL=C comm -13 <(_agentfile_excluded "$before") <(_agentfile_excluded "$after"))"
  [ -z "$excluded" ] ||
    echo "its excludeAgents: turns off agentbrew sync, the shared hooks included, for: $(printf '%s\n' "$excluded" | paste -sd ' ' -)"
  servers="$(LC_ALL=C comm -23 <(_agentfile_mcp_entries "$before") <(_agentfile_mcp_entries "$after"))"
  [ -z "$servers" ] || echo "it replaces these shared MCP servers: $(_agentfile_mcp_labels "$servers")"
  if [ "$(yq '.recommended // false' "$after" 2>/dev/null)" = true ] &&
    [ "$(yq '.recommended // false' "$before" 2>/dev/null)" != true ]; then
    echo "its recommended: true installs the whole recommended set, undoing the trimmed shared list"
  fi
  # The plugin's folders and sources are the ones its merge adds.
  for kind in commands agents; do
    _agentfile_name_reason "$kind" "$(_agentfile_list "$kind" "$before")" \
      "$(_agentfile_added "$kind" "$before" "$after")"
  done
  _agentfile_skill_reason "$(_agentfile_list skills "$before")" \
    "$(_agentfile_list sources "$before" | _agentfile_local_sources)" \
    "$(_agentfile_list skills "$after")" \
    "$(_agentfile_list sources "$after" | _agentfile_local_sources)" "$ab" \
    "$(_agentfile_added sources "$before" "$after" | _agentfile_local_sources)"
}

# _agentfile_plugin_raw_reasons <base Agentfile> <plugin Agentfile>
# [<earlier plugin Agentfile>...]: the same rule without agentbrew's merge,
# read from the files (anchors and merge keys resolved).
_agentfile_plugin_raw_reasons() {
  local base="$1" file="$2" name shared kind f requested sources
  shift 2
  if [ "$(yq 'type' "$file" 2>/dev/null | head -2 | paste -sd ' ' -)" != '!!map' ]; then
    [ ! -s "$file" ] || [ "$(yq 'type' "$file" 2>/dev/null)" = '!!null' ] ||
      echo "it is not one map of keys (a list, a second YAML document, or not YAML), so it cannot be checked"
    return 0
  fi
  # yq resolves a YAML merge key (<<: *anchor) unlike agentbrew (js-yaml
  # keeps an explicit key; yq lets a later merge key override it), so a file
  # with one cannot be read the same way here.
  if [ "$(yq '[.. | key | select(. == "<<")] | length' "$file" 2>/dev/null)" != 0 ]; then
    echo "it uses a YAML merge key (<<), which yq reads unlike agentbrew, so it cannot be checked without agentfile merge"
    return 0
  fi
  [ "$(yq 'explode(.) | has("hooks")' "$file" 2>/dev/null)" = false ] ||
    echo "it has hooks:, and a separate sync would set the hooks to that list, dropping every shared hook"
  [ "$(yq 'explode(.) | (.excludeAgents // []) | length' "$file" 2>/dev/null)" = 0 ] ||
    echo "its excludeAgents: turns off agentbrew sync, the shared hooks included"
  # -o=json reads True and TRUE as true, as agentbrew does.
  [ "$(yq -o=json 'explode(.) | .recommended // false' "$file" 2>/dev/null)" != true ] ||
    echo "its recommended: true installs the whole recommended set, undoing the trimmed shared list"
  for kind in commands agents; do
    # agentbrew turns any entry into text (String()); only plain paths can
    # be followed here.
    [ "$(K="$kind" yq 'explode(.) | [(.[strenv(K)] // []) | select(type == "!!seq") | .[] |
      select(type != "!!str")] | length' "$file" 2>/dev/null)" = 0 ] ||
      echo "its $kind: list has an entry that is not a plain path, so it cannot be checked without agentfile merge"
    shared=""
    for f in "$base" "$@"; do
      [ -f "$f" ] && shared+="$(_agentfile_file_dirs "$kind" "$f")"$'\n'
    done
    _agentfile_name_reason "$kind" "$shared" "$(_agentfile_file_dirs "$kind" "$file")"
  done
  requested="" sources=""
  for f in "$base" "$@"; do
    [ -f "$f" ] || continue
    requested+="$(_agentfile_file_skills "$f")"$'\n'
    sources+="$(_agentfile_file_sources "$f")"$'\n'
  done
  _agentfile_skill_reason "$requested" "$sources" \
    "$requested$(_agentfile_file_skills "$file")" "$sources$(_agentfile_file_sources "$file")" "" \
    "$(LC_ALL=C comm -13 <(printf '%s\n' "$sources" | awk 'NF' | LC_ALL=C sort -u) \
      <(_agentfile_file_sources "$file" | LC_ALL=C sort -u))"
  [ -f "$base" ] || return 0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    shared="$(_agentfile_mcp_entries_named "$base" "$name")"
    if [ -z "$shared" ]; then
      if [ "$name" = memory ] &&
        [ "$(yq -o=json 'explode(.) | .memory.enabled // false' "$base" 2>/dev/null)" = true ]; then
        echo "it re-defines the shared memory server"
      fi
      continue
    fi
    # Every entry with that name must be one the base lists, written the
    # same way: agentbrew applies each entry in turn, and a {name: x} map is
    # a full definition, not the catalog server x.
    if [ -n "$(LC_ALL=C comm -13 <(printf '%s\n' "$shared") <(_agentfile_mcp_entries_named "$file" "$name"))" ]; then
      echo "it re-defines the shared MCP server $name"
    fi
  done < <(_agentfile_mcp_names "$file")
}

# _agentfile_name_reason <commands|agents> <shared folders> <plugin folders>
# (one per line): one line naming the plugin's files of that kind whose
# names (any letter case) a shared folder also has, and one line for names
# that cannot be compared; nothing when there are none. An agent's names are
# its file name and its front matter name: (Claude Code uses the latter).
_agentfile_name_reason() {
  local kind="$1" mine clashes odd
  mine="$(_agentfile_names "$kind" "$(_agentfile_other_dirs "$3" "$2")")"
  [ -n "$mine" ] || return 0
  # macOS folders also fold non-ASCII letters and their encodings, which a
  # plain lowercase compare misses.
  odd="$(LC_ALL=C grep '[^ -~]' <<< "$mine" || true)"
  [ -z "$odd" ] ||
    echo "its $kind have names with letters outside ASCII, so they cannot be checked against the shared names (use ASCII names): $(printf '%s\n' "$odd" | paste -sd ' ' -)"
  clashes="$(LC_ALL=C comm -12 <(_agentfile_names "$kind" "$2") <(printf '%s\n' "$mine"))"
  [ -z "$clashes" ] ||
    echo "its $kind have the names of shared $kind (agentbrew keeps one file per name, so the plugin's copy can replace the shared one): $(printf '%s\n' "$clashes" | paste -sd ' ' -)"
}

# _agentfile_other_dirs <plugin folders> <shared folders> (one per line):
# the plugin folders that are not a shared folder under another spelling
# (same file, test -ef), one per line. Such a folder holds the same files.
_agentfile_other_dirs() {
  local d s same
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    same=false
    while IFS= read -r s; do
      [ -n "$s" ] && [ "$d" -ef "$s" ] && same=true && break
    done <<< "$2"
    "$same" || printf '%s\n' "$d"
  done <<< "$1"
}

# _agentfile_names <commands|agents> <folders> (one per line): the names of
# the *.md entries at the top of each folder (the files agentbrew reads as
# commands or agents), without .md, plus each agent's front matter name:,
# lowercased (macOS folders ignore letter case), sorted.
_agentfile_names() {
  local kind="$1" d f n
  while IFS= read -r d; do
    [ -n "$d" ] && [ -d "$d" ] || continue
    for f in "$d"/*.md "$d"/.*.md; do
      [ -e "$f" ] || [ -L "$f" ] || continue
      n="${f##*/}"
      [ "$n" = .md ] || printf '%s\n' "${n%.md}"
      [ "$kind" != agents ] || [ ! -f "$f" ] || _agentfile_front_name "$f"
    done
  done <<< "$2" | LC_ALL=C tr '[:upper:]' '[:lower:]' | awk 'NF' | LC_ALL=C sort -u
}

# _agentfile_front_name <file>: every name: value in the file's front
# matter, found as agentbrew finds it (from a first --- line to the next
# "\n---"), each with quotes stripped both ways: agentbrew strips a quote
# at each end on its own, YAML strips a matching pair.
_agentfile_front_name() {
  # shellcheck disable=SC2016 # perl code, not shell
  # JavaScript's \s and trim() also cover these Unicode spaces.
  # Bad UTF-8 bytes become U+FFFD, as when Node reads the file.
  env -u PERL5LIB -u PERL5OPT perl -MEncode -0777 -ne '
    binmode STDOUT, ":encoding(UTF-8)";
    $_ = Encode::decode("UTF-8", $_);
    my $w = qr/[\s\x{A0}\x{1680}\x{2000}-\x{200A}\x{2028}\x{2029}\x{202F}\x{205F}\x{3000}\x{FEFF}]/;
    s/\r\n/\n/g;
    exit unless /\A---$w*\n([\s\S]*?)\n---/;
    for (split /\n/, $1) {
      next unless /^name:$w*(.+)$/;
      (my $v = $1) =~ s/^$w+|$w+$//g;
      (my $each = $v) =~ s/^["\x27]|["\x27]$//g;
      print "$each\n";
      print "$2\n" if $v =~ /^(["\x27])(.*)\1$/;
    }' "$1" 2>/dev/null
}

# _agentfile_skill_reason <earlier skills: names> <earlier local sources>
# <skills: names with the plugin> <local sources with the plugin> <agentbrew
# command> <local sources the plugin adds> (lists one per line): one line
# naming the skills that a skills: entry asks for and a local source holds
# with the plugin, but not before it (so a request in one plugin and a copy
# in another count too), or that a source the plugin adds holds. agentbrew
# installs a skills: name that has no catalog entry (a built-in skill) by
# searching every source it tracks, and a local source ranks before the
# built-in, so such a copy could replace the shared or built-in skill. A
# name only the plugin asks for counts when it is an agentbrew built-in
# (any name, when the built-ins cannot be found): agentbrew installs no
# other unknown name. Remote sources cannot be read before the sync.
_agentfile_skill_reason() {
  local earlier asked builtins catalog clashes
  earlier="$(_agentfile_lower "$1")"
  asked="$(LC_ALL=C comm -13 <(printf '%s\n' "$earlier") <(_agentfile_lower "$3"))"
  if [ -n "$asked" ] && builtins="$(_agentfile_builtin_skills "$5")"; then
    asked="$(LC_ALL=C comm -12 <(printf '%s\n' "$asked") <(printf '%s\n' "$builtins"))"
  fi
  # A catalog name installs from the catalog's own source, never by a search.
  if catalog="$(_agentfile_catalog_skills "$5")"; then
    earlier="$(LC_ALL=C comm -23 <(printf '%s\n' "$earlier") <(printf '%s\n' "$catalog") | awk 'NF')"
    asked="$(LC_ALL=C comm -23 <(printf '%s\n' "$asked") <(printf '%s\n' "$catalog") | awk 'NF')"
  fi
  [ -n "$earlier$asked" ] || return 0
  # New matches, plus any copy in a source the plugin adds: a second copy
  # makes agentbrew ask "from which source?", listing the plugin's.
  clashes="$( {
    LC_ALL=C comm -13 \
      <(LC_ALL=C comm -12 <(printf '%s\n' "$earlier") <(_agentfile_skill_names "$2")) \
      <(LC_ALL=C comm -12 <(printf '%s\n%s\n' "$earlier" "$asked" | awk 'NF' | LC_ALL=C sort -u) \
        <(_agentfile_skill_names "$4"))
    LC_ALL=C comm -12 <(printf '%s\n%s\n' "$earlier" "$asked" | awk 'NF' | LC_ALL=C sort -u) \
      <(_agentfile_skill_names "$6")
  } | LC_ALL=C sort -u)"
  [ -z "$clashes" ] ||
    echo "its sources: or skills: make a local skill copy match a skills: entry (agentbrew may install that copy instead of the shared or built-in skill): $(printf '%s\n' "$clashes" | paste -sd ' ' -)"
}

# _agentfile_lower <lines>: lowercased, without empty lines, sorted.
_agentfile_lower() {
  printf '%s\n' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | awk 'NF' | LC_ALL=C sort -u
}

# _agentfile_builtin_skills <agentbrew command>: agentbrew's built-in skill
# names (skill-plugins/dev), lowercased; fails when no agentbrew folder is
# found (AGENTBREW_DIR, the command's dist/cli.js or the agentbrew it runs
# from PATH, then the checkout).
_agentfile_builtin_skills() {
  local dir d
  dir="$(_agentfile_agentbrew_dir "$1")" || return 1
  for d in "$dir"/skill-plugins/dev/*/; do
    [ -d "$d" ] && basename "$d"
  done | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sort -u
}

# _agentfile_catalog_skills <agentbrew command>: the skill names in
# agentbrew's catalog (src/catalog.yaml), lowercased; fails when it is not
# found.
_agentfile_catalog_skills() {
  local dir
  dir="$(_agentfile_agentbrew_dir "$1")" && [ -f "$dir/src/catalog.yaml" ] || return 1
  yq -r '(.skills // [])[] | .name' "$dir/src/catalog.yaml" 2>/dev/null | LC_ALL=C tr '[:upper:]' '[:lower:]' | awk 'NF' | LC_ALL=C sort -u
}

# _agentfile_agentbrew_dir <agentbrew command>: agentbrew's folder (the one
# with skill-plugins/dev): AGENTBREW_DIR, the command's dist/cli.js or the
# agentbrew it runs from PATH, then the checkout; fails when none is found.
_agentfile_agentbrew_dir() {
  local dir="${AGENTBREW_DIR:-}" cmd="${1#node }" bin
  if [ -z "$dir" ]; then
    case "$cmd" in
      */dist/cli.js) dir="${cmd%/dist/cli.js}" ;;
      *)
        # An agentbrew on PATH: follow its symlinks to .../dist/cli.js.
        bin="$(command -v "$cmd" 2>/dev/null)" &&
          bin="$(env -u PERL5LIB -u PERL5OPT perl -MCwd=abs_path -e 'print abs_path(shift)' "$bin" 2>/dev/null)" &&
          case "$bin" in */dist/cli.js) dir="${bin%/dist/cli.js}" ;; esac
        ;;
    esac
  fi
  if [ -z "$dir" ] || [ ! -d "$dir/skill-plugins/dev" ]; then
    # shellcheck source=/dev/null
    source "${BASH_SOURCE[0]%/*}/agentbrew-locate.sh" 2>/dev/null && dir="$(agentbrew_locate 2>/dev/null)" || return 1
  fi
  [ -d "$dir/skill-plugins/dev" ] || return 1
  printf '%s\n' "$dir"
}

# _agentfile_skill_names <folders> (one per line): every name agentbrew can
# find a skill under in those folders, lowercased, sorted: for each
# SKILL.md, skill.md, or DESIGN.md (any letter case) down to 9 levels, its
# folder's name and its front matter names (a symlinked file counts). Like
# agentbrew's scan, it skips hidden folders, node_modules, and __pycache__,
# and follows no symlinked folder below the source.
_agentfile_skill_names() {
  local d f
  while IFS= read -r d; do
    [ -n "$d" ] && [ -d "$d" ] || continue
    find -H "$d" -mindepth 1 -maxdepth 9 \
      \( -type d \( -name '.*' -o -name node_modules -o -name __pycache__ \) -prune \) -o \
      \( \( -type f -o -type l \) \( -iname SKILL.md -o -iname DESIGN.md \) -print \) 2>/dev/null | while IFS= read -r f; do
      basename "$(dirname "$f")"
      _agentfile_front_name "$f"
    done
  done <<< "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]' | awk 'NF' | LC_ALL=C sort -u
}

# _agentfile_file_skills <Agentfile>: its skills: names (plain entries).
_agentfile_file_skills() {
  yq -r 'explode(.) | (.skills // []) | select(type == "!!seq") | .[] | select(type == "!!str")' "$1" 2>/dev/null
}

# _agentfile_list <key> <merged Agentfile>: the entries of that list key,
# one per line (agentbrew's merge writes folders as absolute paths).
_agentfile_list() {
  [ -s "$2" ] || return 0
  K="$1" yq -r '(.[strenv(K)] // [])[]' "$2" 2>/dev/null
}

# _agentfile_added <key> <earlier merge> <merge with the plugin>: the
# entries of that list key that only the second merge has.
_agentfile_added() {
  LC_ALL=C comm -13 <(_agentfile_list "$1" "$2" | LC_ALL=C sort -u) <(_agentfile_list "$1" "$3" | LC_ALL=C sort -u)
}

# _agentfile_local_sources: reads merged sources: entries on stdin and
# prints the local folders among them (agentbrew: a path that starts with /
# or ~; a leading ~ is HOME), as given: agentbrew hands them to the file
# system unchanged. Remote sources are left out.
_agentfile_local_sources() {
  local d
  while IFS= read -r d; do
    case "$d" in
      /*) printf '%s\n' "$d" ;;
      '~'*) printf '%s\n' "$HOME${d#\~}" ;;
    esac
  done
}

# _agentfile_file_dirs <commands|agents> <Agentfile>: its folders of that
# kind as agentbrew resolves them when it applies this file on its own: an
# absolute path as it is, anything else (also ~/x) joined to the file's
# folder on the text (path.join). Only plain string entries of a list.
_agentfile_file_dirs() {
  local d dir
  dir="$(cd "$(dirname "$2")" 2>/dev/null && pwd)" || return 0
  K="$1" yq -r 'explode(.) | (.[strenv(K)] // []) | select(type == "!!seq") | .[] | select(type == "!!str")' "$2" 2>/dev/null |
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      case "$d" in /*) printf '%s\n' "$d" ;; *) _agentfile_norm_path "$dir/$d" ;; esac
    done
}

# _agentfile_file_sources <Agentfile>: its local sources: folders as
# agentbrew resolves them: ./x and ../x joined to the file's folder on the
# text, a leading ~ as HOME, an absolute path as it is. Remote sources are
# left out.
_agentfile_file_sources() {
  local d dir
  dir="$(cd "$(dirname "$1")" 2>/dev/null && pwd)" || return 0
  yq -r 'explode(.) | (.sources // []) | select(type == "!!seq") | .[] | select(type == "!!str")' "$1" 2>/dev/null |
    while IFS= read -r d; do
      case "$d" in
        ./* | ../*) _agentfile_norm_path "$dir/$d" ;;
        /*) printf '%s\n' "$d" ;;
        '~'*) printf '%s\n' "$HOME${d#\~}" ;;
      esac
    done
}

# _agentfile_norm_path <absolute path>: the path without . and .. parts and
# repeated slashes, worked out on the text as Node's path.join does (a
# missing folder in the middle does not matter).
_agentfile_norm_path() {
  local part out="" IFS=/
  local -a parts=() kept=()
  read -r -a parts <<< "$1"
  for part in ${parts[@]+"${parts[@]}"}; do
    case "$part" in
      '' | .) ;;
      ..) [ "${#kept[@]}" -eq 0 ] || unset "kept[$((${#kept[@]} - 1))]" ;;
      *) kept+=("$part") ;;
    esac
  done
  for part in ${kept[@]+"${kept[@]}"}; do out="$out/$part"; done
  printf '%s\n' "${out:-/}"
}

# _agentfile_hook_entries <merged Agentfile>: each hook entry as one line of
# sorted-key JSON (matcher "*" when unset), sorted, for a whole-entry compare.
_agentfile_hook_entries() {
  [ -s "$1" ] || return 0
  yq -o=json -I=0 '(.hooks // [])[] | .matcher = (.matcher // "*") | sort_keys(..)' "$1" 2>/dev/null | LC_ALL=C sort -u
}

# _agentfile_hook_keys <hook entry lines>: one JSON line per hook,
# [event, command or prompt], sorted, for the second-copy compare.
_agentfile_hook_keys() {
  [ -n "$1" ] || return 0
  printf '%s\n' "$1" | yq -p=json -o=json -I=0 '[.event, (.command // .prompt // "")]' 2>/dev/null |
    grep -v '^---$' | LC_ALL=C sort -u
}

# _agentfile_hook_labels <hook entry lines>: "event matcher command|prompt".
_agentfile_hook_labels() {
  [ -n "$1" ] || return 0
  printf '%s\n' "$1" | yq -p=json -r '.event + " " + .matcher + " " + (.command // .prompt // "")' 2>/dev/null |
    grep -v '^---$'
}

# _agentfile_excluded <merged Agentfile>: its excludeAgents, one per line.
_agentfile_excluded() {
  [ -s "$1" ] || return 0
  yq -r '(.excludeAgents // [])[]' "$1" 2>/dev/null | LC_ALL=C sort -u
}

# _agentfile_mcp_entries <merged Agentfile>: each MCP entry (a name, or a
# map) as one line of sorted-key JSON, sorted, for a whole-entry compare.
_agentfile_mcp_entries() {
  [ -s "$1" ] || return 0
  yq -o=json -I=0 '(.mcp // [])[] | sort_keys(..)' "$1" 2>/dev/null | LC_ALL=C sort -u
}

# _agentfile_mcp_labels <MCP entry lines>: their names, on one line.
_agentfile_mcp_labels() {
  [ -n "$1" ] || return 0
  printf '%s\n' "$1" | yq -p=json -r 'select(type == "!!str") // (if (.name // "") == "" then "(no name)" else .name end)' 2>/dev/null |
    grep -v '^---$' | LC_ALL=C sort -u | paste -sd ' ' -
}

# _agentfile_mcp_names <Agentfile>: the MCP server names it lists.
_agentfile_mcp_names() {
  yq -r 'explode(.) | (.mcp // [])[] | select(type == "!!str") // .name' "$1" 2>/dev/null | LC_ALL=C sort -u
}

# _agentfile_mcp_entries_named <Agentfile> <name>: every MCP entry with that
# name, each as one line of sorted-key JSON (written as is), sorted.
_agentfile_mcp_entries_named() {
  N="$2" yq -o=json -I=0 'explode(.) | (.mcp // [])[] | select((select(type == "!!str") // .name) == strenv(N)) |
    sort_keys(..)' "$1" 2>/dev/null | LC_ALL=C sort -u
}

# _agentfile_can_merge <agentbrew command>: succeeds when it has
# `agentfile merge`. The help goes into a variable first: piping it into
# grep -q would let grep stop early, and under pipefail the writer's
# SIGPIPE would turn a match into a failure.
_agentfile_can_merge() {
  local help
  # shellcheck disable=SC2086 # the command may be "node <path>/cli.js"
  help="$($1 agentfile merge --help 2>&1 || true)"
  grep -q 'agentfile merge' <<< "$help"
}

# _agentfile_mikefarah_yq: succeeds when yq is mikefarah yq (same reason).
_agentfile_mikefarah_yq() {
  local v
  v="$(yq --version 2>&1 || true)"
  grep -q mikefarah <<< "$v"
}
