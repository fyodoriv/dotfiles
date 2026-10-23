#!/usr/bin/env bats
# `dotfiles upgrade` moves each pinned company plugin to its newest stable
# signed tag through `dotfiles plugin update --unattended` (task
# upgrade-updates-plugins). A plugin whose capabilities changed is skipped
# and named with the command to run. A failed plugin update is named and
# fails the run, like a failed topgrade step, but the other plugins still
# update. --dry-run lists the pending updates and changes nothing.
# Fixture: local plugin repos with scratch SSH-signed tags; no network.

load test_helper

REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  command -v yq >/dev/null 2>&1 || skip "mikefarah yq is not installed"
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  unset DOTFILES_PLUGINS_LOCK DOTFILES_PLUGINS_HOME AGENT_PLUGINS_ALLOWED_SIGNERS XDG_STATE_HOME
  mkdir -p "$HOME/.local/share/dotfiles/logs" "$TEST_DIR/bin"
  # topgrade, pgrep, osascript, chezmoi: quiet stubs. yq: the real one.
  printf '#!/bin/bash\necho "[topgrade-stub] would run upgrades"\nexit "${TOPGRADE_RC:-0}"\n' > "$TEST_DIR/bin/topgrade"
  printf '#!/bin/bash\nexit 1\n' > "$TEST_DIR/bin/pgrep"
  printf '#!/bin/bash\nexit 0\n' > "$TEST_DIR/bin/osascript"
  printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/bin/chezmoi"
  chmod +x "$TEST_DIR/bin/"*
  ln -s "$(command -v yq)" "$TEST_DIR/bin/yq"
  export PATH="$TEST_DIR/bin:/usr/bin:/bin"
  # A copy of the repo with only what upgrade and plugin need: the real
  # post-steps (bottle re-signing, the jq shim) are left out, so the tests
  # never touch Homebrew or the checkout.
  REPO="$TEST_DIR/repo"
  mkdir -p "$REPO/bin"
  cp "$REPO_ROOT/bin/dotfiles-upgrade" "$REPO_ROOT/bin/dotfiles-plugin" "$REPO/bin/"
  cp -R "$REPO_ROOT/lib" "$REPO_ROOT/config" "$REPO/"
  UPGRADE="$REPO/bin/dotfiles-upgrade"
  CLI="$REPO/bin/dotfiles-plugin"
  export DOTFILES_DIR="$REPO"
  ssh-keygen -q -t ed25519 -N '' -C release -f "$TEST_DIR/key"
  ssh-keygen -q -t ed25519 -N '' -C other -f "$TEST_DIR/other"
  LOCK="$XDG_CONFIG_HOME/dotfiles/plugins.lock"
  # alpha: a newer signed tag, same capabilities.
  make_plugin alpha
  release alpha v1.1.0
  # beta: a newer signed tag whose capabilities changed.
  make_plugin beta
  yq -i '.capabilities.shell_fragment = true' "$TEST_DIR/src-beta/dotfiles-plugin.yaml"
  release beta v1.1.0
}

teardown() {
  rm -rf "$TEST_DIR"
}

gitc() {
  git -C "$1" -c user.name=t -c user.email=t@example.com -c core.hooksPath=/dev/null "${@:2}"
}

# sign_tag <repo> <tag> [<private key>]
sign_tag() {
  git -C "$1" -c gpg.format=ssh -c user.signingkey="${3:-$TEST_DIR/key}.pub" -c user.name=t -c user.email=t@example.com \
    tag -s "$2" -m "$2"
}

# make_plugin <name>: a signed plugin repo at v1.0.0, installed and locked.
make_plugin() {
  local src="$TEST_DIR/src-$1"
  git init -q "$src"
  printf 'schema: 1\nname: %s\nversion: 1.0.0\ncapabilities:\n  sudo: false\ncontributes: {}\n' "$1" > "$src/dotfiles-plugin.yaml"
  echo "# $1" > "$src/README.md"
  gitc "$src" add -A
  gitc "$src" commit -qm init
  sign_tag "$src" v1.0.0
  bash "$CLI" add "$src@v1.0.0" --signer "$(cat "$TEST_DIR/key.pub")" --yes >/dev/null
}

# release <name> <tag> [<private key>]: bump the version, commit, sign a tag.
release() {
  local src="$TEST_DIR/src-$1"
  yq -i ".version = \"${2#v}\"" "$src/dotfiles-plugin.yaml"
  echo "# $2" >> "$src/README.md"
  gitc "$src" commit -qam "release $2"
  sign_tag "$src" "$2" "${3:-}"
}

ref_of() { N="$1" yq -r '.plugins[strenv(N)].ref' "$LOCK"; }

@test "upgrade moves a plugin to its newest signed tag" {
  run bash "$UPGRADE" --yes < /dev/null
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(ref_of alpha)" = v1.1.0 ]
  [[ "$output" == *"Updated plugin alpha: v1.0.0 → v1.1.0"* ]]
  bash "$CLI" verify alpha
  # The updates-landed record names the updated plugin (#301).
  grep -q $'\tdotfiles-upgrade\t.*plugin(s) updated: alpha' "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/updates-landed.tsv"
}

@test "upgrade skips a plugin whose capabilities changed and names the command" {
  run bash "$UPGRADE" --yes < /dev/null
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(ref_of beta)" = v1.0.0 ]
  [[ "$output" == *"Skipped plugin beta"* ]]
  [[ "$output" == *"run: dotfiles plugin update beta"* ]]
  bash "$CLI" verify beta
}

@test "a failing plugin update is named, fails the run, and the plugins after it still update" {
  # A fresh lock: the broken plugin comes first, alpha after it.
  rm -rf "$LOCK" "$XDG_DATA_HOME/dotfiles/plugins"
  make_plugin a0-broken
  release a0-broken v1.1.0
  rm -rf "$TEST_DIR/src-a0-broken"   # its clone now fails
  bash "$CLI" add "$TEST_DIR/src-alpha@v1.0.0" --yes >/dev/null
  [ "$(yq -r '.plugins | keys | .[0]' "$LOCK")" = a0-broken ]
  run bash "$UPGRADE" --yes < /dev/null
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"plugin a0-broken: update failed"* ]]
  [[ "$output" == *"Upgrade complete with failures"* ]]
  [ "$(ref_of alpha)" = v1.1.0 ]
  [ "$(ref_of a0-broken)" = v1.0.0 ]
  bash "$CLI" verify a0-broken
}

@test "a newer release signed by an untrusted key is named in the summary" {
  release alpha v1.2.0 "$TEST_DIR/other"
  rm -rf "$LOCK" "$XDG_DATA_HOME/dotfiles/plugins"
  bash "$CLI" add "$TEST_DIR/src-alpha@v1.0.0" --yes >/dev/null
  # Only v1.2.0 is newer and untrusted once v1.1.0 is gone.
  git -C "$TEST_DIR/src-alpha" tag -d v1.1.0 >/dev/null
  run bash "$UPGRADE" --yes < /dev/null
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipped plugin alpha: its newer release v1.2.0 is not signed by a key trusted for alpha"* ]]
  [ "$(ref_of alpha)" = v1.0.0 ]
}

@test "an unknown result (exit 3 with no Skipped line) counts as a failure" {
  printf '#!/bin/bash\necho "odd"\nexit 3\n' > "$REPO/bin/dotfiles-plugin"
  run bash "$UPGRADE" --yes < /dev/null
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"plugin alpha: update failed (exit 3)"* ]]
}

@test "an unreadable plugins.lock is named, not skipped in silence" {
  printf 'plugins: [unclosed\n' > "$LOCK"
  run bash "$UPGRADE" --yes < /dev/null
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"plugins.lock cannot be read"* ]]
}

@test "the summary asks for dotfiles apply after an update, and the log is private and has no URL tokens" {
  # alpha's source URL carries a fake user:token part (a local path cannot,
  # so the stand-in plugin CLI prints one).
  printf '#!/bin/bash\necho "Source: https://bob:not-a-token@git.example.com/acme.git"\necho "✓ Updated plugin $2: v1.0.0 → v1.1.0"\n' > "$REPO/bin/dotfiles-plugin"
  run bash "$UPGRADE" --yes < /dev/null
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Run dotfiles apply to load the updated plugins"* ]]
  log="$HOME/.local/share/dotfiles/logs/dotfiles-upgrade.log"
  [ "$(stat -f %Lp "$log")" = 600 ]
  [ -z "$(grep 'not-a-token' "$log")" ]
  grep -q 'https://git.example.com/acme.git' "$log"
}

@test "a failure line drops URL tokens too" {
  printf '#!/bin/bash\necho "fatal: could not read https://bob:not-a-token@git.example.com/acme.git"\nexit 1\n' > "$REPO/bin/dotfiles-plugin"
  run bash "$UPGRADE" --yes < /dev/null
  echo "$output"
  [[ "$output" == *"update failed (exit 1): fatal: could not read https://git.example.com/acme.git"* ]]
  [[ "$output" != *"not-a-token"* ]]
}

@test "invalid UTF-8 in one plugin's output does not stop the upgrade (LaunchAgent locale)" {
  cat > "$REPO/bin/dotfiles-plugin" <<'STUB'
#!/bin/bash
if [ "$2" = alpha ]; then printf 'fatal: remote error: \xff\n' >&2; exit 1; fi
echo "✓ Updated plugin $2: v1.0.0 → v1.1.0"
STUB
  chmod +x "$REPO/bin/dotfiles-plugin"
  LANG=C.UTF-8 run /bin/bash "$UPGRADE" --yes < /dev/null
  echo "$output"
  [[ "$output" == *"plugin alpha: update failed (exit 1)"* ]]
  [[ "$output" == *"✓ Updated plugin beta"* ]]
  [[ "$output" == *"Upgrade complete with failures"* ]]
}

@test "upgrade --dry-run fails on a plugin that no longer matches its lock" {
  echo changed >> "$XDG_DATA_HOME/dotfiles/plugins/alpha/README.md"
  run bash "$UPGRADE" --dry-run < /dev/null
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Plugin alpha does not match plugins.lock"* ]]
  [[ "$output" == *"Upgrade complete with failures"* ]]
}

@test "upgrade --dry-run lists the pending plugin updates and changes nothing" {
  cp "$LOCK" "$TEST_DIR/lock.before"
  run bash "$UPGRADE" --dry-run < /dev/null
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Would update plugin alpha: v1.0.0 → v1.1.0"* ]]
  [[ "$output" == *"Would update plugin beta: v1.0.0 → v1.1.0"*"needs approval: dotfiles plugin update beta"* ]]
  cmp "$LOCK" "$TEST_DIR/lock.before"
}

@test "without --yes and without a terminal, no plugin is touched" {
  cp "$LOCK" "$TEST_DIR/lock.before"
  run bash "$UPGRADE" < /dev/null
  [ "$status" -ne 0 ]
  cmp "$LOCK" "$TEST_DIR/lock.before"
}

@test "upgrade leaves a --dev plugin alone" {
  mkdir -p "$TEST_DIR/devsrc"
  cp -R "$TEST_DIR/src-alpha" "$TEST_DIR/devsrc/delta"
  yq -i '.name = "delta"' "$TEST_DIR/devsrc/delta/dotfiles-plugin.yaml"
  bash "$CLI" add --dev "$TEST_DIR/devsrc/delta" --yes >/dev/null
  run bash "$UPGRADE" --yes < /dev/null
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" != *"delta"*"failed"* ]]
  [ "$(ref_of delta)" = dev ]
}

@test "an update that prints no known result line is named and does not abort the upgrade" {
  # A dotfiles-plugin stand-in that succeeds and prints nothing usable.
  printf '#!/bin/bash\necho "something else"\nexit 0\n' > "$REPO/bin/dotfiles-plugin"
  run bash "$UPGRADE" --yes < /dev/null
  echo "$output"
  [[ "$output" == *"plugin alpha: update failed (exit 0): something else"* ]]
  [[ "$output" == *"plugin beta: update failed (exit 0)"* ]]
  [[ "$output" == *"Upgrade complete with failures"* ]]
}
