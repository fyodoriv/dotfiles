#!/usr/bin/env bats

load test_helper

REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home" XDG_CONFIG_HOME="$TEST_DIR/home/.config" XDG_STATE_HOME="$TEST_DIR/home/.local/state" XDG_DATA_HOME="$TEST_DIR/home/.local/share"
  unset DOTFILES_PLUGINS_LOCK DOTFILES_PLUGINS_HOME
  export APP_PATH="$TEST_DIR/Applications/Maccy.app" APP_OWNER=0
  export CASK_METADATA="$TEST_DIR/casks.json" BUNDLE_OBSERVED="$TEST_DIR/bundle" LATER_STEP="$TEST_DIR/later"
  mkdir -p "$HOME" "$APP_PATH" "$TEST_DIR/bin" "$TEST_DIR/work"
  cat > "$TEST_DIR/config.yaml" <<'YAML'
data:
  profile: full
  is_enterprise: false
  use_local_ai: false
  use_ai_tools: false
  brew_skip: []
YAML
  jq -n --arg app "$APP_PATH" '{casks:[{token:"maccy",installed:null,artifacts:[{app:["Maccy.app"],target:$app}]}]}' > "$CASK_METADATA"
  cat > "$TEST_DIR/bin/brew" <<'SH'
#!/bin/bash
case "$1" in
  info) [ -z "${METADATA_UNAVAILABLE:-}" ] || exit 1; cat "$CASK_METADATA";;
  bundle)
    for arg in "$@"; do case "$arg" in --file=*) cp "${arg#--file=}" "$BUNDLE_OBSERVED";; esac; done
    [ -z "${UNRELATED_BUNDLE_FAILURE:-}" ] || exit 7
    if grep -q '^cask "maccy"' "$BUNDLE_OBSERVED" && [ -d "$APP_PATH" ] && [ "$APP_OWNER" != 501 ] && [ -z "${CASK_REGISTERED:-}" ]; then
      echo 'fixture: app adoption needs a terminal for sudo' >&2
      exit 1
    fi;;
esac
SH
  cat > "$TEST_DIR/bin/stat" <<'SH'
#!/bin/bash
if [ "${!#}" = "$APP_PATH" ]; then printf '%s\n' "$APP_OWNER"; else /usr/bin/stat "$@"; fi
SH
  printf '#!/bin/sh\n[ "$1" = -u ] && echo 501\n' > "$TEST_DIR/bin/id"
  chmod +x "$TEST_DIR/bin/"*
  export PATH="$TEST_DIR/bin:$PATH"
}

teardown() { rm -rf "$TEST_DIR"; }

run_brew_stage() {
  chezmoi --config "$TEST_DIR/config.yaml" --source "$REPO_ROOT" --destination "$HOME" execute-template \
    < "$REPO_ROOT/.chezmoiscripts/run_onchange_brew.sh.tmpl" > "$TEST_DIR/work/brew.sh" || return "$?"
  bash -e -c 'bash "$1" && touch "$LATER_STEP"' _ "$TEST_DIR/work/brew.sh"
}

@test "an unregistered foreign-owned app does not abort later apply steps" {
  run run_brew_stage
  [ "$status" -eq 0 ]
  [ -e "$LATER_STEP" ]
  ! grep -q '^cask "maccy"' "$BUNDLE_OBSERVED"
  grep -q '^brew "jq"' "$BUNDLE_OBSERVED"
  [[ "$output" == *maccy*"terminal"* ]]
  [[ "$output" != *"packages up to date"* ]]
}

@test "a same-owner app stays in the bundle" {
  APP_OWNER=501 run run_brew_stage
  [ "$status" -eq 0 ]
  grep -q '^cask "maccy"' "$BUNDLE_OBSERVED"
}

@test "a registered cask is not deferred just because the app is root-owned" {
  jq '.casks[0].installed="1.0"' "$CASK_METADATA" > "$CASK_METADATA.new"
  mv "$CASK_METADATA.new" "$CASK_METADATA"
  CASK_REGISTERED=1 run run_brew_stage
  [ "$status" -eq 0 ]
  grep -q '^cask "maccy"' "$BUNDLE_OBSERVED"
}

@test "a missing app stays in the bundle for installation" {
  rmdir "$APP_PATH"
  run run_brew_stage
  [ "$status" -eq 0 ]
  grep -q '^cask "maccy"' "$BUNDLE_OBSERVED"
}

@test "require_admin metadata alone cannot defer a cask" {
  jq '.casks[0].artifacts=[{pkg:["installer.pkg"]}] | .casks[0].require_admin=true' "$CASK_METADATA" > "$CASK_METADATA.new"
  mv "$CASK_METADATA.new" "$CASK_METADATA"
  run run_brew_stage
  [ "$status" -ne 0 ]
  grep -q '^cask "maccy"' "$BUNDLE_OBSERVED"
}

@test "metadata failure leaves the bundle unchanged and preserves its failure" {
  METADATA_UNAVAILABLE=1 run run_brew_stage
  [ "$status" -ne 0 ]
  grep -q '^cask "maccy"' "$BUNDLE_OBSERVED"
  [ ! -e "$LATER_STEP" ]
}

@test "an unrelated bundle failure remains fatal after deferring a foreign app" {
  UNRELATED_BUNDLE_FAILURE=1 run run_brew_stage
  [ "$status" -eq 7 ]
  [ ! -e "$LATER_STEP" ]
}

@test "a malformed later artifact cannot partially defer an earlier cask" {
  jq '.casks += [{token:"unrequested",installed:null,artifacts:[{app:["Broken.app"],target:{}}]}]' "$CASK_METADATA" > "$CASK_METADATA.new"
  mv "$CASK_METADATA.new" "$CASK_METADATA"
  run run_brew_stage
  [ "$status" -ne 0 ]
  grep -q '^cask "maccy"' "$BUNDLE_OBSERVED"
}

@test "missing target metadata cannot guess where an app was installed" {
  jq 'del(.casks[0].artifacts[0].target)' "$CASK_METADATA" > "$CASK_METADATA.new"
  mv "$CASK_METADATA.new" "$CASK_METADATA"
  run run_brew_stage
  [ "$status" -ne 0 ]
  grep -q '^cask "maccy"' "$BUNDLE_OBSERVED"
  [ ! -e "$LATER_STEP" ]
}
