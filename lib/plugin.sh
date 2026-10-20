#!/bin/bash
# The one overlay ("plugin") lookup for the whole core (issue #145, step 3).
# Every caller (doctor, validate, brew, vscode, agentbrew, oss-readiness,
# agentbrew sync) uses these functions. Do not copy the lookup inline.
#
# Resolution order:
#   1. $EXTRA_OVERLAY_ROOT (explicit env — highest priority)
#   2. chezmoi data key `extra_overlay_root`
#   3. The first plugin in plugins.lock that still matches its lock entry.
#      Folder names never make code trusted: there is no auto-discovery
#      (issue #145 gap S3).
#
# Usage (sourced):
#   source "$DOTFILES_DIR/lib/plugin.sh"
#   if root="$(plugin_overlay_root)"; then ...; fi
#   file="$(plugin_overlay_path Agentfile.yaml)"
#
# --no-discover (first argument of either function) skips step 3. Callers
# that never used auto-discovery (vscode, brew, validate) pass it until the
# typed extension points land (step 6).
#
# plugin_overlay_root prints the path and returns 0, returns 1 when there is
# no overlay, and returns 2 (with a message on stderr) for a colon-separated
# list, because only one overlay is allowed.
#
# Lock file (machine-local, mode 0600, never in a repo):
#   ${DOTFILES_PLUGINS_LOCK:-~/.config/dotfiles/plugins.lock}
#   plugins:
#     acme:
#       source: <git url>
#       ref: <tag>
#       version: <manifest version>
#       commit: <full sha>
#       tree_hash: <HEAD tree sha>
#       capabilities_sha: sha256-<hex of the canonical capabilities JSON>
#       signer: <ssh public key that signed the tag; must stay trusted>
#       path: <checkout>
#       dev: false
#       locked_at: <UTC time>

# Without the signers lib, plugin_verify fails closed for pinned plugins.
if [ -f "$(dirname "${BASH_SOURCE[0]}")/plugin-signers.sh" ]; then
  # shellcheck source=lib/plugin-signers.sh
  source "$(dirname "${BASH_SOURCE[0]}")/plugin-signers.sh"
fi

plugin_lock_file() {
  printf '%s' "${DOTFILES_PLUGINS_LOCK:-${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/plugins.lock}"
}

plugin_home() {
  printf '%s' "${DOTFILES_PLUGINS_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles/plugins}"
}

plugin_schema_file() {
  printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/dotfiles-plugin.schema.json"
}

# Prints the locked plugin names, one per line, in lock order.
plugin_lock_names() {
  local lock
  lock="$(plugin_lock_file)"
  [ -f "$lock" ] || return 0
  yq -r '.plugins // {} | keys | .[]' "$lock" 2>/dev/null
}

# plugin_lock_get <name> <field>: prints one field of a lock entry.
plugin_lock_get() {
  local lock
  lock="$(plugin_lock_file)"
  [ -f "$lock" ] || return 1
  N="$1" F="$2" yq -r '.plugins[strenv(N)][strenv(F)] // ""' "$lock" 2>/dev/null
}

# plugin_validate_manifest <file>: prints one error per line and fails when
# the manifest breaks config/dotfiles-plugin.schema.json.
plugin_validate_manifest() {
  local file="$1" json errors
  [ -f "$file" ] || { echo "manifest not found: $file"; return 1; }
  json="$(yq -o=json '.' "$file" 2>/dev/null)" || { echo "manifest is not valid YAML: $file"; return 1; }
  errors="$(printf '%s' "$json" | jq -r --slurpfile schema "$(plugin_schema_file)" '
    def resolve($root): if has("$ref") then $root["$defs"][.["$ref"] | sub("^#/\\$defs/"; "")] else . end;
    def jtype: if type == "number" then "integer" else type end;
    def v($s0; $root; $p):
      ($s0 | resolve($root)) as $s
      | (if $s.type and (jtype != $s.type) then "\($p): must be \($s.type)" else empty end),
        (if ($s | has("const")) and (. != $s.const) then "\($p): must be \($s.const)" else empty end),
        (if $s.pattern and type == "string" and (test($s.pattern) | not) then "\($p): does not match \($s.pattern)" else empty end),
        (if type == "object" then
           (($s.required // [])[] as $k | if has($k) then empty else "\($p).\($k): is required" end),
           (to_entries[] as $e
             | if ($s.properties // {}) | has($e.key) then ($e.value | v($s.properties[$e.key]; $root; "\($p).\($e.key)"))
               elif $s.additionalProperties == false then "\($p).\($e.key): unknown key"
               else empty end)
         else empty end),
        (if type == "array" then
           (if $s.uniqueItems and (length != (unique | length)) then "\($p): items must be unique" else empty end),
           (if $s.items then (to_entries[] | .key as $i | .value | v($s.items; $root; "\($p)[\($i)]")) else empty end)
         else empty end);
    $schema[0] as $s | v($s; $s; "manifest")')" || { echo "manifest check failed: $file"; return 1; }
  [ -z "$errors" ] && return 0
  printf '%s\n' "$errors"
  return 1
}

# Prints sha256-<hex> of the canonical JSON of the manifest's capabilities.
plugin_capabilities_sha() {
  local hex
  hex="$(yq -o=json '.capabilities // {}' "$1" | jq -S -c . | shasum -a 256 | cut -d' ' -f1)"
  printf 'sha256-%s' "$hex"
}

# plugin_verify <name>: succeeds when the checkout still matches its lock
# entry. Otherwise prints what differs and fails. A dev entry skips the
# commit and tree checks.
plugin_verify() {
  local name="$1" path commit tree caps dev signer
  path="$(plugin_lock_get "$name" path)"
  [ -n "$path" ] || { echo "$name: not in $(plugin_lock_file)"; return 1; }
  [ -d "$path" ] || { echo "$name: checkout missing: $path"; return 1; }
  [ -f "$path/dotfiles-plugin.yaml" ] || { echo "$name: dotfiles-plugin.yaml missing"; return 1; }
  dev="$(plugin_lock_get "$name" dev)"
  if [ "$dev" != true ]; then
    commit="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
    [ "$commit" = "$(plugin_lock_get "$name" commit)" ] ||
      { echo "$name: commit is $commit, lock has $(plugin_lock_get "$name" commit)"; return 1; }
    tree="$(git -C "$path" rev-parse 'HEAD^{tree}' 2>/dev/null || true)"
    [ "$tree" = "$(plugin_lock_get "$name" tree_hash)" ] ||
      { echo "$name: tree changed"; return 1; }
    signer="$(plugin_lock_get "$name" signer)"
    if [ -z "$signer" ] || ! plugin_signers_for "$name" | grep -qxF -- "$signer"; then
      echo "$name: signer revoked or missing (trust it again with: dotfiles plugin trust $name --signer <key>)"
      return 1
    fi
    if [ -n "$(git -C "$path" status --porcelain --untracked-files=all 2>/dev/null)" ]; then
      echo "$name: files changed after install:"
      git -C "$path" status --porcelain --untracked-files=all | sed 's/^/  /'
      return 1
    fi
  fi
  caps="$(plugin_capabilities_sha "$path/dotfiles-plugin.yaml")"
  [ "$caps" = "$(plugin_lock_get "$name" capabilities_sha)" ] ||
    { echo "$name: capabilities changed since approval"; return 1; }
  return 0
}

_plugin_find_overlay_root() {
  local discover="${1:-1}" configured candidate

  if [ -n "${EXTRA_OVERLAY_ROOT:-}" ]; then
    printf '%s' "$EXTRA_OVERLAY_ROOT"
    return 0
  fi

  if command -v chezmoi &>/dev/null; then
    configured="$(
      chezmoi execute-template '{{ dig "extra_overlay_root" "" . }}' 2>/dev/null || true
    )"
    if [ -n "$configured" ] && [ -d "$configured" ]; then
      printf '%s' "$configured"
      return 0
    fi
  fi

  [ "$discover" -eq 1 ] || return 1
  for candidate in $(plugin_lock_names); do
    plugin_verify "$candidate" >/dev/null 2>&1 || continue
    plugin_lock_get "$candidate" path
    return 0
  done
  return 1
}

plugin_overlay_root() {
  local root discover=1
  [ "${1:-}" != --no-discover ] || discover=0
  root="$(_plugin_find_overlay_root "$discover")" || return 1
  if [[ "$root" == *:* ]]; then
    echo "ERROR: EXTRA_OVERLAY_ROOT must be a single path, not colon-separated. One overlay at a time. — fix: set EXTRA_OVERLAY_ROOT to one path" >&2
    return 2
  fi
  printf '%s' "$root"
}

# Prints <overlay root>/<relative path> when an overlay exists. Same return
# codes as plugin_overlay_root. The path may not exist; callers check.
plugin_overlay_path() {
  local root rc=0 flag=""
  if [ "${1:-}" = --no-discover ]; then flag=--no-discover; shift; fi
  root="$(plugin_overlay_root $flag)" || rc=$?
  [ "$rc" -eq 0 ] || return "$rc"
  printf '%s/%s' "$root" "$1"
}
