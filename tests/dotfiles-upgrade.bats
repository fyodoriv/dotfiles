#!/usr/bin/env bats
# Tests for bin/dotfiles-upgrade — software upgrade orchestration.
#
# Post PR #126 the script is a thin wrapper around `topgrade` (the canonical
# GET-don't-IMPLEMENT unified upgrader). These tests pin the wrapper's
# value-add: lock acquisition, grind-active safety, logging, notification,
# bottle re-signing — NOT topgrade's per-manager upgrade logic, which is
# tested upstream and configured via dot_config/topgrade.toml.tmpl.

load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../bin/dotfiles-upgrade"

# Build all the command stubs ONCE per file, into BATS_FILE_TMPDIR.
# Each test then sets PATH to point at the stubs (no per-test cat>+chmod).
setup_file() {
  export FILE_TMPDIR="$BATS_FILE_TMPDIR"
  local stub_bin="$FILE_TMPDIR/stub-bin"
  mkdir -p "$stub_bin"

  # topgrade — succeeds quietly. Wrapper passes it `--no-tmux --yes` plus
  # optionally `--dry-run`; the stub doesn't care about the arg shape, it
  # just emits a sentinel line so output assertions can grep for it.
  cat > "$stub_bin/topgrade" <<'STUB'
#!/bin/bash
echo "[topgrade-stub] would run upgrades"
case " $* " in
  *" --dry-run "*) echo "[topgrade-stub] --dry-run passed" ;;
esac
exit 0
STUB

  # pgrep — reports no active grind/devin sessions
  cat > "$stub_bin/pgrep" <<'STUB'
#!/bin/bash
exit 1
STUB

  # osascript (notify) — silent no-op
  cat > "$stub_bin/osascript" <<'STUB'
#!/bin/bash
exit 0
STUB

  # date — pass through to the real one (the wrapper uses `date '+%s'`).
  # We DON'T stub it; just chmod the stubs that exist.
  chmod +x "$stub_bin"/*
}

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_BIN="$TEST_DIR/bin"
  mkdir -p "$TEST_HOME/.local/share/dotfiles/logs" "$TEST_BIN"
  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$BATS_TEST_DIRNAME/.."

  # Fast copy of the prebuilt stubs.
  cp -r "$FILE_TMPDIR/stub-bin/." "$TEST_BIN/"

  # Put stubs first on PATH so they shadow real commands. /usr/bin needed
  # for date, tee, tail, mkdir, etc.
  export PATH="$TEST_BIN:/usr/bin:/bin"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── Static checks ────────────────────────────────────────────────────

@test "dotfiles-upgrade exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

@test "dotfiles-upgrade has correct shebang" {
  head -1 "$SCRIPT" | grep -q '#!/bin/bash'
}

@test "dotfiles-upgrade uses strict mode" {
  grep -q 'set -euo pipefail' "$SCRIPT"
}

@test "dotfiles-upgrade sources colors.sh" {
  grep -q 'source.*lib/colors.sh' "$SCRIPT"
}

@test "dotfiles-upgrade sources stats.sh" {
  grep -q 'source.*lib/stats.sh' "$SCRIPT"
}

@test "dotfiles-upgrade sources lock.sh" {
  grep -q 'source.*lib/lock.sh' "$SCRIPT"
}

@test "dotfiles-upgrade delegates to topgrade" {
  # The wrapper's job is to call topgrade — not to reimplement upgrade logic.
  # Catching a regression where someone replaces the wrapper with a
  # hand-rolled version (the 239-line predecessor) would be a "GET don't
  # IMPLEMENT" violation. Pin the dependency.
  grep -q '^if topgrade ' "$SCRIPT"
}

# ── Help ─────────────────────────────────────────────────────────────

@test "--help shows usage and exits 0" {
  run "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]]
}

@test "--help mentions --dry-run" {
  run "$SCRIPT" --help
  [[ "$output" == *"dry-run"* ]]
}

@test "--help describes topgrade integration" {
  # Help text should tell operators where to configure topgrade.
  run "$SCRIPT" --help
  [[ "$output" == *"topgrade"* ]]
}

# ── Dry run ──────────────────────────────────────────────────────────

@test "--dry-run exits 0 with topgrade available" {
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
}

@test "--dry-run does not create last-upgrade file" {
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_HOME/.local/share/dotfiles/last-upgrade" ]
}

@test "--dry-run passes --dry-run flag to topgrade" {
  run "$SCRIPT" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"--dry-run passed"* ]]
}

@test "blocked Node publisher skips topgrade entirely" {
  mkdir -p "$TEST_HOME/.local/state/dotfiles"
  touch "$TEST_HOME/.local/state/dotfiles/endpoint-node-publisher-blocked"

  run "$SCRIPT"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Software upgrade skipped"* ]]
  [[ "$output" != *"[topgrade-stub] would run upgrades"* ]]
}

# ── Grind safety ─────────────────────────────────────────────────────

@test "skips upgrade when minsky autonomous iteration is in flight" {
  # Match the REAL signal — `pgrep -f 'minsky run\b'`. Sharpened from
  # the prior over-eager `pgrep -f minsky` (which matched any process
  # path containing 'minsky', e.g. vim editing ~/apps/tooling/minsky/...).
  cat > "$TEST_BIN/pgrep" <<'STUB'
#!/bin/bash
# Simulate `minsky run` autonomous iteration running
[[ "$*" == *"minsky run"* ]] && exit 0
exit 1
STUB
  chmod +x "$TEST_BIN/pgrep"

  run "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"minsky autonomous iteration in flight"* ]]
}

@test "does NOT skip on an interactive dvb (devin --permission-mode) session" {
  # Operator is at the keyboard with a `dvb` session open. They invoked
  # `dotfiles upgrade` themselves — skipping would be backwards.
  # PR #129 dropped the devin check; the safety now only triggers on
  # actual autonomous loops.
  cat > "$TEST_BIN/pgrep" <<'STUB'
#!/bin/bash
# Simulate a legacy `caffeinate -ms devin --permission-mode dangerous --`
# process from the 2026-05-29 reproducer in the operator's shell.
[[ "$*" == *"devin"* ]] && exit 0
[[ "$*" == *"minsky run"* ]] && exit 1
exit 1
STUB
  chmod +x "$TEST_BIN/pgrep"

  run "$SCRIPT" --yes
  [ "$status" -eq 0 ]
  [[ "$output" != *"Skipping upgrade"* ]]
  # Sanity: the wrapper ran topgrade rather than aborting
  [[ "$output" == *"[topgrade-stub] would run upgrades"* ]]
}

@test "does NOT skip when 'minsky' appears in an unrelated path (e.g. vim editing minsky source)" {
  # Original `pgrep -f minsky` regex was too broad — it matched an
  # operator editing files under ~/apps/tooling/minsky in vim/etc.
  # The new `pgrep -f 'minsky run\b'` regex requires the canonical
  # autonomous-iteration argv shape.
  cat > "$TEST_BIN/pgrep" <<'STUB'
#!/bin/bash
# Simulate a vim editing a minsky source file
[[ "$*" == *"minsky run"* ]] && exit 1   # not an autonomous iteration
[[ "$*" == *"minsky"* ]] && exit 0       # path match, but not the loop
exit 1
STUB
  chmod +x "$TEST_BIN/pgrep"

  run "$SCRIPT" --yes
  [ "$status" -eq 0 ]
  [[ "$output" != *"Skipping upgrade"* ]]
}

# ── topgrade-missing handling ────────────────────────────────────────

@test "exits non-zero with friendly hint when topgrade missing" {
  rm "$TEST_BIN/topgrade"
  # Restrict PATH so the system topgrade (if installed) doesn't get picked up.
  PATH="$TEST_BIN:/usr/bin:/bin" run "$SCRIPT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"topgrade not installed"* ]]
  [[ "$output" == *"dotfiles apply"* ]]
}

# ── Full run ─────────────────────────────────────────────────────────

@test "full run creates last-upgrade timestamp file" {
  run "$SCRIPT" --yes
  [ "$status" -eq 0 ]
  [ -f "$TEST_HOME/.local/share/dotfiles/last-upgrade" ]
}

@test "full run creates log file" {
  run "$SCRIPT" --yes
  [ "$status" -eq 0 ]
  [ -f "$TEST_HOME/.local/share/dotfiles/logs/dotfiles-upgrade.log" ]
}

@test "full run invokes topgrade" {
  run "$SCRIPT" --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"[topgrade-stub] would run upgrades"* ]]
}

@test "full run shows upgrade complete summary" {
  run "$SCRIPT" --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"Upgrade complete"* ]]
}

# ── Log management ───────────────────────────────────────────────────

@test "log file is trimmed to 1000 lines" {
  # topgrade is verbose enough that the prior 500-line cap was rotating
  # mid-run and dropping the actual upgrade summary. New cap is 1000.
  grep -q 'tail -1000' "$SCRIPT"
}

# ── Bottle re-signing (endpoint agent) ───────────────────────────────

@test "topgrade.toml runs bottle re-signing post-upgrade (endpoint agent)" {
  # `brew upgrade` (invoked by topgrade's brew_formula + brew_cask steps)
  # installs new bottles unsigned; endpoint agent fires an policy dialog on
  # every spawn of an unsigned bottle, so an upgrade would silently
  # reintroduce the dialogs the arm64 migration removed. Post PR #128
  # the re-signing helper is invoked from topgrade's [post_commands]
  # block (not bin/dotfiles-upgrade) — same coverage, plus direct
  # `topgrade` runs also get the safety. See AGENTS.md rule #10.
  local cfg="$BATS_TEST_DIRNAME/../dot_config/topgrade.toml.tmpl"
  [ -f "$cfg" ]
  grep -q '\[post_commands\]' "$cfg"
  grep -q 'dotfiles-adhoc-sign-bottles' "$cfg"
}

@test "topgrade.toml runs dev-cache cleanup post-upgrade" {
  # PR #128 deleted the standalone com.dotfiles.cleanup LaunchAgent and
  # moved its dotfiles-specific cleanups (gradle, /tmp/node_modules,
  # ~/Library/Caches) into topgrade's [post_commands] so they fire
  # after the upgrade has downloaded new artifacts (correct ordering:
  # download new → purge old). brew/npm/yarn cache pruning comes from
  # topgrade's own `--cleanup` flag passed by the wrapper.
  local cfg="$BATS_TEST_DIRNAME/../dot_config/topgrade.toml.tmpl"
  grep -q "bin/cleanup" "$cfg"
}

@test "wrapper passes --cleanup to topgrade" {
  # Replaces the brew/npm/yarn cache pruning the standalone
  # com.dotfiles.cleanup LaunchAgent used to do. Topgrade's --cleanup
  # flag covers those managers; the dotfiles-specific cleanups run
  # via [post_commands] (see test above).
  grep -q -- '--cleanup' "$SCRIPT"
}

# ── OpenCode step leaves the managed zshrc alone (#260) ──────────────
# topgrade's OpenCode step runs `opencode upgrade`, which re-runs the
# OpenCode install script. That script appends `# opencode` and an
# `export PATH=<home>/.opencode/bin:$PATH` line to ${ZDOTDIR:-$HOME}/.zshrc
# unless ~/.opencode/bin is already on PATH. ~/.zshrc links to the tracked
# home/zshrc, so the append dirties the repo. This topgrade stub copies the
# install script's rule (its add_to_path block), so no real upgrade runs.
_opencode_installer_stub() {
  cat > "$TEST_BIN/topgrade" <<'STUB'
#!/bin/bash
install_dir="$HOME/.opencode/bin"
if [[ ":$PATH:" != *":$install_dir:"* ]]; then
  printf '\n# opencode\nexport PATH=%s:$PATH\n' "$install_dir" >> "${ZDOTDIR:-$HOME}/.zshrc"
fi
echo "[topgrade-stub] PATH=$PATH"
STUB
  chmod +x "$TEST_BIN/topgrade"
  mkdir -p "$TEST_DIR/repo/home"
  printf '# managed zshrc\n' > "$TEST_DIR/repo/home/zshrc"
  ln -s "$TEST_DIR/repo/home/zshrc" "$TEST_HOME/.zshrc"
}

@test "OpenCode upgrade step does not edit the managed zshrc" {
  _opencode_installer_stub
  mkdir -p "$TEST_HOME/.opencode/bin"

  run "$SCRIPT" --yes

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_DIR/repo/home/zshrc")" = "# managed zshrc" ]
}

@test "wrapper adds ~/.opencode/bin to PATH only when it exists" {
  _opencode_installer_stub

  run "$SCRIPT" --yes

  [ "$status" -eq 0 ]
  [[ "$output" == *"[topgrade-stub] PATH="* ]]
  [[ "$output" != *".opencode/bin"* ]]
}

@test "without a terminal and without --yes it refuses before topgrade runs" {
  run "$SCRIPT" < /dev/null
  [ "$status" -eq 2 ]
  [[ "$output" == *"--yes"* ]]
  [[ "$output" != *"[topgrade-stub]"* ]]
  [ ! -f "$TEST_HOME/.local/share/dotfiles/last-upgrade" ]
}

@test "--node asks too, and --dry-run needs no yes" {
  run "$SCRIPT" --node 24 < /dev/null
  [ "$status" -eq 2 ]
  run "$SCRIPT" --dry-run < /dev/null
  [ "$status" -eq 0 ]
}

@test "the weekly LaunchAgent passes --yes: auto_upgrade is the owner's yes" {
  local plist="$BATS_TEST_DIRNAME/../launchagents/com.dotfiles.dotfiles-upgrade.plist.tmpl"
  grep -A1 'bin/dotfiles-upgrade</string>' "$plist" | grep -q '<string>--yes</string>'
}

@test "--yes --help prints the help and upgrades nothing" {
  run "$SCRIPT" --yes --help < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" != *"[topgrade-stub]"* ]]
  [ ! -f "$TEST_HOME/.local/share/dotfiles/last-upgrade" ]
}

# ── updates-landed record (#301 follow-up) ──────────────────────────────
# A brew stub whose `list --versions` reads a file; the topgrade stub can
# move a version during the run.
nudge_stubs() {
  printf 'foo 1.0\nbar 2.0\n' > "$TEST_DIR/formulae"
  : > "$TEST_DIR/casks"
  cat > "$TEST_BIN/brew" <<EOF2
#!/bin/bash
case "\$*" in
  "list --formula --versions") cat "$TEST_DIR/formulae" ;;
  "list --cask --versions") cat "$TEST_DIR/casks" ;;
esac
exit 0
EOF2
  cat > "$TEST_BIN/topgrade" <<EOF2
#!/bin/bash
[ -z "\${MOVE_VERSION:-}" ] || printf 'foo 1.1\nbar 2.0\nnew 0.1\n' > "$TEST_DIR/formulae"
exit 0
EOF2
  chmod +x "$TEST_BIN/brew" "$TEST_BIN/topgrade"
  RECORD="$HOME/.local/state/dotfiles/updates-landed.tsv"
}

@test "an upgrade that changed nothing records nothing, so the nudge stays quiet" {
  nudge_stubs
  run "$SCRIPT" --yes
  echo "$output"
  [ "$status" -eq 0 ]
  [ ! -s "$RECORD" ]
}

@test "an upgrade that moved package versions records a short summary of them" {
  nudge_stubs
  MOVE_VERSION=1 run "$SCRIPT" --yes
  echo "$output"
  [ "$status" -eq 0 ]
  cat "$RECORD"
  grep -q $'\tdotfiles-upgrade\t2 Homebrew package(s): foo 1.0 → 1.1, new 0.1 (new)' "$RECORD"
}
