#!/usr/bin/env bats
# A new user on someone else's Mac runs `chezmoi init` with the defaults and
# their own git identity. These tests render that user's home and check that
# nothing owner-specific reaches it: no owner identity, no paths that only
# exist on the owner's Macs, and no owner-only jobs or checks by default.
# They also pin that the owner's identity still turns the owner-only parts on.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  # The new user's clone lives at the default dotfiles_dir (~/apps/dotfiles),
  # not at the owner's ~/apps/tooling/dotfiles.
  NEW_HOME="$TEST_DIR/home"
  SRC="$NEW_HOME/apps/dotfiles"
  mkdir -p "$SRC"
  (cd "$REPO" && git ls-files -z | rsync -a --from0 --files-from=- ./ "$SRC/")
  # Uncommitted template edits must count too, so copy the working tree.
  cp "$REPO/.chezmoi.yaml.tmpl" "$SRC/"
}

teardown() { rm -rf "$TEST_DIR"; }

_init_config() {
  local email="$1"
  HOME="$NEW_HOME" chezmoi init --source "$SRC" --config-path "$TEST_DIR/cfg.yaml" \
    --promptDefaults \
    --promptString "Git commit name for work/default identity=Alex Example" \
    --promptString "Git commit email for work/default identity=$email" >/dev/null 2>&1
}

_render_home() {
  mkdir -p "$TEST_DIR/out"
  HOME="$NEW_HOME" chezmoi archive --config "$TEST_DIR/cfg.yaml" --source "$SRC" --format tar 2>/dev/null \
    | tar -x -C "$TEST_DIR/out"
}

@test "new user defaults: core profile, no auto-push sync, no Cursor, not the owner" {
  _init_config alex@example.com
  grep -q '^  profile: "core"' "$TEST_DIR/cfg.yaml"
  grep -q '^  auto_sync: false' "$TEST_DIR/cfg.yaml"
  grep -q '^  owner_machine: false' "$TEST_DIR/cfg.yaml"
  grep -q '^  use_cursor: false' "$TEST_DIR/cfg.yaml"
  grep -q '^  global_git_hooks: true' "$TEST_DIR/cfg.yaml"
}

@test "owner identity keeps owner_machine and auto_sync on" {
  _init_config fyodor@sent.com
  grep -q '^  owner_machine: true' "$TEST_DIR/cfg.yaml"
  grep -q '^  auto_sync: true' "$TEST_DIR/cfg.yaml"
}

@test "rendered new-user home has no owner identity" {
  _init_config alex@example.com
  _render_home
  run grep -rIl -i -E 'cbrwizard|fyodor@|Ivanischev' "$TEST_DIR/out"
  [ "$status" -ne 0 ] || { echo "owner identity in: $output"; return 1; }
  # The owner's agent policy (attribution rewrite, PR body rules) stays off.
  git config --file "$TEST_DIR/out/.gitconfig" --bool dotfiles.agentPolicy | grep -qx false
}

@test "owner render keeps the owner's agent policy on" {
  _init_config fyodor@sent.com
  _render_home
  git config --file "$TEST_DIR/out/.gitconfig" --bool dotfiles.agentPolicy | grep -qx true
}

@test "rendered new-user home uses owner paths only as fallbacks" {
  _init_config alex@example.com
  _render_home
  # Config files (not lifecycle scripts) must not name the owner's layout.
  run grep -rIn 'apps/tooling' "$TEST_DIR/out" --exclude-dir=.chezmoiscripts --exclude=ensure-chrome.sh
  [ "$status" -ne 0 ] || { echo "owner path in config: $output"; return 1; }
  grep -q "$SRC/bin/dotfiles-mas-upgrade" "$TEST_DIR/out/.config/topgrade.toml"
  # Lifecycle scripts may only probe the owner's layout after the real
  # source dir: as a comment, an elif branch, the body of that branch,
  # a probe-list entry, or a ${VAR:-fallback} default.
  local bad
  bad="$(awk '
    FNR == 1 { prev = "" }
    /apps\/tooling/ {
      ok = ($0 ~ /^[[:space:]]*#/) || ($0 ~ /elif /) || (prev ~ /elif /) \
        || ($0 ~ /^[[:space:]]*"\$HOME\/apps\/tooling\/dotfiles" \\$/) \
        || ($0 ~ /:-[^}]*apps\/tooling/)
      if (!ok) print FILENAME ":" FNR ": " $0
    }
    { prev = $0 }' "$TEST_DIR"/out/.chezmoiscripts/*.sh)"
  [ -z "$bad" ] || { echo "owner path used as primary: $bad"; return 1; }
}

@test "global_git_hooks=false drops core.hooksPath" {
  _init_config alex@example.com
  printf '  global_git_hooks: false\n' >> "$TEST_DIR/cfg.yaml"
  _render_home
  run grep -q 'hooksPath' "$TEST_DIR/out/.gitconfig"
  [ "$status" -ne 0 ]
}

@test "doctor skips owner-only modules when owner_machine=false" {
  grep -q 'dig "owner_machine" true' "$REPO/bin/dotfiles-doctor"
  grep -q 'OWNER_MACHINE:-true}" = "false"' "$REPO/modules/personal-machine/doctor.sh"
  grep -q 'OWNER_MACHINE:-true}" = "false"' "$REPO/modules/minsky/doctor.sh"
}
