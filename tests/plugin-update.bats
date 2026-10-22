#!/usr/bin/env bats
# `dotfiles plugin update <name> [<tag>]` (issue #265): move an installed
# plugin to another signed tag in place. The new tag is cloned and checked
# beside the current checkout; the swap and the new lock entry happen only
# when every check passes. A failed update keeps the current version.
# Fixture: a local plugin repo with SSH-signed tags; no network.

load test_helper

REPO_ROOT="$BATS_TEST_DIRNAME/.."
CLI="$BATS_TEST_DIRNAME/../bin/dotfiles-plugin"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  unset DOTFILES_PLUGINS_LOCK DOTFILES_PLUGINS_HOME AGENT_PLUGINS_ALLOWED_SIGNERS
  mkdir -p "$HOME" "$TEST_DIR/stub"
  printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/stub/chezmoi"
  chmod +x "$TEST_DIR/stub/chezmoi"
  export PATH="$TEST_DIR/stub:$PATH"
  ssh-keygen -q -t ed25519 -N '' -C release -f "$TEST_DIR/key"
  ssh-keygen -q -t ed25519 -N '' -C other -f "$TEST_DIR/other"
  KEY="$(cat "$TEST_DIR/key.pub")"
  SRC="$TEST_DIR/dotfiles-acme"
  LOCK="$XDG_CONFIG_HOME/dotfiles/plugins.lock"
  DEST="$XDG_DATA_HOME/dotfiles/plugins/acme"
  make_plugin_repo "$SRC"
  bash "$CLI" add "$SRC@v1.0.0" --signer "$KEY" --yes >/dev/null
}

teardown() {
  chmod -R u+w "$TEST_DIR" 2>/dev/null || true
  rm -rf "$TEST_DIR"
}

gitc() {
  git -C "$SRC" -c user.name=t -c user.email=t@example.com -c core.hooksPath=/dev/null "$@"
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

# release <tag> [<key>]: bump the manifest version, commit, and sign a tag.
release() {
  local version="${1#v}"
  sed -i.bak "s/^version: .*/version: $version/" "$SRC/dotfiles-plugin.yaml" && rm -f "$SRC/dotfiles-plugin.yaml.bak"
  echo "# $1" >> "$SRC/modules/acme/doctor.sh"
  gitc commit -qam "release $1"
  sign_tag "$SRC" "$1" "${2:-$TEST_DIR/key}"
}

lock_ref() { yq -r '.plugins.acme.ref' "$LOCK"; }
lock_commit() { yq -r '.plugins.acme.commit' "$LOCK"; }

# The old checkout is still in place, still verified, and the lock is unchanged.
assert_kept_v1() {
  [ "$(lock_ref)" = v1.0.0 ]
  [ "$(git -C "$DEST" rev-parse HEAD)" = "$(git -C "$SRC" rev-parse 'v1.0.0^{commit}')" ]
  bash "$CLI" verify acme
  [ -z "$(find "$XDG_DATA_HOME/dotfiles/plugins" -maxdepth 1 -name '.staging.*')" ]
}

@test "update with no tag moves to the newest signed tag and re-locks it" {
  release v1.1.0
  release v1.2.0
  run bash "$CLI" update acme < /dev/null
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"v1.0.0 → v1.2.0"* ]]
  [[ "$output" == *"Capabilities: unchanged"* ]]
  [ "$(lock_ref)" = v1.2.0 ]
  [ "$(yq -r '.plugins.acme.version' "$LOCK")" = 1.2.0 ]
  [ "$(lock_commit)" = "$(git -C "$SRC" rev-parse 'v1.2.0^{commit}')" ]
  [ "$(yq -r '.plugins.acme.tree_hash' "$LOCK")" = "$(git -C "$SRC" rev-parse 'v1.2.0^{tree}')" ]
  [ "$(stat -f %Lp "$LOCK")" = 600 ]
  [ "$(git -C "$DEST" rev-parse HEAD)" = "$(lock_commit)" ]
  bash "$CLI" verify acme
  [ -z "$(find "$XDG_DATA_HOME/dotfiles/plugins" -maxdepth 1 -name '.staging.*')" ]
}

@test "update to a named tag installs that tag" {
  release v1.1.0
  release v1.2.0
  run bash "$CLI" update acme v1.1.0 < /dev/null
  [ "$status" -eq 0 ]
  [ "$(lock_ref)" = v1.1.0 ]
  bash "$CLI" verify acme
}

@test "update with no tag skips newer tags that are unsigned or signed by an untrusted key" {
  release v1.1.0
  release v1.2.0 "$TEST_DIR/other"
  gitc commit -q --allow-empty -m lightweight
  gitc tag v1.3.0
  run bash "$CLI" update acme < /dev/null
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped v1.3.0"* ]]
  [[ "$output" == *"skipped v1.2.0"* ]]
  [ "$(lock_ref)" = v1.1.0 ]
}

@test "update with no newer signed tag changes nothing" {
  release v1.1.0 "$TEST_DIR/other"
  cp "$LOCK" "$TEST_DIR/lock.before"
  run bash "$CLI" update acme < /dev/null
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date at v1.0.0"* ]]
  cmp "$LOCK" "$TEST_DIR/lock.before"
  assert_kept_v1
}

@test "update to the installed tag on a verified checkout changes nothing" {
  cp "$LOCK" "$TEST_DIR/lock.before"
  run bash "$CLI" update acme v1.0.0 < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"already at v1.0.0"* ]]
  cmp "$LOCK" "$TEST_DIR/lock.before"
}

@test "update to the installed tag repairs a checkout that no longer matches its lock" {
  printf ' ' >> "$DEST/modules/acme/doctor.sh"
  run bash "$CLI" verify acme
  [ "$status" -ne 0 ]
  run bash "$CLI" update acme v1.0.0 < /dev/null
  echo "$output"
  [ "$status" -eq 0 ]
  assert_kept_v1
}

@test "a named tag signed by an untrusted key is refused and the current version stays" {
  release v1.1.0 "$TEST_DIR/other"
  run bash "$CLI" update acme v1.1.0 --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"not signed by a trusted signer"* ]]
  assert_kept_v1
}

@test "a lightweight tag is refused and the current version stays" {
  gitc commit -q --allow-empty -m lightweight
  gitc tag v1.1.0
  run bash "$CLI" update acme v1.1.0 --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a signed tag"* ]]
  assert_kept_v1
}

@test "an invalid manifest at the new tag is refused and the current version stays" {
  printf 'bogus: true\n' >> "$SRC/dotfiles-plugin.yaml"
  gitc commit -qam bad
  sign_tag "$SRC" v1.1.0 "$TEST_DIR/key"
  run bash "$CLI" update acme v1.1.0 --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"manifest.bogus: unknown key"* ]]
  assert_kept_v1
}

@test "a new tag whose manifest names another plugin is refused" {
  sed -i.bak 's/^name: acme$/name: other/' "$SRC/dotfiles-plugin.yaml" && rm -f "$SRC/dotfiles-plugin.yaml.bak"
  gitc commit -qam rename
  sign_tag "$SRC" v1.1.0 "$TEST_DIR/key"
  run bash "$CLI" update acme v1.1.0 --yes
  [ "$status" -ne 0 ]
  [[ "$output" == *"names plugin other, not acme"* ]]
  assert_kept_v1
}

@test "changed capabilities need approval: refused without a terminal or --yes" {
  yq -i '.capabilities.shell_fragment = true' "$SRC/dotfiles-plugin.yaml"
  release v1.1.0
  run bash "$CLI" update acme < /dev/null
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Capabilities changed"* ]]
  [[ "$output" == *"shell_fragment"* ]]
  [[ "$output" == *"approval needed"* ]]
  assert_kept_v1
  old_caps="$(yq -r '.plugins.acme.capabilities_sha' "$LOCK")"
  run bash "$CLI" update acme --yes
  [ "$status" -eq 0 ]
  [ "$(lock_ref)" = v1.1.0 ]
  [ "$(yq -r '.plugins.acme.capabilities_sha' "$LOCK")" != "$old_caps" ]
  bash "$CLI" verify acme
}

@test "a failed lock write after the swap puts the old checkout back" {
  release v1.1.0
  cp "$LOCK" "$TEST_DIR/lock.before"
  # A read-only lock in a read-only folder: yq cannot rewrite it.
  chmod 400 "$LOCK"
  chmod 500 "$(dirname "$LOCK")"
  run bash "$CLI" update acme < /dev/null
  chmod 700 "$(dirname "$LOCK")"
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"stays at v1.0.0"* ]]
  cmp "$LOCK" "$TEST_DIR/lock.before"
  assert_kept_v1
}

@test "update refuses a plugin that is not installed, a dev plugin, and a ref with a slash" {
  run bash "$CLI" update nope
  [ "$status" -ne 0 ]
  [[ "$output" == *"not installed"* ]]
  run bash "$CLI" update acme feature/x
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a tag"* ]]
  bash "$CLI" remove acme >/dev/null
  bash "$CLI" add --dev "$SRC" --yes >/dev/null
  run bash "$CLI" update acme
  [ "$status" -ne 0 ]
  [[ "$output" == *"dev checkout"* ]]
}

@test "a named older tag installs with a downgrade note" {
  release v1.1.0
  bash "$CLI" update acme < /dev/null >/dev/null
  [ "$(lock_ref)" = v1.1.0 ]
  run bash "$CLI" update acme v1.0.0 < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"downgrade: v1.0.0 is older than v1.1.0"* ]]
  assert_kept_v1
}

@test "the doctor hint for a broken pinned plugin names plugin update" {
  run bash -c 'DOTFILES_DIR="$1"; check() { echo "$2"; }; audit_warn() { :; }; source "$1/modules/plugins/doctor.sh"' _ "$REPO_ROOT"
  echo "$output"
  [[ "$output" == *"(fix: dotfiles plugin update acme v1.0.0)"* ]]
  grep -q 'dotfiles plugin update <name> \[<tag>\]' "$REPO_ROOT/docs/plugins.md"
  run bash "$CLI" --help
  [[ "$output" == *"dotfiles plugin update <name> [<tag>]"* ]]
}
