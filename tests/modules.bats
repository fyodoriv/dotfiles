#!/usr/bin/env bats
# Tests for module-level doctor.sh structure and conventions

load test_helper

MODULES_DIR="$BATS_TEST_DIRNAME/../modules"

# ── Module structure ──────────────────────────────────────────────

@test "all modules have doctor.sh" {
  for mod in "$MODULES_DIR"/*/; do
    local name
    name=$(basename "$mod")
    [ -f "$mod/doctor.sh" ] || { echo "missing: $name/doctor.sh"; return 1; }
  done
}

@test "all modules have severity file" {
  for mod in "$MODULES_DIR"/*/; do
    local name
    name=$(basename "$mod")
    [ -f "$mod/severity" ] || { echo "missing: $name/severity"; return 1; }
  done
}

@test "severity files contain valid values" {
  for mod in "$MODULES_DIR"/*/; do
    local name sev
    name=$(basename "$mod")
    sev=$(cat "$mod/severity")
    case "$sev" in
      critical|important|performance|cosmetic) ;;
      *) echo "invalid severity '$sev' in $name"; return 1 ;;
    esac
  done
}

@test "there are at least 21 modules" {
  local count
  count=$(find "$MODULES_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
  [ "$count" -ge 21 ]
}

# ── doctor.sh file quality ────────────────────────────────────────

@test "all doctor.sh files have bash shebang" {
  for mod in "$MODULES_DIR"/*/doctor.sh; do
    head -1 "$mod" | grep -q '#!/bin/bash' || { echo "missing shebang: $mod"; return 1; }
  done
}

@test "all doctor.sh files use check functions" {
  for mod in "$MODULES_DIR"/*/doctor.sh; do
    # Every doctor module should have at least one check call
    # claude module may early-exit for non-enterprise, but still has checks after the gate
    grep -q 'check\|check_symlink\|check_managed\|check_defaults' "$mod" || \
      { echo "no check calls: $mod"; return 1; }
  done
}

# ── Check ID naming conventions ───────────────────────────────────

@test "check IDs use prefix.name dot notation" {
  # Extract all check IDs across every module in one grep pass, then
  # validate each. Previous version forked grep per module + per ID
  # (~5s); batched version is <100ms even on slow CI.
  local all_ids
  all_ids=$(grep -h -ohE '^[[:space:]]*(check|check_symlink|check_managed|check_defaults)[[:space:]]+"[^"]+"' \
    "$MODULES_DIR"/*/doctor.sh \
    | grep -oE '"[^"]+"' | tr -d '"')

  local bad=""
  for id in $all_ids; do
    # Format: prefix.name where each segment is [a-z_$] starting char,
    # [a-z0-9_${}/.\\-] body. Braces/slashes/backslashes are allowed
    # to support bash parameter expansion like ${rel//\//_}.
    if ! [[ "$id" =~ ^[a-z_$][a-z0-9_$\{\}/.\\-]*\.[a-z_$][a-z0-9_$\{\}/\\]*$ ]]; then
      bad="$bad $id"
    fi
  done
  [ -z "$bad" ] || { echo "bad IDs:$bad"; return 1; }
}

@test "check IDs are unique across all modules" {
  local all_ids
  all_ids=$(grep -ohE '^\s*(check|check_symlink|check_managed|check_defaults)\s+"[^"]+"' \
    "$MODULES_DIR"/*/doctor.sh | grep -oE '"[^"]+"' | tr -d '"' | sort)
  local dupes
  dupes=$(echo "$all_ids" | uniq -d)
  [ -z "$dupes" ] || { echo "duplicate IDs: $dupes"; return 1; }
}

# ── Enterprise gating ────────────────────────────────────────────

@test "claude module gates behind IS_ENTERPRISE" {
  grep -q 'IS_ENTERPRISE' "$MODULES_DIR/claude/doctor.sh"
}

@test "chrome work profile check gates behind IS_ENTERPRISE" {
  grep -q 'IS_ENTERPRISE' "$MODULES_DIR/chrome/doctor.sh"
}

@test "enterprise module exists for enterprise-specific checks" {
  [ -f "$MODULES_DIR/enterprise/doctor.sh" ]
  grep -q 'check' "$MODULES_DIR/enterprise/doctor.sh"
}

# ── Severity distribution ────────────────────────────────────────

@test "at least 2 modules have critical severity" {
  local count
  count=$(grep -rl '^critical$' "$MODULES_DIR"/*/severity | wc -l | tr -d ' ')
  [ "$count" -ge 2 ]
}

@test "no module has empty severity file" {
  for mod in "$MODULES_DIR"/*/severity; do
    [ -s "$mod" ] || { echo "empty: $mod"; return 1; }
  done
}
