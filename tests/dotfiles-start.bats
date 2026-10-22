#!/usr/bin/env bats
# `dotfiles` with no arguments is the start screen (bin/dotfiles-start): it
# checks what is missing, refreshes, and prints what needs you and a Next
# line. It never uses sudo, never loads LaunchAgents, and applies or installs
# only with a yes (--yes here; a y/N prompt in a terminal).

load test_helper

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
# Found before setup puts fakes first on PATH (used by the fresh-clone e2e).
REAL_CHEZMOI="$(command -v chezmoi || true)"

setup() {
  TEST_DIR="$(cd "$(mktemp -d)" && pwd -P)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME" "$TEST_DIR/fakebin"
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
  unset XDG_STATE_HOME XDG_CONFIG_HOME DOTFILES_PLUGINS_LOCK DOTFILES_STATS_FILE DOTFILES_LOCK
  CALLS="$TEST_DIR/calls.log"
  : > "$CALLS"

  REPO="$TEST_DIR/dotfiles"
  mkdir -p "$REPO/bin" "$REPO/lib"
  cp "$REPO_ROOT/bin/dotfiles" "$REPO_ROOT/bin/dotfiles-start" "$REPO/bin/"
  for f in colors lock apply-state dotfiles-source-dir; do cp "$REPO_ROOT/lib/$f.sh" "$REPO/lib/"; done
  for stub in dotfiles-doctor dotfiles-install; do
    printf '#!/bin/bash\necho "%s $*" >> "%s"\necho "✓ 10 passed"\nexit "${FAKE_DOCTOR_RC:-0}"\n' "${stub#dotfiles-}" "$CALLS" > "$REPO/bin/$stub"
  done
  chmod +x "$REPO"/bin/*
  git init --quiet "$REPO"
  git -C "$REPO" add -A
  git -C "$REPO" commit --quiet --no-verify -m "chore: initial"

  # Fakes log every call. chezmoi: FAKE_SOURCE is its source dir, FAKE_STATUS
  # the status output. launchctl list prints the labels in FAKE_LOADED.
  cat > "$TEST_DIR/fakebin/chezmoi" <<FAKE
#!/bin/bash
echo "chezmoi \$*" >> "$CALLS"
case "\$1" in
  source-path) echo "\${FAKE_SOURCE:-$REPO}" ;;
  status) [ -n "\${FAKE_STATUS:-}" ] && printf '%s\n' "\$FAKE_STATUS"; exit 0 ;;
esac
exit 0
FAKE
  cat > "$TEST_DIR/fakebin/launchctl" <<FAKE
#!/bin/bash
echo "launchctl \$*" >> "$CALLS"
[ "\$1" = list ] || exit 0
echo "PID	Status	Label"
for l in \${FAKE_LOADED:-}; do printf -- '-\t0\t%s\n' "\$l"; done
FAKE
  printf '#!/bin/bash\necho "sudo $*" >> "%s"\n' "$CALLS" > "$TEST_DIR/fakebin/sudo"
  chmod +x "$TEST_DIR"/fakebin/*
  export PATH="$TEST_DIR/fakebin:$PATH"
  CONFIG="$HOME/.config/chezmoi/chezmoi.yaml"
  STATS="$HOME/.dotfiles-stats.jsonl"
}

teardown() { rm -rf "$TEST_DIR"; }

start() { run "$REPO/bin/dotfiles" "$@"; }
called() { grep -q "^$1" "$CALLS"; }

installed() {
  mkdir -p "$HOME/.config/chezmoi"
  printf 'data:\n  profile: "full"\n' > "$CONFIG"
}

# The record that a full apply leaves (lib/apply-state.sh).
recorded() {
  bash -c 'source "$1/lib/apply-state.sh"; apply_state_record "$1"' _ "$REPO"
}

doctor_ran() {
  local ts="${2:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
  printf '{"task":"doctor","timestamp":"%s","pass":500,"fail":%s,"fixed":0,"warn":0,"skip":0,"seconds_saved":2,"units":1}\n' "$ts" "$1" >> "$STATS"
}

agent() {
  mkdir -p "$HOME/Library/LaunchAgents"
  : > "$HOME/Library/LaunchAgents/com.dotfiles.$1.plist"
}

@test "dotfiles with no arguments prints the start screen, not the help" {
  start
  [ "$status" -eq 0 ]
  [[ "$output" == *"Next: "* ]]
  [[ "$output" != *"Usage:"* ]]
  run "$REPO/bin/dotfiles" start --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--yes"* ]] && [[ "$output" == *"--health"* ]]
}

@test "new Mac: says it is not installed, names the installer, and installs nothing" {
  start
  [ "$status" -eq 0 ]
  [[ "$output" == *"not installed on this Mac yet"* ]]
  [[ "$output" == *"Next: dotfiles install run --yes"* ]]
  ! called install
  ! called "chezmoi apply"
}

@test "new Mac with --yes runs the installer" {
  start --yes
  [ "$status" -eq 0 ]
  grep -qx "install run --yes" "$CALLS"
}

@test "waiting changes are listed; nothing is applied without a yes" {
  installed
  FAKE_STATUS=" M .zshrc" start
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 change(s) wait to be applied"* ]]
  [[ "$output" == *"M .zshrc"* ]]
  [[ "$output" == *"Next: dotfiles apply --if-changed"* ]]
  called "chezmoi status"
  ! called "chezmoi apply"
}

@test "--yes applies the waiting changes through dotfiles apply --if-changed" {
  installed
  FAKE_STATUS=" M .zshrc" start --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"→ dotfiles apply --if-changed"* ]]
  called "chezmoi apply"
  # The apply ends with the doctor pass, as a plain `dotfiles apply` does.
  grep -qx "doctor --fix --quiet" "$CALLS"
}

@test "up to date: nothing needs you, and nothing runs but read-only checks" {
  installed
  recorded
  doctor_ran 0
  agent sync
  FAKE_LOADED="com.dotfiles.sync" start
  [ "$status" -eq 0 ]
  [[ "$output" == *"Set up: profile full"* ]]
  [[ "$output" == *"Applied: nothing changed since the last apply"* ]]
  [[ "$output" == *"Background jobs: 1 of 1"* ]]
  [[ "$output" == *"Health: 500 checks passed"* ]]
  [[ "$output" == *"Nothing needs you."* ]]
  [[ "$output" == *"Next: nothing."* ]]
  ! grep -vE '^(chezmoi (source-path|status)|launchctl list)' "$CALLS"
}

@test "a changed source after the last full apply asks for the full apply" {
  installed
  recorded
  echo "b = 2" > "$REPO/dot_new"
  git -C "$REPO" add dot_new
  git -C "$REPO" commit --quiet --no-verify -m "feat: new"
  start
  [[ "$output" == *"changed since the last full apply"* ]]
  [[ "$output" == *"Next: dotfiles apply --if-changed"* ]]
}

@test "failing doctor checks point at doctor --fix; an old run asks for a fresh check" {
  installed
  recorded
  doctor_ran 3
  start
  [[ "$output" == *"3 failing check(s) in the last doctor run"* ]]
  [[ "$output" == *"Next: dotfiles doctor --fix"* ]]
  : > "$STATS"
  doctor_ran 0 2020-01-01T00:00:00Z
  start
  [[ "$output" == *"the last doctor run was"*"days ago"* ]]
  [[ "$output" == *"Next: dotfiles doctor"* ]]
}

@test "--health runs a fresh dotfiles-doctor --quiet" {
  installed
  recorded
  start --health
  [ "$status" -eq 0 ]
  grep -qx "doctor --quiet" "$CALLS"
  [[ "$output" == *"Health: ✓ 10 passed"* ]]
  FAKE_DOCTOR_RC=1 start --health
  [[ "$output" == *"Next: dotfiles doctor --fix"* ]]
}

@test "a LaunchAgent that is not loaded is reported and never loaded here" {
  installed
  recorded
  doctor_ran 0
  agent sync
  agent morning
  FAKE_LOADED="com.dotfiles.sync" start --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"Background jobs: 1 of 2 loaded; not loaded: morning"* ]]
  [[ "$output" == *"Next: dotfiles-reload-launchagents"* ]]
  ! grep -E '^launchctl (load|bootstrap|kickstart)' "$CALLS"
}

@test "run from another checkout: shows the applied one and never applies from here" {
  installed
  local applied="$TEST_DIR/applied"
  git init --quiet "$applied"
  git -C "$applied" commit --quiet --allow-empty --no-verify -m "chore: applied"
  FAKE_SOURCE="$applied" FAKE_STATUS=" M .zshrc" start --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"this Mac applies"* ]]
  [[ "$output" == *"Not applying from this checkout"* ]]
  ! called "chezmoi apply"
}

@test "the start screen never uses sudo" {
  installed
  FAKE_STATUS=" M .zshrc" start --yes
  ! called sudo
  ! grep -v '^[[:space:]]*#' "$REPO_ROOT/bin/dotfiles-start" | grep -qw sudo
}

# Measurement e2e for the one-command start: a fresh clone, one command, a
# useful first screen; then `dotfiles config set` round-trips a setting.
@test "fresh clone e2e: one command shows the first useful screen; config set round-trips" {
  [ -n "$REAL_CHEZMOI" ] || skip "chezmoi not installed"
  command -v yq >/dev/null 2>&1 || skip "yq not installed"
  local clone="$HOME/apps/dotfiles" path="$(dirname "$REAL_CHEZMOI"):$(dirname "$(command -v yq)"):/usr/bin:/bin"
  mkdir -p "$clone"
  # The working tree, so uncommitted edits count, as a new git checkout.
  (cd "$REPO_ROOT" && git ls-files -z --cached --others --exclude-standard | rsync -a --from0 --files-from=- ./ "$clone/")
  git -C "$clone" init --quiet
  git -C "$clone" add -A
  git -C "$clone" commit --quiet --no-verify -m "chore: clone"
  in_clone() { env -i HOME="$HOME" PATH="$path" TERM=dumb GIT_CONFIG_GLOBAL=/dev/null DOTFILES_STATS_LOG=0 "$@"; }

  run in_clone "$clone/bin/dotfiles"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not installed on this Mac yet"* ]] && [[ "$output" == *"Next: dotfiles install run --yes"* ]] || { echo "$output"; return 1; }

  # What the installer does first: write the chezmoi config with defaults.
  in_clone "$REAL_CHEZMOI" init --source "$clone" --promptDefaults >/dev/null 2>&1
  run in_clone "$clone/bin/dotfiles"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Set up: profile core"* ]] && [[ "$output" == *"Next: "* ]] || { echo "$output"; return 1; }

  run in_clone "$clone/bin/dotfiles" config set weekly_metrics true
  [ "$status" -eq 0 ] || { echo "$output"; return 1; }
  run in_clone "$clone/bin/dotfiles" config get weekly_metrics
  [ "$output" = "true" ]
  [ "$(yq '.data.weekly_metrics' "$HOME/.config/chezmoi/chezmoi.yaml")" = "true" ]
}

@test "the /dotfiles agent command runs the start screen and asks before acting" {
  local f="$REPO_ROOT/commands/dotfiles.md"
  [ -f "$f" ]
  # Agentfile.yaml deploys commands/ to every agent (agentbrew sync).
  awk '/^commands:/ { on = 1; next } on && /^[^ #]/ { exit } on' "$REPO_ROOT/Agentfile.yaml" | grep -qE '^  - \./commands$'
  head -4 "$f" | grep -q '^description: '
  grep -q 'Run `dotfiles` with no arguments' "$f"
  grep -q 'only after the user says yes' "$f"
  grep -q 'dotfiles config set <key> <value>' "$f"
  grep -q 'Never run sudo' "$f"
  grep -q 'Never hand-edit `~/.config/chezmoi/chezmoi.yaml`' "$f"
  # Every command the file names exists in bin/dotfiles or bin/.
  local cmd
  for cmd in apply install update doctor config; do
    grep -qE "^  ${cmd}\)" "$REPO_ROOT/bin/dotfiles" || { echo "bin/dotfiles has no $cmd"; return 1; }
  done
  [ -x "$REPO_ROOT/bin/dotfiles-reload-launchagents" ]
}
