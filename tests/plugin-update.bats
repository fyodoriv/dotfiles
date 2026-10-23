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
  bash "$CLI" remove acme --yes >/dev/null
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

# ── Hardening (review of #276) ─────────────────────────────────────────

# commit_evil: a commit with changed plugin code, on no branch tip.
commit_evil() {
  echo 'echo evil' >> "$SRC/modules/acme/doctor.sh"
  gitc commit -qam evil
  git -C "$SRC" rev-parse HEAD
}

@test "a tag named like a signed tag's object ID cannot borrow its signature" {
  real_tag="$(git -C "$SRC" rev-parse refs/tags/v1.0.0)"
  evil="$(commit_evil)"
  # Unsigned annotated tag, named after the real signed tag object.
  gitc tag -a "$real_tag" -m evil "$evil"
  run bash "$CLI" update acme "$real_tag" --yes
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"looks like an object ID"* ]]
  [ "$(lock_commit)" != "$evil" ]
  assert_kept_v1
}

@test "a signed tag object under another tag name is refused" {
  release v1.1.0
  # refs/tags/v2.0.0 points at the real, signed v1.1.0 tag object.
  git -C "$SRC" update-ref refs/tags/v2.0.0 "$(git -C "$SRC" rev-parse refs/tags/v1.1.0)"
  run bash "$CLI" update acme v2.0.0 --yes
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"names tag v1.1.0, not v2.0.0"* ]]
  assert_kept_v1
  # With no tag, update skips the renamed tag and takes the real one.
  run bash "$CLI" update acme < /dev/null
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped v2.0.0"* ]]
  [ "$(lock_ref)" = v1.1.0 ]
}

@test "update with no tag ignores pre-release tags" {
  release v1.1.0
  release v1.1.0-rc.1
  release v1.2.0-beta
  run bash "$CLI" update acme < /dev/null
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(lock_ref)" = v1.1.0 ]
}

@test "update with no tag ignores tags that are not versions" {
  echo '# wip' >> "$SRC/modules/acme/doctor.sh"
  gitc commit -qam wip
  sign_tag "$SRC" wip "$TEST_DIR/key"
  sign_tag "$SRC" latest "$TEST_DIR/key"
  run bash "$CLI" update acme < /dev/null
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date at v1.0.0"* ]]
  assert_kept_v1
}

@test "update with no tag compares versions by number, with or without a v" {
  release v1.9.0
  release 1.10.0
  run bash "$CLI" update acme < /dev/null
  [ "$status" -eq 0 ]
  [ "$(lock_ref)" = 1.10.0 ]
}

@test "a named pre-release installs, and the stable release counts as newer" {
  release v1.1.0-rc.1
  run bash "$CLI" update acme v1.1.0-rc.1 < /dev/null
  [ "$status" -eq 0 ]
  [ "$(lock_ref)" = v1.1.0-rc.1 ]
  run bash "$CLI" update acme < /dev/null
  [[ "$output" == *"up to date at v1.1.0-rc.1"* ]]
  release v1.1.0
  run bash "$CLI" update acme < /dev/null
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(lock_ref)" = v1.1.0 ]
}

@test "update with no tag needs a named tag when the installed ref is not a version" {
  sign_tag "$SRC" stable "$TEST_DIR/key"
  bash "$CLI" update acme stable < /dev/null >/dev/null
  [ "$(lock_ref)" = stable ]
  release v9.0.0
  run bash "$CLI" update acme < /dev/null
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a version"* ]]
  [ "$(lock_ref)" = stable ]
}

# interrupt_at <step> <signal>: the next update gets <signal> at <step>.
# Stub mv and yq send it to the CLI ($PPID); INT also kills the stub
# itself, as Ctrl-C does to the whole foreground group.
interrupt_at() {
  mkdir -p "$TEST_DIR/sig"
  cat > "$TEST_DIR/sig/mv" <<'STUB'
#!/bin/bash
a2="$2"; [ "$1" != -f ] || a2="$3"
case "${FAIL_MV:-}:$a2" in new-aside:*/.staging.*/new) exit 1 ;; esac
/bin/mv "$@"; rc=$?
[ "$1" != -f ] || shift
case "$KILL_AT:$1:$2" in
  old-aside:*:*/.staging.*/old | new-in:*/.staging.*/src:* | lock-replaced:*plugins.lock.tmp.*:*)
    kill "-$KILL_SIG" "$PPID"; [ "$KILL_SIG" != INT ] || kill -INT $$ ;;
esac
exit "$rc"
STUB
  cat > "$TEST_DIR/sig/yq" <<STUB
#!/bin/bash
if [ "\$KILL_AT" = lock-write ] && [[ "\$*" == *locked_at* ]]; then
  kill "-\$KILL_SIG" "\$PPID"; [ "\$KILL_SIG" != INT ] || kill -INT \$\$
  exit 1
fi
exec $(command -v yq) "\$@"
STUB
  chmod +x "$TEST_DIR/sig/mv" "$TEST_DIR/sig/yq"
  export KILL_AT="$1" KILL_SIG="$2"
}

run_interrupted_update() {
  release v1.1.0
  interrupt_at "$1" "$2"
  PATH="$TEST_DIR/sig:$PATH" run bash "$CLI" update acme < /dev/null
  unset KILL_AT KILL_SIG
  echo "$output"
  [ "$status" -ne 0 ]
  assert_kept_v1
}

@test "TERM after the old checkout moves aside puts it back" {
  run_interrupted_update old-aside TERM
}

@test "Ctrl-C after the new checkout moves in puts the old one back" {
  run_interrupted_update new-in INT
}

@test "TERM during the lock write keeps the old checkout and lock" {
  run_interrupted_update lock-write TERM
}

@test "TERM after the lock is replaced, before the check, rolls both back" {
  run_interrupted_update lock-replaced TERM
}

@test "the lock is written through a temp file and a rename" {
  release v1.1.0
  bash "$CLI" update acme < /dev/null >/dev/null
  [ "$(stat -f %Lp "$LOCK")" = 600 ]
  [ -z "$(find "$(dirname "$LOCK")" -name 'plugins.lock.tmp.*')" ]
  run grep -n 'yq -i' "$REPO_ROOT/bin/dotfiles-plugin"
  [ "$status" -ne 0 ]
}

# ── Recovery (re-review of #281) ───────────────────────────────────────

staging_dirs() { find "$XDG_DATA_HOME/dotfiles/plugins" -maxdepth 1 -name '.staging.*'; }

@test "a failed move of the new checkout never nests the old one inside it" {
  release v1.1.0
  interrupt_at new-in TERM
  export FAIL_MV=new-aside
  PATH="$TEST_DIR/sig:$PATH" run bash "$CLI" update acme < /dev/null
  unset KILL_AT KILL_SIG FAIL_MV
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"could not restore everything"* ]]
  [ ! -e "$DEST/old" ]
  [ -d "$(staging_dirs)/old" ]
  # The next plugin command finishes the restore.
  run bash "$CLI" list
  echo "$output"
  assert_kept_v1
}

# crash_update_at <step>: SIGKILL at <step>, so no exit handler runs (as on
# a power cut). A staging folder is left behind.
crash_update_at() {
  release v1.1.0
  interrupt_at "$1" KILL
  PATH="$TEST_DIR/sig:$PATH" run bash "$CLI" update acme < /dev/null
  unset KILL_AT KILL_SIG
  [ "$status" -ne 0 ]
  [ -n "$(staging_dirs)" ]
}

@test "after a crash between the moves, the next plugin command puts the old checkout back" {
  crash_update_at old-aside
  [ ! -e "$DEST" ]
  run bash "$CLI" list
  echo "$output"
  [[ "$output" == *"restored acme"* ]]
  assert_kept_v1
}

@test "after a crash before the lock write, the next plugin command rolls back" {
  crash_update_at new-in
  run bash "$CLI" verify acme
  echo "$output"
  assert_kept_v1
}

@test "after a crash once the lock is written, the next plugin command keeps the new version" {
  crash_update_at lock-replaced
  run bash "$CLI" list
  echo "$output"
  [[ "$output" == *"finished an interrupted update of acme"* ]]
  [ "$(lock_ref)" = v1.1.0 ]
  bash "$CLI" verify acme
  [ -z "$(staging_dirs)" ]
}

@test "doctor reports a staging folder left by a crash" {
  crash_update_at old-aside
  run bash -c 'DOTFILES_DIR="$1"
    check() { if eval "$3" >/dev/null 2>&1; then echo "$1 PASS"; else echo "$1 FAIL $2"; fi; }
    audit_warn() { :; }
    source "$1/modules/plugins/doctor.sh"' _ "$REPO_ROOT"
  echo "$output"
  [[ "$output" == *"plugins.staging_clean FAIL"* ]]
  [[ "$output" == *"dotfiles plugin list"* ]]
  bash "$CLI" list >/dev/null
  run bash -c 'DOTFILES_DIR="$1"
    check() { if eval "$3" >/dev/null 2>&1; then echo "$1 PASS"; else echo "$1 FAIL $2"; fi; }
    audit_warn() { :; }
    source "$1/modules/plugins/doctor.sh"' _ "$REPO_ROOT"
  [[ "$output" == *"plugins.staging_clean PASS"* ]]
}

boot_id() { bash -c 'source "$1/lib/plugin.sh"; plugin_boot_id' _ "$REPO_ROOT"; }

# fake_staging <name> <pid> <boot>: a staging folder with an old checkout
# copy of acme and that owner.
fake_staging() {
  local s="$XDG_DATA_HOME/dotfiles/plugins/.staging.$1"
  mkdir -p "$s"
  cp -R "$DEST" "$s/old"
  printf '%s %s\n' "$2" "$3" > "$s/owner.pid"
  printf '%s\n' "$s"
}

@test "a staging folder whose update is still running is left alone" {
  live="$(fake_staging live "$$" "$(boot_id)")"
  run bash "$CLI" list
  echo "$output"
  [ "$status" -eq 0 ]
  [ -d "$live/old" ]
  [[ "$output" != *"interrupted"* ]]
}

@test "a PID saved before a reboot counts as gone" {
  s="$(fake_staging reboot "$$" before-the-reboot)"
  rm -rf "$DEST"
  run bash "$CLI" list
  echo "$output"
  [[ "$output" == *"restored acme"* ]]
  [ ! -e "$s" ]
  assert_kept_v1
}

@test "recovery never stops the command, even for an old/ with no manifest" {
  s="$XDG_DATA_HOME/dotfiles/plugins/.staging.broken"
  mkdir -p "$s/old"
  printf '999999 %s\n' "$(boot_id)" > "$s/owner.pid"
  run bash "$CLI" list
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"checkout of no installed plugin"* ]]
  [[ "$output" == *"acme"*"v1.0.0"* ]]
  [ -d "$s/old" ]
}

@test "a staging folder beside a dev link, or one with no owner.pid, is never touched" {
  bash "$CLI" remove acme --yes >/dev/null
  mkdir -p "$TEST_DIR/src"
  cp -R "$SRC" "$TEST_DIR/src/acme"
  bash "$CLI" add --dev "$TEST_DIR/src/acme" --yes >/dev/null
  mkdir -p "$TEST_DIR/src/.staging.site/important" "$XDG_DATA_HOME/dotfiles/plugins/.staging.old-core"
  printf '999999 %s\n' "$(boot_id)" > "$TEST_DIR/src/.staging.site/owner.pid"
  echo keep > "$TEST_DIR/src/.staging.site/important/file.txt"
  touch -t 202001010000 "$XDG_DATA_HOME/dotfiles/plugins/.staging.old-core"
  run bash "$CLI" list
  [ "$status" -eq 0 ]
  [ -f "$TEST_DIR/src/.staging.site/important/file.txt" ]
  [ -d "$XDG_DATA_HOME/dotfiles/plugins/.staging.old-core" ]
}

@test "after a crash with the old checkout back but the new lock, the lock entry comes back" {
  release v1.1.0
  s="$XDG_DATA_HOME/dotfiles/plugins/.staging.halfway"
  mkdir -p "$s"
  cp "$LOCK" "$s/plugins.lock.before"
  echo acme > "$s/plugin.name"
  printf '999999 %s\n' "$(boot_id)" > "$s/owner.pid"
  # The lock says v1.1.0, but the checkout is still v1.0.0.
  NEW="$(git -C "$SRC" rev-parse 'v1.1.0^{commit}')" yq -i '.plugins.acme.commit = strenv(NEW) | .plugins.acme.ref = "v1.1.0"' "$LOCK"
  run bash "$CLI" verify acme
  echo "$output"
  [[ "$output" == *"restored the lock entry of acme"* ]]
  [ ! -e "$s" ]
  assert_kept_v1
}

@test "when it cannot tell whether a run is live, recovery leaves its folder alone" {
  # A run whose boot ID was unknown when it started.
  unknown="$(fake_staging unknown "$$" unknown)"
  # A reader that cannot read the boot ID (sysctl blocked, as in a sandbox).
  mkdir -p "$TEST_DIR/nosysctl"
  printf '#!/bin/sh\nexit 1\n' > "$TEST_DIR/nosysctl/sysctl"
  chmod +x "$TEST_DIR/nosysctl/sysctl"
  blind="$(fake_staging blind "$$" "$(boot_id)")"
  PATH="$TEST_DIR/nosysctl:$PATH" run bash "$CLI" list
  echo "$output"
  [ "$status" -eq 0 ]
  [ -d "$unknown/old" ]
  [ -d "$blind/old" ]
}

@test "a lock-only restore needs the new lock: an unchanged lock is left as it is" {
  s="$XDG_DATA_HOME/dotfiles/plugins/.staging.unchanged"
  mkdir -p "$s"
  cp "$LOCK" "$s/plugins.lock.before"
  echo acme > "$s/plugin.name"
  printf '999999 %s\n' "$(boot_id)" > "$s/owner.pid"
  # The checkout fails verify for another reason (a changed file).
  printf ' ' >> "$DEST/modules/acme/doctor.sh"
  cp "$LOCK" "$TEST_DIR/lock.before"
  run bash "$CLI" list
  echo "$output"
  [[ "$output" != *"restored the lock entry"* ]]
  cmp "$LOCK" "$TEST_DIR/lock.before"
}

# ── Unattended and dry-run modes (dotfiles upgrade, task upgrade-updates-plugins) ──

@test "update --dry-run names the newer tag and changes nothing" {
  release v1.1.0
  cp "$LOCK" "$TEST_DIR/lock.before"
  run bash "$CLI" update acme --dry-run < /dev/null
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Would update plugin acme: v1.0.0 → v1.1.0"* ]]
  cmp "$LOCK" "$TEST_DIR/lock.before"
  assert_kept_v1
}

@test "update --dry-run says when changed capabilities need approval" {
  yq -i '.capabilities.shell_fragment = true' "$SRC/dotfiles-plugin.yaml"
  release v1.1.0
  run bash "$CLI" update acme --dry-run < /dev/null
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Would update plugin acme: v1.0.0 → v1.1.0"* ]]
  [[ "$output" == *"needs approval: dotfiles plugin update acme"* ]]
  assert_kept_v1
}

@test "update --unattended updates when the capabilities did not change" {
  release v1.1.0
  run bash "$CLI" update acme --unattended < /dev/null
  [ "$status" -eq 0 ]
  [ "$(lock_ref)" = v1.1.0 ]
}

@test "update --unattended skips changed capabilities with exit 3 and the command to run" {
  yq -i '.capabilities.shell_fragment = true' "$SRC/dotfiles-plugin.yaml"
  release v1.1.0
  run bash "$CLI" update acme --unattended < /dev/null
  echo "$output"
  [ "$status" -eq 3 ]
  [[ "$output" == *"Skipped plugin acme"* ]]
  [[ "$output" == *"run: dotfiles plugin update acme"* ]]
  assert_kept_v1
}

@test "update --unattended skips an installed ref that is not a version with exit 3" {
  sign_tag "$SRC" stable "$TEST_DIR/key"
  bash "$CLI" update acme stable < /dev/null >/dev/null
  run bash "$CLI" update acme --unattended < /dev/null
  echo "$output"
  [ "$status" -eq 3 ]
  [[ "$output" == *"Skipped plugin acme"* ]]
  [[ "$output" == *"dotfiles plugin update acme <tag>"* ]]
}

@test "update --unattended and --yes together are refused" {
  run bash "$CLI" update acme --unattended --yes < /dev/null
  [ "$status" -ne 0 ]
  [[ "$output" == *"--unattended never approves"* ]]
}

@test "update --dry-run runs no crash recovery" {
  s="$XDG_DATA_HOME/dotfiles/plugins/.staging.dry"
  mkdir -p "$s"
  cp -R "$DEST" "$s/old"
  printf '999999 %s\n' "$(boot_id)" > "$s/owner.pid"
  run bash "$CLI" update acme --dry-run < /dev/null
  [ -d "$s/old" ]
}

@test "update --unattended names a newer release no trusted key signed, with exit 3" {
  release v1.1.0 "$TEST_DIR/other"
  run bash "$CLI" update acme --unattended < /dev/null
  echo "$output"
  [ "$status" -eq 3 ]
  [[ "$output" == *"Skipped plugin acme: its newer release v1.1.0 is not signed by a key trusted for acme"* ]]
  [[ "$output" == *"dotfiles plugin trust acme --signer"* ]]
  assert_kept_v1
}

@test "update --unattended fails a plugin that no longer matches its lock, not up to date" {
  printf ' ' >> "$DEST/modules/acme/doctor.sh"
  run bash "$CLI" update acme --unattended < /dev/null
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not match plugins.lock"* ]]
  [[ "$output" == *"fix: dotfiles plugin update acme v1.0.0"* ]]
}

@test "update --unattended gives the real reason for an unsigned newer tag, with no trust hint" {
  gitc commit -q --allow-empty -m lightweight
  gitc tag v1.1.0
  run bash "$CLI" update acme --unattended < /dev/null
  echo "$output"
  [ "$status" -eq 3 ]
  [[ "$output" == *"Skipped plugin acme: its newer release v1.1.0 failed the signature check (v1.1.0 is not a signed tag"* ]]
  [[ "$output" != *"plugin trust"* ]]
}

@test "update --unattended names every changed file of a disabled plugin, once" {
  printf ' ' >> "$DEST/modules/acme/doctor.sh"
  echo new > "$DEST/new.sh"
  run bash "$CLI" update acme --unattended < /dev/null
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"files changed after install"* ]]
  [[ "$output" == *"modules/acme/doctor.sh"* ]]
  [[ "$output" == *"new.sh"* ]]
}

@test "update --unattended reports a disabled plugin as failed even with an untrusted newer tag" {
  release v1.1.0 "$TEST_DIR/other"
  printf ' ' >> "$DEST/modules/acme/doctor.sh"
  run bash "$CLI" update acme --unattended < /dev/null
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not match plugins.lock"* ]]
}

@test "an update to a trusted release names a newer, untrusted one it skipped" {
  release v1.1.0
  release v1.2.0 "$TEST_DIR/other"
  run bash "$CLI" update acme --unattended < /dev/null
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ Updated plugin acme: v1.0.0 → v1.1.0 (skipped newer v1.2.0: tag v1.2.0 is not signed by a trusted signer for acme)"* ]]
}

@test "update --unattended never replaces a plugin that no longer matches its lock, even with a newer release" {
  release v1.1.0
  printf ' ' >> "$DEST/modules/acme/doctor.sh"
  run bash "$CLI" update acme --unattended < /dev/null
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not match plugins.lock"* ]]
  [ "$(lock_ref)" = v1.0.0 ]
}

@test "after a key rotation, update --unattended moves to the release the new key signed" {
  release v1.1.0 "$TEST_DIR/other"
  bash "$CLI" trust acme --signer "$(cat "$TEST_DIR/other.pub")" --yes >/dev/null
  bash "$CLI" trust acme --signer "$KEY" --revoke >/dev/null
  run bash "$CLI" verify acme
  [ "$status" -ne 0 ]
  run bash "$CLI" update acme --unattended < /dev/null
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$(lock_ref)" = v1.1.0 ]
  bash "$CLI" verify acme
}

@test "a revoked signer with no newer trusted release fails with a fix that works" {
  bash "$CLI" trust acme --signer "$KEY" --revoke >/dev/null
  run bash "$CLI" update acme --unattended < /dev/null
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"the signer of v1.0.0 is no longer trusted, and no newer release is signed by a trusted key"* ]]
  [[ "$output" == *"install one: dotfiles plugin update acme <tag>"* ]]
  [[ "$output" != *"fix: dotfiles plugin update acme v1.0.0"* ]]
}

@test "update <name> <ref> --dry-run previews the repair of a changed checkout" {
  printf ' ' >> "$DEST/modules/acme/doctor.sh"
  run bash "$CLI" update acme v1.0.0 --dry-run < /dev/null
  echo "$output"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Would update plugin acme: v1.0.0 → v1.0.0"* ]]
}

@test "a changed checkout whose signer was also revoked gets a fix hint that can work" {
  bash "$CLI" trust acme --signer "$KEY" --revoke >/dev/null
  printf ' ' >> "$DEST/modules/acme/doctor.sh"
  run bash "$CLI" update acme --unattended < /dev/null
  echo "$output"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fix: dotfiles plugin update acme <a tag a trusted key signed>"* ]]
  [[ "$output" != *"fix: dotfiles plugin update acme v1.0.0"* ]]
}
