#!/usr/bin/env bats
# Company plugin contract v2 (issue #145, step 4): manifest schema,
# plugins.lock with commit + tree hash + capabilities hash, and
# `dotfiles plugin add/remove/list/verify`. Step 5: SSH-signed tags checked
# against the allowed-signers file shared with agentbrew, and `plugin trust`.

load test_helper

REPO_ROOT="$BATS_TEST_DIRNAME/.."
CLI="$BATS_TEST_DIRNAME/../bin/dotfiles-plugin"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  export DOTFILES_PLUGINS_V2=1
  unset EXTRA_OVERLAY_ROOT DOTFILES_PLUGINS_LOCK DOTFILES_PLUGINS_HOME
  mkdir -p "$HOME" "$TEST_DIR/stub"
  printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/stub/chezmoi"
  chmod +x "$TEST_DIR/stub/chezmoi"
  export PATH="$TEST_DIR/stub:$PATH"
  ssh-keygen -q -t ed25519 -N '' -C release -f "$TEST_DIR/key"
  ssh-keygen -q -t ed25519 -N '' -C other -f "$TEST_DIR/other"
  KEY="$(cat "$TEST_DIR/key.pub")"
  OTHER="$(cat "$TEST_DIR/other.pub")"
  SIGNERS="$XDG_CONFIG_HOME/agent-plugins/allowed_signers"
  unset AGENT_PLUGINS_ALLOWED_SIGNERS
  SRC="$TEST_DIR/dotfiles-acme"
  make_plugin_repo "$SRC"
  LOCK="$XDG_CONFIG_HOME/dotfiles/plugins.lock"
  DEST="$XDG_DATA_HOME/dotfiles/plugins/acme"
}

teardown() {
  rm -rf "$TEST_DIR"
}

make_plugin_repo() {
  git init -q "$1"
  cat > "$1/dotfiles-plugin.yaml" <<'YAML'
schema: 1
name: acme
version: 1.0.0
capabilities:
  launchagents: [com.acme.*]
  sudo: false
contributes:
  doctor_modules: modules/
YAML
  mkdir -p "$1/modules/acme"
  echo 'check "acme.one" "acme" "true" ""' > "$1/modules/acme/doctor.sh"
  git -C "$1" add -A
  git -C "$1" -c user.name=t -c user.email=t@example.com -c core.hooksPath=/dev/null commit -qm init
  sign_tag "$1" v1.0.0 "$TEST_DIR/key"
}

# sign_tag <repo> <tag> <private key>: an SSH-signed annotated tag.
sign_tag() {
  git -C "$1" -c gpg.format=ssh -c user.signingkey="$3.pub" -c user.name=t -c user.email=t@example.com \
    tag -s "$2" -m "$2"
}

add_signed() {
  bash "$CLI" add "$SRC@${1:-v1.0.0}" --signer "$KEY" --yes
}

lookup() {
  bash -c 'source "$1/lib/plugin.sh"; plugin_overlay_root' _ "$REPO_ROOT"
}

@test "v2 commands need DOTFILES_PLUGINS_V2=1" {
  DOTFILES_PLUGINS_V2= run bash "$REPO_ROOT/bin/dotfiles-plugin-v2" list
  [ "$status" -eq 2 ]
  [[ "$output" == *"DOTFILES_PLUGINS_V2=1"* ]]
}

@test "add pins commit, tree hash and capabilities in a 0600 lock" {
  run add_signed
  echo "$output"
  [ "$status" -eq 0 ]
  [ -f "$DEST/dotfiles-plugin.yaml" ]
  [ "$(stat -f %Lp "$LOCK")" = 600 ]
  [ "$(yq -r '.plugins.acme.commit' "$LOCK")" = "$(git -C "$SRC" rev-parse 'v1.0.0^{commit}')" ]
  [ "$(yq -r '.plugins.acme.tree_hash' "$LOCK")" = "$(git -C "$SRC" rev-parse 'v1.0.0^{tree}')" ]
  [[ "$(yq -r '.plugins.acme.capabilities_sha' "$LOCK")" == sha256-* ]]
  [ "$(yq -r '.plugins.acme.ref' "$LOCK")" = v1.0.0 ]
  [[ "$output" == *"com.acme.*"* ]]
}

@test "a locked, verified plugin is the overlay root" {
  add_signed
  run lookup
  [ "$status" -eq 0 ]
  [ "$output" = "$DEST" ]
}

@test "one changed byte disables the plugin and verify names the file" {
  add_signed
  printf ' ' >> "$DEST/modules/acme/doctor.sh"
  run lookup
  [ "$status" -eq 1 ]
  run bash "$CLI" verify acme
  [ "$status" -ne 0 ]
  [[ "$output" == *"modules/acme/doctor.sh"* ]]
  run bash "$CLI" list
  [[ "$output" == *"DISABLED"* ]]
}

@test "a different commit at the install path disables the plugin" {
  add_signed
  git -C "$DEST" -c user.name=t -c user.email=t@example.com -c core.hooksPath=/dev/null \
    commit -q --allow-empty -m drift
  run bash "$CLI" verify acme
  [ "$status" -ne 0 ]
  [[ "$output" == *"commit is"* ]]
}

@test "add refuses a spec without a ref" {
  run bash "$CLI" add "$SRC" --signer "$KEY" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"pin a ref"* ]]
  [ ! -f "$LOCK" ]
}

@test "add refuses without approval when there is no terminal" {
  run bash "$CLI" add "$SRC@v1.0.0" --signer "$KEY" < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"approval needed"* ]]
  [ ! -e "$DEST" ]
}

@test "add refuses an invalid manifest and installs nothing" {
  printf 'schema: 1\nname: acme\nversion: 1.0.0\nbogus: true\n' > "$SRC/dotfiles-plugin.yaml"
  git -C "$SRC" -c user.name=t -c user.email=t@example.com -c core.hooksPath=/dev/null commit -qam bad
  git -C "$SRC" tag v2.0.0
  run bash "$CLI" add "$SRC@v2.0.0" --signer "$KEY" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"manifest.bogus: unknown key"* ]]
  [ ! -e "$DEST" ]
  [ -z "$(ls -A "$XDG_DATA_HOME/dotfiles/plugins")" ]
}

@test "add refuses a second install of the same name" {
  add_signed
  run add_signed
  [ "$status" -ne 0 ]
  [[ "$output" == *"already installed"* ]]
}

@test "remove deletes the checkout and the lock entry" {
  add_signed
  run bash "$CLI" remove acme
  [ "$status" -eq 0 ]
  [ ! -e "$DEST" ]
  [ "$(yq -r '.plugins | length' "$LOCK")" = 0 ]
  run lookup
  [ "$status" -eq 1 ]
}

@test "add --dev links a local checkout and list marks it dev" {
  run bash "$CLI" add --dev "$SRC" --yes
  [ "$status" -eq 0 ]
  [ "$(yq -r '.plugins.acme.dev' "$LOCK")" = true ]
  run bash "$CLI" list
  [[ "$output" == *"(dev)"* ]]
  run lookup
  [ "$output" = "$(cd "$SRC" && pwd -P)" ]
}

@test "a dev plugin whose capabilities change is disabled" {
  bash "$CLI" add --dev "$SRC" --yes
  printf '  sudo: true\n' >> "$SRC/dotfiles-plugin.yaml"
  sed -i.bak 's/^  sudo: false$//' "$SRC/dotfiles-plugin.yaml" && rm -f "$SRC/dotfiles-plugin.yaml.bak"
  run bash "$CLI" verify acme
  [ "$status" -ne 0 ]
  [[ "$output" == *"capabilities changed"* ]]
}

@test "the manifest schema rejects unknown keys, bad names and parent paths" {
  printf 'schema: 2\nname: Acme\nversion: 1\ncontributes: {shell: ../x, settings: {other: a}}\n' > "$TEST_DIR/m.yaml"
  run bash -c 'source "$1/lib/plugin.sh"; plugin_validate_manifest "$2"' _ "$REPO_ROOT" "$TEST_DIR/m.yaml"
  [ "$status" -ne 0 ]
  [[ "$output" == *"manifest.schema: must be 1"* ]]
  [[ "$output" == *"manifest.name: does not match"* ]]
  [[ "$output" == *"manifest.version: must be string"* ]]
  [[ "$output" == *"manifest.contributes.shell: does not match"* ]]
  [[ "$output" == *"manifest.contributes.settings.other: unknown key"* ]]
}

@test "add trusts the approved signer in the shared allowed-signers file" {
  run add_signed
  [ "$status" -eq 0 ]
  grep -qxF "acme namespaces=\"git\" $(echo "$KEY" | cut -d' ' -f1-2)" "$SIGNERS"
  [ "$(yq -r '.plugins.acme.signer' "$LOCK")" = "$(echo "$KEY" | cut -d' ' -f1-2)" ]
}

@test "a second install needs no --signer once the key is trusted" {
  add_signed
  bash "$CLI" remove acme
  run bash "$CLI" add "$SRC@v1.0.0" --yes
  [ "$status" -eq 0 ]
}

@test "AGENT_PLUGINS_ALLOWED_SIGNERS overrides the signers path" {
  export AGENT_PLUGINS_ALLOWED_SIGNERS="$TEST_DIR/custom_signers"
  add_signed
  [ -f "$TEST_DIR/custom_signers" ]
  [ ! -f "$SIGNERS" ]
}

@test "a lightweight tag is refused" {
  git -C "$SRC" tag v1.0.1
  run bash "$CLI" add "$SRC@v1.0.1" --signer "$KEY" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a signed tag"* ]]
  [ ! -e "$DEST" ]
}

@test "a tag signed by an untrusted key is refused" {
  sign_tag "$SRC" v1.0.2 "$TEST_DIR/other"
  run bash "$CLI" add "$SRC@v1.0.2" --signer "$KEY" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"not signed by a trusted signer"* ]]
  [ ! -f "$SIGNERS" ]
}

@test "no trusted signer and no --signer is refused" {
  run bash "$CLI" add "$SRC@v1.0.0" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"no trusted signer"* ]]
}

@test "a key trusted for another plugin cannot sign this one" {
  mkdir -p "$(dirname "$SIGNERS")"
  printf 'other-plugin namespaces="git" %s\n' "$KEY" > "$SIGNERS"
  run bash "$CLI" add "$SRC@v1.0.0" --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"no trusted signer"* ]]
}

@test "revoking the signer disables the installed plugin" {
  add_signed
  run bash "$CLI" trust acme --signer "$KEY" --revoke
  [ "$status" -eq 0 ]
  run bash "$CLI" verify acme
  [ "$status" -ne 0 ]
  [[ "$output" == *"signer revoked"* ]]
  run lookup
  [ "$status" -eq 1 ]
  run bash "$CLI" trust acme --signer "$KEY" --yes
  [ "$status" -eq 0 ]
  run bash "$CLI" verify acme
  [ "$status" -eq 0 ]
}

@test "trust needs a terminal or --yes" {
  run bash "$CLI" trust acme --signer "$OTHER" < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"approval needed"* ]]
  [ ! -f "$SIGNERS" ]
}

@test "10: plugin new scaffolds a plugin whose own tests pass against this core" {
  cd "$TEST_DIR"
  run bash "$CLI" new acme-tools
  [ "$status" -eq 0 ]
  [ -f dotfiles-acme-tools/.gitignore ]
  [ -f dotfiles-acme-tools/.github/workflows/ci.yml ]
  [ "$(yq -r .name dotfiles-acme-tools/dotfiles-plugin.yaml)" = acme-tools ]
  ! grep -rq '@NAME@' dotfiles-acme-tools
  DOTFILES_CORE="$REPO_ROOT" run bats dotfiles-acme-tools/tests
  echo "$output"
  [ "$status" -eq 0 ]
  run bash "$CLI" new Bad_Name
  [ "$status" -ne 0 ]
}

@test "10: plugin migrate drafts a manifest from a v1 overlay and lists unmapped files" {
  local o="$TEST_DIR/dotfiles-corp"
  mkdir -p "$o/modules/m" "$o/hooks" "$o/brewfile" "$o/vscode" "$o/misc"
  echo 'check "a" "a" "true" ""' > "$o/modules/m/doctor.sh"
  printf '#!/bin/sh\n' > "$o/hooks/pre-push"; chmod +x "$o/hooks/pre-push"
  printf 'tap "corp/tap"\ncask "corp-app"\n' > "$o/brewfile/Brewfile"
  echo '{}' > "$o/vscode/settings.json"
  echo x > "$o/misc/patch-chrome.sh"
  run bash "$CLI" migrate "$o"
  [ "$status" -eq 0 ]
  [[ "$output" == *"misc/patch-chrome.sh"* ]]
  [[ "$output" != *"modules/m/doctor.sh"* ]]
  [ ! -f "$o/dotfiles-plugin.yaml" ]
  run bash -c 'source "$1/lib/plugin.sh"; plugin_validate_manifest "$2"' _ "$REPO_ROOT" "$o/dotfiles-plugin.yaml.draft"
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(yq -r '.capabilities.hooks[0]' "$o/dotfiles-plugin.yaml.draft")" = pre-push ]
  [ "$(yq -r '.capabilities.brew.taps[0]' "$o/dotfiles-plugin.yaml.draft")" = corp/tap ]
  [ "$(yq -r '.contributes.settings.vscode' "$o/dotfiles-plugin.yaml.draft")" = vscode/settings.json ]
}
