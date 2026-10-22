#!/usr/bin/env bats
# Per-machine Agentfile layer (issue #259). An untracked
# ~/.config/dotfiles/Agentfile.local.yaml adds MCP servers (or skills,
# rules) on one Mac without a change to the shared Agentfile.yaml. The
# apply-time sync and the agentbrew.global_agentfile_in_sync doctor check
# both get it from lib/agentfile-layers.sh, so they merge the same list.

load test_helper

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  unset XDG_CONFIG_HOME XDG_STATE_HOME DOTFILES_PLUGINS_LOCK
  export DOTFILES_OWNER_MACHINE=false
  LOCAL="$HOME/.config/dotfiles/Agentfile.local.yaml"
  mkdir -p "$HOME/.config/dotfiles" "$TEST_DIR/bin"
  printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/bin/chezmoi"
  # Stub agentbrew: `agentfile merge` writes each input after a "# layer:" line.
  cat > "$TEST_DIR/bin/agentbrew" <<'STUB'
#!/bin/bash
echo "$*" >> "${AGENTBREW_CALLS:-/dev/null}"
[ "$1 $2" = "agentfile merge" ] || exit 0
[ "${3:-}" = "--help" ] && { echo "Usage: agentbrew agentfile merge <agentfiles...>"; exit 0; }
shift 2
inputs=()
while [ $# -gt 0 ]; do
  case "$1" in --output) out="$2"; shift 2 ;; *) inputs+=("$1"); shift ;; esac
done
for f in "${inputs[@]}"; do
  yq '.' "$f" >/dev/null 2>&1 || { echo "agentfile merge: cannot parse $f" >&2; exit 1; }
done
mkdir -p "$(dirname "$out")"
for f in "${inputs[@]}"; do echo "# layer: $(basename "$f")"; cat "$f"; done > "$out"
STUB
  chmod +x "$TEST_DIR/bin/chezmoi" "$TEST_DIR/bin/agentbrew"
  # Only yq from the real PATH, not the rest of its folder.
  command -v yq >/dev/null 2>&1 || skip "mikefarah yq is not installed"
  ln -s "$(command -v yq)" "$TEST_DIR/bin/yq"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# The real agentbrew checkout, when this Mac has one (found with the real
# HOME). Tests that need the real merge skip without it.
setup_file() {
  local co
  co="$(bash -c 'source "$1/lib/agentbrew-locate.sh"; agentbrew_locate' _ "$BATS_TEST_DIRNAME/.." 2>/dev/null || true)"
  if [ -n "$co" ] && [ -f "$co/dist/cli.js" ] && command -v node >/dev/null 2>&1; then
    export AGENTBREW_CHECKOUT="$co" NODE_BIN="$(command -v node)"
  fi
}

# The stub agentbrew, never the user's real one.
layers() {
  PATH="$TEST_DIR/bin:$PATH" bash -c 'source "$1/lib/agentfile-layers.sh"; agentfile_optional_layers "$1"' _ "$REPO_ROOT"
}

problems() {
  PATH="$TEST_DIR/bin:$PATH" bash -c 'source "$1/lib/agentfile-layers.sh"; agentfile_local_layer_problems' _ "$REPO_ROOT"
}

# Runs the real apply-time sync script with the stub agentbrew.
run_sync() {
  env -i HOME="$HOME" PATH="${RUN_SYNC_PATH:-$TEST_DIR/bin}:/usr/bin:/bin" DOTFILES_OWNER_MACHINE=false \
    CHEZMOI_SOURCE_DIR="$REPO_ROOT" bash "$REPO_ROOT/.chezmoiscripts/run_after_agentbrew-sync.sh"
}

@test "no local Agentfile: no local layer" {
  run layers
  [ "$status" -eq 0 ]
  [[ "$output" != *"Agentfile.local.yaml"* ]]
}

@test "a local Agentfile is a layer, merged after the owner rules" {
  printf 'mcp:\n  - figma\n' > "$LOCAL"
  run layers
  [ "$status" -eq 0 ]
  [ "$output" = "$LOCAL" ]
  DOTFILES_OWNER_MACHINE=true run layers
  [ "${lines[0]}" = "$REPO_ROOT/config/agentfile-owner-rules.yaml" ]
  [ "${lines[1]}" = "$LOCAL" ]
}

@test "XDG_CONFIG_HOME moves the local Agentfile" {
  export XDG_CONFIG_HOME="$TEST_DIR/xdg"
  mkdir -p "$XDG_CONFIG_HOME/dotfiles"
  printf 'mcp:\n  - figma\n' > "$XDG_CONFIG_HOME/dotfiles/Agentfile.local.yaml"
  run layers
  [ "$output" = "$XDG_CONFIG_HOME/dotfiles/Agentfile.local.yaml" ]
}

@test "dotfiles apply merges the local Agentfile into the global Agentfile" {
  printf 'mcp:\n  - figma\n' > "$LOCAL"
  run run_sync
  echo "$output"
  [ "$status" -eq 0 ]
  global="$HOME/.config/agentbrew/Agentfile.yaml"
  grep -qx '# layer: Agentfile.yaml' "$global"
  grep -qx '# layer: Agentfile.local.yaml' "$global"
  grep -qx '  - figma' "$global"
  # The shared Agentfile stays the same.
  ! grep -q 'figma$' <(grep -v '^ *#' "$REPO_ROOT/Agentfile.yaml")
}

@test "the last-apply fingerprint changes when the local Agentfile changes" {
  repo="$TEST_DIR/repo"
  git init -q "$repo"
  git -C "$repo" -c user.name=t -c user.email=t@example.com -c core.hooksPath=/dev/null commit -q --allow-empty -m init
  fp() { bash -c 'source "$1/lib/apply-state.sh"; apply_state_fingerprint "$2"' _ "$REPO_ROOT" "$repo"; }
  before="$(fp)"
  printf 'mcp:\n  - figma\n' > "$LOCAL"
  with_local="$(fp)"
  [ "$before" != "$with_local" ]
  printf 'mcp:\n  - figma\n  - other\n' > "$LOCAL"
  [ "$(fp)" != "$with_local" ]
}

@test "apply-state and agentfile-layers name the same local Agentfile path" {
  export XDG_CONFIG_HOME="$TEST_DIR/xdg"
  path="$(bash -c 'source "$1/lib/agentfile-layers.sh"; agentfile_local_layer_path' _ "$REPO_ROOT")"
  [ "$path" = "$XDG_CONFIG_HOME/dotfiles/Agentfile.local.yaml" ]
  grep -qF '${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/Agentfile.local.yaml' "$REPO_ROOT/lib/apply-state.sh"
}

@test "docs name the local Agentfile" {
  grep -q 'Agentfile.local.yaml' "$REPO_ROOT/docs/agentbrew-setup.md"
  grep -q 'Agentfile.local.yaml' "$REPO_ROOT/Agentfile.yaml"
}

# ── Hardening (review of #278) ─────────────────────────────────────────

# The local-layer doctor check: prints its description, then PASS or FAIL.
doctor_local_check() {
  PATH="${DOCTOR_PATH:-$TEST_DIR/bin}:/usr/bin:/bin" bash -c 'DOTFILES_DIR="$1"
    check() { [ "$1" = agentbrew.local_agentfile_valid ] || return 0; echo "$2"; if eval "$3" >/dev/null 2>&1; then echo PASS; else echo FAIL; fi; }
    check_advisory() { :; }; audit_warn() { :; }
    source "$1/modules/agentbrew/doctor.sh"' _ "$REPO_ROOT"
}

# real_agentbrew: a bin folder whose agentbrew runs the real merge and
# stubs every other command (no real sync). Skips without a checkout.
real_agentbrew() {
  [ -n "${AGENTBREW_CHECKOUT:-}" ] || skip "no agentbrew checkout on this Mac"
  mkdir -p "$TEST_DIR/realbin"
  cat > "$TEST_DIR/realbin/agentbrew" <<STUB
#!/bin/bash
[ "\$1 \$2" = "agentfile merge" ] || exit 0
exec "$NODE_BIN" "$AGENTBREW_CHECKOUT/dist/cli.js" "\$@"
STUB
  chmod +x "$TEST_DIR/realbin/agentbrew"
  export RUN_SYNC_PATH="$TEST_DIR/realbin:$TEST_DIR/bin"
}

write_local_with_hook() {
  cat > "$LOCAL" <<'YAML'
mcp:
  - figma
hooks:
  - event: PreToolUse
    matcher: Bash
    command: "~/bin/log-bash.sh"
YAML
}

@test "a hook in the local Agentfile cannot drop a shared hook (real agentbrew merge)" {
  [ -n "${AGENTBREW_CHECKOUT:-}" ] || skip "no agentbrew checkout on this Mac"
  write_local_with_hook
  out="$(layers 2>"$TEST_DIR/warn")"
  args=("$REPO_ROOT/Agentfile.yaml")
  while IFS= read -r l; do [ -n "$l" ] && args+=("$l"); done <<< "$out"
  node "$AGENTBREW_CHECKOUT/dist/cli.js" agentfile merge "${args[@]}" --output "$TEST_DIR/merged.yaml" >/dev/null
  cat "$TEST_DIR/warn"
  grep -q 'block-dangerous-git.sh' "$TEST_DIR/merged.yaml"
  base_bash="$(yq '[.hooks[] | select(.matcher == "Bash")] | length' "$REPO_ROOT/Agentfile.yaml")"
  [ "$(yq '[.hooks[] | select(.matcher == "Bash")] | length' "$TEST_DIR/merged.yaml")" = "$base_bash" ]
  ! grep -q 'log-bash.sh' "$TEST_DIR/merged.yaml"
  grep -q 'hooks:' "$TEST_DIR/warn"
}

@test "apply skips a local Agentfile with hooks, says why, and syncs the rest" {
  write_local_with_hook
  run run_sync
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping $LOCAL"* ]]
  [[ "$output" == *"hooks:"* ]]
  global="$HOME/.config/agentbrew/Agentfile.yaml"
  grep -qx '# layer: Agentfile.yaml' "$global"
  ! grep -qx '# layer: Agentfile.local.yaml' "$global"
}

@test "a malformed local Agentfile is skipped with its parse error, and the rest syncs" {
  printf 'mcp: [figma\n' > "$LOCAL"
  run run_sync
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping $LOCAL"* ]]
  [[ "$output" == *"did not find expected"* ]]
  [[ "$output" == *"agentbrew synced"* ]]
  global="$HOME/.config/agentbrew/Agentfile.yaml"
  grep -qx '# layer: Agentfile.yaml' "$global"
  ! grep -qx '# layer: Agentfile.local.yaml' "$global"
}

@test "mcp: written as a string is reported, not silently ignored" {
  printf 'mcp: figma\n' > "$LOCAL"
  run run_sync
  echo "$output"
  [[ "$output" == *"mcp: must be a list"* ]]
}

@test "doctor: the local Agentfile check fails on hooks, bad YAML, or a non-list mcp" {
  run doctor_local_check
  [[ "$output" == *PASS* ]]
  printf 'mcp:\n  - figma\n' > "$LOCAL"
  run doctor_local_check
  [[ "$output" == *PASS* ]]
  write_local_with_hook
  run doctor_local_check
  echo "$output"
  [[ "$output" == *FAIL* ]]
  [[ "$output" == *"hooks:"* ]]
  printf 'mcp: [figma\n' > "$LOCAL"
  run doctor_local_check
  [[ "$output" == *FAIL* ]]
  printf 'mcp: figma\n' > "$LOCAL"
  run doctor_local_check
  [[ "$output" == *FAIL* ]]
}

@test "the manual sync in the README runs the one script that builds every layer" {
  ! grep -q 'agentbrew agentfile merge ~/apps/dotfiles/Agentfile.yaml --output' "$REPO_ROOT/README.md"
  grep -q 'run_after_agentbrew-sync.sh' "$REPO_ROOT/README.md"
  ! grep -q 'later[^.]*layer adds entries' "$REPO_ROOT/docs/agentbrew-setup.md"
}

@test "the apply skip messages name the local Agentfile" {
  grep -q 'or the local Agentfile changed since the last apply' "$REPO_ROOT/bin/dotfiles"
  grep -q 'or the local Agentfile changed since the last full apply' "$REPO_ROOT/bin/dotfiles-start"
}

@test "duplicate keys, which yq accepts but agentbrew refuses, skip only the local layer (real agentbrew)" {
  real_agentbrew
  printf 'mcp:\n  - figma\nmcp:\n  - other\n' > "$LOCAL"
  run run_sync
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping $LOCAL"* ]]
  [[ "$output" == *"duplicated mapping key"* ]]
  [[ "$output" == *"canonical Agentfile updated"* ]]
  [[ "$output" == *"agentbrew synced"* ]]
  global="$HOME/.config/agentbrew/Agentfile.yaml"
  grep -q 'block-dangerous-git.sh' "$global"
  ! grep -q 'figma' "$global"
}

# A hook that arrives through a YAML merge key (<<: *anchor).
write_local_with_merge_key_hook() {
  cat > "$LOCAL" <<'YAML'
x-base: &b
  hooks:
    - {event: PreToolUse, matcher: Bash, command: "~/bin/log-bash.sh"}
<<: *b
mcp: [figma]
YAML
}

@test "a hook through a YAML merge key is refused too (real agentbrew)" {
  real_agentbrew
  write_local_with_merge_key_hook
  run run_sync
  echo "$output"
  [[ "$output" == *"Skipping $LOCAL"* ]]
  global="$HOME/.config/agentbrew/Agentfile.yaml"
  grep -q 'block-dangerous-git.sh' "$global"
  ! grep -q 'log-bash.sh' "$global"
}

@test "a hook through a YAML merge key is refused when only yq can check" {
  write_local_with_merge_key_hook
  AGENTFILE_AGENTBREW_CMD=false run layers
  [[ "$output" == *"hooks: is not allowed"* ]]
  run bash -c 'source "$1/lib/agentfile-layers.sh"; AGENTFILE_AGENTBREW_CMD=false agentfile_optional_layers "$1" 2>/dev/null' _ "$REPO_ROOT"
  [ -z "$output" ]
}

@test "a second YAML document gets a clear message" {
  printf 'mcp:\n  - figma\n---\n' > "$LOCAL"
  run problems
  echo "$output"
  [[ "$output" == *"more than one YAML document"* ]]
  [[ "$output" != *"not a map"* ]]
}

@test "a local file with only warnings is still merged" {
  printf 'mcp: figma\nskills:\n  - local-skill\n' > "$LOCAL"
  run run_sync
  echo "$output"
  [[ "$output" == *"mcp: must be a list"* ]]
  [[ "$output" != *"Skipping"* ]]
  grep -qx '# layer: Agentfile.local.yaml' "$HOME/.config/agentbrew/Agentfile.yaml"
}

@test "agentbrew alone, without yq, catches a hook through a merge key (real agentbrew)" {
  real_agentbrew
  ! PATH="$TEST_DIR/realbin:/usr/bin:/bin" command -v yq >/dev/null || skip "yq is in /usr/bin"
  write_local_with_merge_key_hook
  run env PATH="$TEST_DIR/realbin:/usr/bin:/bin" AGENTFILE_AGENTBREW_CMD="$TEST_DIR/realbin/agentbrew" \
    bash -c 'source "$1/lib/agentfile-layers.sh"; agentfile_local_layer_problems' _ "$REPO_ROOT"
  echo "$output"
  [[ "$output" == *"hooks: is not allowed"* ]]
  [[ "$output" != *"note:"* ]]
}

@test "with no usable temp folder the local layer is skipped, not trusted" {
  printf 'mcp:\n  - figma\n' > "$LOCAL"
  TMPDIR=/nonexistent/tmp XDG_CACHE_HOME=/nonexistent/cache run layers
  echo "$output"
  [[ "$output" == *"Skipping $LOCAL"* ]]
  [[ "$output" == *"cannot check this file"* ]]
  [ "${lines[${#lines[@]}-1]}" != "$LOCAL" ]
  write_local_with_hook
  TMPDIR=/nonexistent/tmp XDG_CACHE_HOME=/nonexistent/cache run layers
  [[ "$output" == *"Skipping $LOCAL"* ]]
  [ "${lines[${#lines[@]}-1]}" != "$LOCAL" ]
}

@test "the reason shown is agentbrew's Error: line, not its status line" {
  out=$'\033[33m\xe2\x9a\xa1 1 agents \xc2\xb7 1 sync error(s)\033[39m\nError: duplicated mapping key (3:1)'
  run bash -c 'source "$1/lib/agentfile-layers.sh"; _agentfile_error_line "$2"' _ "$REPO_ROOT" "$out"
  [ "$output" = "Error: duplicated mapping key (3:1)" ]
}

@test "doctor: --list mode and an override start no agentbrew" {
  printf 'mcp:\n  - figma\n' > "$LOCAL"
  export AGENTBREW_CALLS="$TEST_DIR/calls"
  : > "$AGENTBREW_CALLS"
  PATH="$TEST_DIR/bin:/usr/bin:/bin" bash -c 'DOTFILES_DIR="$1"; LIST_MODE=true
    check() { :; }; check_advisory() { :; }; audit_warn() { :; }
    source "$1/modules/agentbrew/doctor.sh"' _ "$REPO_ROOT"
  PATH="$TEST_DIR/bin:/usr/bin:/bin" bash -c 'DOTFILES_DIR="$1"
    is_overridden() { [ "$1" = agentbrew.local_agentfile_valid ]; }
    check() { :; }; check_advisory() { :; }; audit_warn() { :; }
    source "$1/modules/agentbrew/doctor.sh"' _ "$REPO_ROOT"
  run grep -c 'agentfile merge' "$AGENTBREW_CALLS"
  [ "$output" = 0 ]
}

@test "doctor: without a merge-capable agentbrew the check says it used yq only" {
  mkdir -p "$TEST_DIR/nomerge"
  printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/nomerge/agentbrew"
  chmod +x "$TEST_DIR/nomerge/agentbrew"
  printf 'mcp:\n  - figma\n' > "$LOCAL"
  DOCTOR_PATH="$TEST_DIR/nomerge:$TEST_DIR/bin" run doctor_local_check
  echo "$output"
  [[ "$output" == *"checked with yq only"* ]]
  [[ "$output" == *PASS* ]]
}
