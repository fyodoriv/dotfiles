#!/bin/bash
# Typed extension points for company plugins (issue #145, step 6).
#
# The core reads each verified plugin in plugins.lock and applies its
# contributions through these functions. Every step is checked against the
# plugin's declared capabilities first (lib/plugin-capabilities.sh).
# A plugin that fails verification is skipped and reported, never run.
#
# Needs lib/plugin.sh and lib/plugin-capabilities.sh sourced first.

# Prints "<name>\t<path>" for each locked plugin that passes plugin_verify.
# Prints a "skipped" line on stderr for each one that does not.
plugin_verified_list() {
  local name
  for name in $(plugin_lock_names); do
    if plugin_verify "$name" >/dev/null 2>&1; then
      printf '%s\t%s\n' "$name" "$(plugin_lock_get "$name" path)"
    else
      echo "skipped plugin $name: it does not match plugins.lock (run: dotfiles plugin verify $name)" >&2
    fi
  done
}

# plugin_contribution <plugin path> <key>: prints the absolute path of a
# contributes.<key> entry, or fails when the plugin does not contribute it.
plugin_contribution() {
  local rel
  rel="$(K="$2" yq -r '.contributes[strenv(K)] // ""' "$1/dotfiles-plugin.yaml" 2>/dev/null)"
  [ -n "$rel" ] || return 1
  printf '%s/%s' "$1" "$rel"
}

# ── 6a. Brewfile pass ──────────────────────────────────────────────────
# One `brew bundle --file` pass per plugin, after the core pass. Every tap
# must be listed in capabilities.brew.taps, and casks need
# capabilities.brew.casks: true. An undeclared entry refuses the whole
# plugin Brewfile (status 3). A failed bundle is reported as
# "unreachable (plugin <name>)", never as a silent pass.
plugin_brew_check() {
  local name="$1" brewfile="$2" tap status=0
  while IFS= read -r tap; do
    plugin_require "$name" brew_tap "$tap" || status=3
  done < <(sed -nE 's/^[[:space:]]*tap[[:space:]]+"([^"]+)".*/\1/p' "$brewfile")
  if grep -qE '^[[:space:]]*cask[[:space:]]+"' "$brewfile"; then
    plugin_require "$name" brew_cask "" || status=3
  fi
  return "$status"
}

plugin_brew_pass() {
  local name path brewfile failed=0
  while IFS=$'\t' read -r name path; do
    [ -n "$name" ] || continue
    brewfile="$(plugin_contribution "$path" brewfile)" || continue
    [ -f "$brewfile" ] || { echo "plugin $name: Brewfile missing: $brewfile" >&2; failed=1; continue; }
    if ! plugin_brew_check "$name" "$brewfile"; then
      echo "plugin $name: Brewfile refused (undeclared capability)" >&2
      failed=1
      continue
    fi
    echo "→ brew bundle for plugin $name"
    if ! brew bundle --no-upgrade --file="$brewfile"; then
      echo "brew bundle: unreachable (plugin $name)" >&2
      failed=1
    fi
  done < <(plugin_verified_list)
  return "$failed"
}

# ── 6b. LaunchAgent templates ──────────────────────────────────────────
# A plugin ships plist templates in contributes.launchagents (a folder).
# The core renders them (@HOME@ and @PLUGIN_DIR@ placeholders), checks each
# Label against capabilities.launchagents, installs, and reloads. Plugins
# never edit core plists. Installed labels are recorded per plugin, so
# `plugin remove` can unload and delete them.

plugin_launchagents_dir() {
  printf '%s' "${DOTFILES_LAUNCHAGENTS_DIR:-$HOME/Library/LaunchAgents}"
}

_plugin_state_file() {
  local dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/plugins"
  mkdir -p "$dir"
  printf '%s/%s.%s' "$dir" "$1" "$2"
}

_plugin_plist_label() {
  plutil -extract Label raw -o - "$1" 2>/dev/null
}

# plugin_launchagents_render <name> <path>: installs and reloads changed
# agents. Returns 3 when any Label is not declared (nothing is installed
# for that template).
plugin_launchagents_render() {
  local name="$1" path="$2" src tmpl rendered label dest state status=0
  src="$(plugin_contribution "$path" launchagents)" || return 0
  [ -d "$src" ] || { echo "plugin $name: launchagents folder missing: $src" >&2; return 1; }
  state="$(_plugin_state_file "$name" launchagents)"
  : > "$state.new"
  for tmpl in "$src"/*.plist; do
    [ -f "$tmpl" ] || continue
    rendered="$(mktemp)"
    sed -e "s|@HOME@|$HOME|g" -e "s|@PLUGIN_DIR@|$path|g" "$tmpl" > "$rendered"
    label="$(_plugin_plist_label "$rendered")"
    if [ -z "$label" ]; then
      echo "plugin $name: $(basename "$tmpl") has no Label" >&2
      rm -f "$rendered"; status=1; continue
    fi
    if ! plugin_launchagent_check "$name" "$label"; then
      rm -f "$rendered"; status=3; continue
    fi
    dest="$(plugin_launchagents_dir)/$label.plist"
    echo "$label" >> "$state.new"
    if [ -f "$dest" ] && cmp -s "$rendered" "$dest"; then
      rm -f "$rendered"; continue
    fi
    mkdir -p "$(plugin_launchagents_dir)"
    launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
    mv "$rendered" "$dest"
    launchctl bootstrap "gui/$(id -u)" "$dest" >/dev/null 2>&1 ||
      echo "plugin $name: could not load $label" >&2
    echo "→ loaded $label (plugin $name)"
  done
  mv "$state.new" "$state"
  return "$status"
}

plugin_launchagents_pass() {
  local name path failed=0
  while IFS=$'\t' read -r name path; do
    [ -n "$name" ] || continue
    plugin_launchagents_render "$name" "$path" || failed=1
  done < <(plugin_verified_list)
  return "$failed"
}

# plugin_launchagents_remove <name>: unloads and deletes recorded agents.
plugin_launchagents_remove() {
  local state label
  state="$(_plugin_state_file "$1" launchagents)"
  [ -f "$state" ] || return 0
  while IFS= read -r label; do
    [ -n "$label" ] || continue
    launchctl bootout "gui/$(id -u)/$label" >/dev/null 2>&1 || true
    rm -f "$(plugin_launchagents_dir)/$label.plist"
  done < "$state"
  rm -f "$state"
}

# ── 6d. Shell fragments ────────────────────────────────────────────────
# A plugin with capabilities.shell_fragment: true may contribute one zsh
# fragment (contributes.shell). The core writes one generated file that
# sources each verified fragment in lock order. home/zshrc sources that
# file after core setup and before ~/.zshrc.local.

plugin_shell_file() {
  printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/plugin-shell.zsh"
}

plugin_shell_pass() {
  local name path fragment out tmp failed=0
  out="$(plugin_shell_file)"
  mkdir -p "$(dirname "$out")"
  tmp="$(mktemp "$out.XXXXXX")"
  echo "# Generated by dotfiles (lib/plugin-extensions.sh). Do not edit." > "$tmp"
  while IFS=$'\t' read -r name path; do
    [ -n "$name" ] || continue
    fragment="$(plugin_contribution "$path" shell)" || continue
    if ! plugin_require "$name" shell_fragment; then
      failed=1; continue
    fi
    [ -f "$fragment" ] || { echo "plugin $name: shell fragment missing: $fragment" >&2; failed=1; continue; }
    printf '# plugin %s\n[ -f %q ] && source %q\n' "$name" "$fragment" "$fragment" >> "$tmp"
  done < <(plugin_verified_list)
  mv "$tmp" "$out"
  return "$failed"
}

# ── 6c. Settings merge with priorities ─────────────────────────────────
# A plugin contributes a JSON settings file per target
# (contributes.settings.<target>, today: vscode). Layers merge deep, in
# this order, later wins (the NixOS mkDefault/mkForce model):
#
#   default  the core file
#   plugin   each verified plugin, in lock order (minus its "_force" key)
#   user     ~/.config/dotfiles/settings/<target>.user.json (optional)
#   force    each plugin's "_force" object
#
# A leaf that two plugin/user layers set to different values is a conflict.
# Conflicts print as "settings conflict (<target>): <key path>: <layers>".

plugin_settings_user_file() {
  printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/settings/$1.user.json"
}

# plugin_settings_merge <target> <default json> <out json>: writes the merged
# result and prints conflicts on stderr. Returns 1 on bad JSON.
plugin_settings_merge() {
  local target="$1" base="$2" out="$3" name path file layers tmp user
  layers="$(mktemp)"
  echo '[]' > "$layers"
  while IFS=$'\t' read -r name path; do
    [ -n "$name" ] || continue
    file="$(T="$target" yq -r '.contributes.settings[strenv(T)] // ""' "$path/dotfiles-plugin.yaml")"
    [ -n "$file" ] && [ -f "$path/$file" ] || continue
    tmp="$(mktemp)"
    jq --arg n "plugin $name" --slurpfile s "$path/$file" '. + [{name: $n, kind: "plugin", data: $s[0]}]' \
      "$layers" > "$tmp" || { echo "plugin $name: $file is not valid JSON" >&2; rm -f "$tmp" "$layers"; return 1; }
    mv "$tmp" "$layers"
  done < <(plugin_verified_list)
  user="$(plugin_settings_user_file "$target")"
  if [ -f "$user" ]; then
    tmp="$(mktemp)"
    jq --slurpfile s "$user" '. + [{name: "user", kind: "user", data: $s[0]}]' "$layers" > "$tmp" ||
      { echo "$user is not valid JSON" >&2; rm -f "$tmp" "$layers"; return 1; }
    mv "$tmp" "$layers"
  fi
  tmp="$(mktemp)"
  jq --slurpfile layers "$layers" '
    reduce ($layers[0][] | .data | del(._force)) as $l (.; . * $l)
    | reduce ($layers[0][] | select(.kind == "plugin") | .data._force // {}) as $f (.; . * $f)' \
    "$base" > "$tmp" || { rm -f "$tmp" "$layers"; return 1; }
  mv "$tmp" "$out"
  jq -r --arg t "$target" '
    [ .[] | .name as $n | .data | del(._force) | paths(type != "object") as $p
      | {p: ($p | map(tostring) | join(".")), n: $n, v: getpath($p)} ]
    | group_by(.p)[]
    | select((map(.v) | unique | length) > 1)
    | "settings conflict (\($t)): \(.[0].p): \(map(.n) | join(" vs "))"' "$layers" >&2
  rm -f "$layers"
}

# ── 6e. Doctor modules and validate scripts in a child process ─────────
# Plugin code never runs inside the core shell. Each doctor module
# (contributes.doctor_modules/<module>/doctor.sh) and validate script
# (contributes.validate/*.sh) runs through lib/plugin-sandbox-runner.sh:
#   - a cleaned environment: only HOME, USER, LOGNAME, TMPDIR, LANG, and a
#     fixed PATH; no DOTFILES_* overrides and no inherited tokens
#   - the plugin root as the working folder
#   - a timeout (DOTFILES_PLUGIN_TIMEOUT seconds, default 60)
# Check ids are namespaced as <plugin>/<id>.

plugin_sandbox_run() {
  local root="$1" mode="$2" file="$3" runner
  runner="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/plugin-sandbox-runner.sh"
  (
    cd "$root" || exit 1
    exec env -i HOME="$HOME" USER="${USER:-}" LOGNAME="${LOGNAME:-}" TMPDIR="${TMPDIR:-/tmp}" \
      LANG="${LANG:-en_US.UTF-8}" PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
      perl -e '
        # Run the command in its own process group; on timeout kill the
        # whole group (so no child keeps running) and exit 142.
        my $t = shift; my $pid = fork() // exit 1;
        if (!$pid) { setpgrp(0, 0); exec @ARGV or exit 127; }
        local $SIG{ALRM} = sub { kill "KILL", -$pid; waitpid($pid, 0); exit 142; };
        alarm $t; waitpid($pid, 0); exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
      ' "${DOTFILES_PLUGIN_TIMEOUT:-60}" \
      /bin/bash "$runner" "$mode" "$file"
  )
}

# plugin_doctor_modules <severity|all>: prints "<plugin>\t<root>\t<module dir>"
# for each verified plugin module at that severity.
plugin_doctor_modules() {
  local want="$1" name path dir module sev
  while IFS=$'\t' read -r name path; do
    [ -n "$name" ] || continue
    dir="$(plugin_contribution "$path" doctor_modules)" || continue
    for module in "$dir"/*/; do
      [ -f "$module/doctor.sh" ] || continue
      sev="$(cat "$module/severity" 2>/dev/null || echo cosmetic)"
      [ "$want" = all ] || [ "$sev" = "$want" ] || continue
      printf '%s\t%s\t%s\n' "$name" "$path" "${module%/}"
    done
  done < <(plugin_verified_list 2>/dev/null)
}

# plugin_doctor_run <plugin> <root> <module dir> <list|run>: records each
# result through the caller's check() (so overrides, JSON and counts work).
# A timeout or crash is a failed check "<plugin>/<module>.ran".
plugin_doctor_run() {
  local name="$1" root="$2" module="$3" mode="$4" out status=0 kind id result desc
  out="$(plugin_sandbox_run "$root" "$mode" "$module/doctor.sh" 2>/dev/null)" || status=$?
  while IFS=$'\t' read -r kind id result desc; do
    [ "$kind" = CHECK ] || continue
    if [ "$result" = pass ] || [ "$result" = list ]; then
      check "$name/$id" "$desc" "true" ""
    else
      check "$name/$id" "$desc" "false" ""
    fi
  done <<< "$out"
  if [ "$status" -ne 0 ] && [ "$mode" = run ]; then
    check "$name/$(basename "$module").ran" \
      "plugin $name module $(basename "$module") finished (exit $status; 142 = timeout)" "false" ""
  fi
}

# plugin_validate_run: runs every verified plugin's validate scripts and
# records results through the caller's pass/fail/audit_warn.
plugin_validate_run() {
  local name path dir script out status kind msg
  while IFS=$'\t' read -r name path; do
    [ -n "$name" ] || continue
    dir="$(plugin_contribution "$path" validate)" || continue
    for script in "$dir"/*.sh; do
      [ -f "$script" ] || continue
      status=0
      out="$(plugin_sandbox_run "$path" validate "$script" 2>/dev/null)" || status=$?
      while IFS=$'\t' read -r kind msg; do
        case "$kind" in
          PASS) pass "$name: $msg" ;;
          FAIL) fail "$name: $msg" ;;
          WARN) audit_warn "$name: $msg" ;;
        esac
      done <<< "$out"
      [ "$status" -eq 0 ] || fail "plugin $name validate script $(basename "$script") failed (exit $status; 142 = timeout)"
    done
  done < <(plugin_verified_list 2>/dev/null)
}

# ── 7. Core options ────────────────────────────────────────────────────
# config/plugin-options.yaml declares every option a plugin may set.

plugin_options_file() {
  printf '%s' "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/plugin-options.yaml"
}

# plugin_validate_options <manifest>: prints one error per line and fails
# for an unknown option or a value of the wrong type.
plugin_validate_options() {
  local errors
  errors="$(yq -o=json '.contributes.options // {}' "$1" | jq -r --slurpfile reg <(yq -o=json '.' "$(plugin_options_file)") '
    to_entries[] | .key as $k | .value as $v | ($reg[0].options[$k]) as $o
    | if $o == null then "option \($k): unknown (see config/plugin-options.yaml)"
      elif $o.type == "boolean" and ($v | type) != "boolean" then "option \($k): must be boolean"
      elif $o.type == "list" and ($v | type) != "array" then "option \($k): must be a list"
      else empty end')"
  [ -z "$errors" ] && return 0
  printf '%s\n' "$errors"
  return 1
}

# plugin_option <key>: prints the effective value. Booleans print true or
# false; lists print one item per line. Plugins are read in lock order.
plugin_option() {
  local key="$1" reg type value name path v
  reg="$(plugin_options_file)"
  type="$(K="$key" yq -r '.options[strenv(K)].type // ""' "$reg")"
  [ -n "$type" ] || { echo "unknown option: $key" >&2; return 2; }
  if [ "$type" = boolean ]; then
    value="$(K="$key" yq -r '.options[strenv(K)].default' "$reg")"
    while IFS=$'\t' read -r name path; do
      [ -n "$name" ] || continue
      v="$(K="$key" yq -r '.contributes.options[strenv(K)] | select(. != null)' "$path/dotfiles-plugin.yaml")"
      [ -z "$v" ] || value="$v"
    done < <(plugin_verified_list 2>/dev/null)
    printf '%s\n' "$value"
  else
    {
      K="$key" yq -r '.options[strenv(K)].default[]' "$reg"
      while IFS=$'\t' read -r name path; do
        [ -n "$name" ] || continue
        K="$key" yq -r '.contributes.options[strenv(K)] // [] | .[]' "$path/dotfiles-plugin.yaml"
      done < <(plugin_verified_list 2>/dev/null)
    } | awk 'NF && !seen[$0]++'
  fi
}

# plugin_options_report: every option, its effective value, and which
# plugins set it. Booleans set to different values by two plugins print
# "conflict".
plugin_options_report() {
  local key setters values name path v
  for key in $(yq -r '.options | keys | .[]' "$(plugin_options_file)"); do
    setters="" values=""
    while IFS=$'\t' read -r name path; do
      [ -n "$name" ] || continue
      v="$(K="$key" yq -o=json -I0 '.contributes.options[strenv(K)] | select(. != null)' "$path/dotfiles-plugin.yaml")"
      [ -n "$v" ] || continue
      setters="$setters $name"
      values="$values"$'\n'"$v"
    done < <(plugin_verified_list 2>/dev/null)
    printf '%s = %s' "$key" "$(plugin_option "$key" | paste -sd, -)"
    [ -z "$setters" ] || printf '  (set by:%s)' "$setters"
    [ "$(printf '%s' "$values" | sed '/^$/d' | sort -u | wc -l | tr -d ' ')" -le 1 ] ||
      [ "$(K="$key" yq -r '.options[strenv(K)].type' "$(plugin_options_file)")" != boolean ] ||
      printf '  conflict'
    printf '\n'
  done
}
