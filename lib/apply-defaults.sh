#!/bin/bash
# Shared library for applying macOS defaults from data/macos-defaults.json.
# Usage: source this file, then call apply_defaults <script-filter>
#
# The JSON schema is:
#   [{ "domain", "key", "type", "value", "section", "script",
#      "currenthost"?: bool, "expand_vars"?: bool }]

# Skip list: ~/.config/dotfiles/macos-defaults-skip (or $DOTFILES_MACOS_DEFAULTS_SKIP),
# one "domain key" per line. Listed keys are never written.
#
# Requires: jq

apply_defaults() {
  command -v jq &>/dev/null || { echo "Error: jq required but not installed. Run: brew install jq" >&2; return 1; }

  local script_filter="$1"
  local json_file="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/data/macos-defaults.json"

  if [ ! -f "$json_file" ]; then
    echo "Error: $json_file not found" >&2
    return 1
  fi

  local invalid_rows
  if ! invalid_rows="$(jq -r '
    def blank_string($name):
      ((.[$name] | type) != "string") or ((.[$name] | length) == 0);
    def valid_defaults_type:
      .type == "bool" or .type == "int" or .type == "float" or .type == "string";
    to_entries[]
    | select(
        (.value | blank_string("domain")) or
        (.value | blank_string("key")) or
        (.value | blank_string("type")) or
        (.value | has("value") | not) or
        (.value | blank_string("section")) or
        (.value | blank_string("script")) or
        (.value | valid_defaults_type | not) or
        ((.value.currenthost // false | type) != "boolean") or
        ((.value.expand_vars // false | type) != "boolean")
      )
    | "row \(.key): expected domain/key/type/value/section/script; type must be bool, int, float, or string"
  ' "$json_file")"; then
    echo "Error: failed to parse $json_file" >&2
    return 1
  fi

  if [ -n "$invalid_rows" ]; then
    echo "Error: invalid macOS defaults data in $json_file" >&2
    echo "$invalid_rows" >&2
    return 1
  fi

  # Keys the person keeps as their own: one "domain key" per line, # comments.
  local skip_file="${DOTFILES_MACOS_DEFAULTS_SKIP:-$HOME/.config/dotfiles/macos-defaults-skip}"
  # Domain is the first word; the key is the rest (keys may hold spaces).
  # An unreadable or odd file skips nothing and never aborts the apply.
  local skip_list="" line skip_domain skip_key
  if [ -r "$skip_file" ] && [ -f "$skip_file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%%#*}"
      line="${line//$'\r'/}"
      read -r skip_domain skip_key <<< "$line" || true
      [ -n "$skip_domain" ] && [ -n "$skip_key" ] || continue
      skip_list+=$'\n'"$skip_domain $skip_key"
    done < "$skip_file" || true
    skip_list+=$'\n'
  fi

  # Read entries for this script, output tab-separated fields
  while IFS=$'\t' read -r domain key dtype value currenthost expand_vars _section; do
    case "$skip_list" in
      *$'\n'"$domain $key"$'\n'*) continue ;;
    esac
    # Expand $HOME if needed
    if [ "$expand_vars" = "true" ]; then
      value="${value//\$HOME/$HOME}"
    fi

    # Normalize value for defaults write
    local write_value="$value"
    if [ "$dtype" = "bool" ]; then
      if [ "$value" = "true" ]; then
        write_value="true"
      else
        write_value="false"
      fi
    fi

    # Apply the default
    if [ "$currenthost" = "true" ]; then
      defaults -currentHost write "$domain" "$key" "-${dtype}" "$write_value" 2>/dev/null || true
    else
      defaults write "$domain" "$key" "-${dtype}" "$write_value" 2>/dev/null || true
    fi
  done < <(jq -r --arg s "$script_filter" '
    [.[] | select(.script == $s)] | .[] |
    [
      .domain,
      .key,
      .type,
      (.value | tostring),
      (.currenthost // false | tostring),
      (.expand_vars // false | tostring),
      .section
    ] | @tsv
  ' "$json_file")
}
