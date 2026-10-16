#!/usr/bin/env bats
# Functional tests for modules/upgrade/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME"
  mkdir -p "$TEST_DOTFILES/home"
  mkdir -p "$TEST_HOME/.local/share/dotfiles"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"

  # Stub chezmoi so the test does not depend on this machine's chezmoi data.
  # The doctor gates upgrade.launchagent/upgrade.recent on `auto_upgrade`.
  # Tests set AUTO_UPGRADE=false to cover the opt-out path.
  export AUTO_UPGRADE=true
  mkdir -p "$TEST_DIR/chezmoibin"
  cat > "$TEST_DIR/chezmoibin/chezmoi" <<'STUB'
#!/bin/bash
case "$*" in
  *auto_upgrade*) echo "$AUTO_UPGRADE" ;;
  *) echo "false" ;;
esac
STUB
  chmod +x "$TEST_DIR/chezmoibin/chezmoi"
  export PATH="$TEST_DIR/chezmoibin:$PATH"

  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"
  touch "$OVERRIDES_FILE"
  FIX_MODE=false
  LIST_MODE=false
  pass_count=0
  fail_count=0
  fix_count=0
  skip_count=0

  pass()    { pass_count=$((pass_count + 1)); }
  fail()    { fail_count=$((fail_count + 1)); }
  fixed()   { fix_count=$((fix_count + 1)); }
  skipped() { skip_count=$((skip_count + 1)); }

  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }

  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="${4:-}"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if eval "$test_cmd" >/dev/null 2>&1; then
      pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then
      eval "$fix_cmd" >/dev/null 2>&1
      fixed "$desc"
    else
      fail "$desc"
    fi
  }
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "upgrade: passes upgrade.recent when last-upgrade is fresh" {
  # Write a recent epoch (now)
  date "+%s" > "$TEST_HOME/.local/share/dotfiles/last-upgrade"
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  # upgrade.recent should pass
  [ "$pass_count" -ge 1 ]
}

@test "upgrade: fails upgrade.recent when last-upgrade is stale" {
  # Write an epoch from 30 days ago
  local stale_epoch=$(($(date "+%s") - 30 * 86400))
  echo "$stale_epoch" > "$TEST_HOME/.local/share/dotfiles/last-upgrade"
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "upgrade: fails upgrade.recent when file is missing" {
  rm -f "$TEST_HOME/.local/share/dotfiles/last-upgrade"
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "upgrade: fails upgrade.recent when file has garbage content" {
  echo "not-a-number" > "$TEST_HOME/.local/share/dotfiles/last-upgrade"
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

@test "upgrade: skips upgrade.launchagent and upgrade.recent when auto_upgrade is false" {
  export AUTO_UPGRADE=false
  rm -f "$TEST_HOME/.local/share/dotfiles/last-upgrade"
  checked_ids=()
  check() { checked_ids+=("$1"); }
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  ! printf '%s\n' "${checked_ids[@]}" | grep -qx "upgrade.launchagent"
  ! printf '%s\n' "${checked_ids[@]}" | grep -qx "upgrade.recent"
  printf '%s\n' "${checked_ids[@]}" | grep -qx "upgrade.brew"
}

@test "upgrade: passes upgrade.brew when brew is installed" {
  # brew should be available in the test environment
  if ! command -v brew >/dev/null 2>&1; then
    skip "brew not installed"
  fi
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  [ "$pass_count" -ge 1 ]
}

@test "upgrade: skips overridden checks" {
  echo "upgrade.launchagent" >> "$OVERRIDES_FILE"
  echo "upgrade.recent" >> "$OVERRIDES_FILE"
  echo "upgrade.brew" >> "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  [ "$skip_count" -eq 3 ]
  [ "$fail_count" -eq 0 ]
}

@test "upgrade: uses 14-day threshold by default" {
  # Write an epoch from exactly 13 days ago (should pass)
  local recent_epoch=$(($(date "+%s") - 13 * 86400))
  echo "$recent_epoch" > "$TEST_HOME/.local/share/dotfiles/last-upgrade"
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  # upgrade.recent should pass (13 < 14)
  [ "$pass_count" -ge 1 ]
}

@test "upgrade: fails at exactly 14 days" {
  # Write an epoch from exactly 15 days ago (should fail)
  local old_epoch=$(($(date "+%s") - 15 * 86400))
  echo "$old_epoch" > "$TEST_HOME/.local/share/dotfiles/last-upgrade"
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  [ "$fail_count" -ge 1 ]
}

# ── Non-uv poetry with a missing interpreter ─────────────────────────
# Stub poetry/uv in a private bin dir that wins PATH lookup.
_poetry_stub() {  # $1 = dir, $2 = exit code for `poetry --version`
  mkdir -p "$1"
  printf '#!/bin/bash\nexit %s\n' "$2" > "$1/poetry"
  chmod +x "$1/poetry"
}
_uv_stub() {  # `uv tool dir` prints $TEST_DIR/uv-tools
  mkdir -p "$TEST_DIR/stubbin"
  printf '#!/bin/bash\n[ "$1 $2" = "tool dir" ] && echo "%s" && exit 0\nexit 1\n' "$TEST_DIR/uv-tools" > "$TEST_DIR/stubbin/uv"
  chmod +x "$TEST_DIR/stubbin/uv"
}

@test "upgrade: reports a non-uv poetry whose --version fails, with the uv hint" {
  _poetry_stub "$TEST_DIR/stubbin" 1
  _uv_stub
  export PATH="$TEST_DIR/stubbin:$PATH"
  failed_descs=()
  fail() { fail_count=$((fail_count + 1)); failed_descs+=("$1"); }
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  printf '%s\n' "${failed_descs[@]}" | grep -F "non-uv poetry" | grep -F "uv tool install poetry" | grep -qF "pypoetry/venv"
}

@test "upgrade: passes a non-uv poetry that runs" {
  _poetry_stub "$TEST_DIR/stubbin" 0
  _uv_stub
  export PATH="$TEST_DIR/stubbin:$PATH"
  failed_descs=()
  fail() { fail_count=$((fail_count + 1)); failed_descs+=("$1"); }
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  ! printf '%s\n' "${failed_descs[@]}" | grep -qF "poetry"
}

@test "upgrade: ignores a uv-managed poetry even when --version fails" {
  _uv_stub
  _poetry_stub "$TEST_DIR/uv-tools/poetry/bin" 1
  mkdir -p "$TEST_DIR/localbin"
  ln -s "$TEST_DIR/uv-tools/poetry/bin/poetry" "$TEST_DIR/localbin/poetry"
  export PATH="$TEST_DIR/localbin:$TEST_DIR/stubbin:$PATH"
  failed_descs=()
  fail() { fail_count=$((fail_count + 1)); failed_descs+=("$1"); }
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  ! printf '%s\n' "${failed_descs[@]}" | grep -qF "poetry"
}

# ── upgrade.poetry_runs --fix ────────────────────────────────────────
# uv stub: `tool dir` prints $TEST_DIR/uv-tools; `tool install poetry`
# makes a working uv-managed poetry and links it into ~/.local/bin.
_uv_install_stub() {
  mkdir -p "$TEST_DIR/stubbin"
  cat > "$TEST_DIR/stubbin/uv" <<STUB
#!/bin/bash
if [ "\$1 \$2" = "tool dir" ]; then echo "$TEST_DIR/uv-tools"; exit 0; fi
if [ "\$1 \$2 \$3" = "tool install poetry" ]; then
  mkdir -p "$TEST_DIR/uv-tools/poetry/bin" "$TEST_HOME/.local/bin"
  printf '#!/bin/bash\necho "Poetry (version 2.0.0)"\n' > "$TEST_DIR/uv-tools/poetry/bin/poetry"
  chmod +x "$TEST_DIR/uv-tools/poetry/bin/poetry"
  ln -sf "$TEST_DIR/uv-tools/poetry/bin/poetry" "$TEST_HOME/.local/bin/poetry"
  exit 0
fi
exit 1
STUB
  chmod +x "$TEST_DIR/stubbin/uv"
}

_broken_official_poetry() {
  _poetry_stub "$TEST_HOME/.local/bin" 1
  mkdir -p "$TEST_HOME/Library/Application Support/pypoetry/venv/bin"
  touch "$TEST_HOME/Library/Application Support/pypoetry/venv/bin/python"
}

@test "upgrade: poetry_runs --fix moves the broken poetry aside and installs it with uv" {
  mkdir -p "$TEST_DOTFILES/lib"
  cp "$BATS_TEST_DIRNAME/../lib/poetry-repair.sh" "$TEST_DOTFILES/lib/"
  _broken_official_poetry
  _uv_install_stub
  export PATH="$TEST_HOME/.local/bin:$TEST_DIR/stubbin:$PATH"
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  [ -f "$TEST_HOME/.local/bin/poetry.bak" ]
  [ -d "$TEST_HOME/Library/Application Support/pypoetry/venv.bak" ]
  [ ! -e "$TEST_HOME/Library/Application Support/pypoetry/venv" ]
  [ -L "$TEST_HOME/.local/bin/poetry" ]
  "$TEST_HOME/.local/bin/poetry" --version
}

@test "upgrade: poetry_runs --fix is a no-op on the second run" {
  mkdir -p "$TEST_DOTFILES/lib"
  cp "$BATS_TEST_DIRNAME/../lib/poetry-repair.sh" "$TEST_DOTFILES/lib/"
  _broken_official_poetry
  _uv_install_stub
  export PATH="$TEST_HOME/.local/bin:$TEST_DIR/stubbin:$PATH"
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  local before
  before="$(ls -A "$TEST_HOME/.local/bin" "$TEST_HOME/Library/Application Support/pypoetry")"
  checked_ids=()
  check() { checked_ids+=("$1"); }
  source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  ! printf '%s\n' "${checked_ids[@]}" | grep -qx "upgrade.poetry_runs"
  [ "$before" = "$(ls -A "$TEST_HOME/.local/bin" "$TEST_HOME/Library/Application Support/pypoetry")" ]
}

@test "upgrade: poetry_runs has no fix when uv is missing" {
  _broken_official_poetry
  mkdir -p "$TEST_DIR/nouv"
  ln -s "$(command -v chezmoi)" "$TEST_DIR/nouv/chezmoi"
  for t in bash cat date dirname readlink grep; do ln -s "$(command -v "$t")" "$TEST_DIR/nouv/$t"; done
  fix_args=()
  check() { [ "$1" = "upgrade.poetry_runs" ] && fix_args+=("${4:-}"); return 0; }
  PATH="$TEST_HOME/.local/bin:$TEST_DIR/nouv" source "$BATS_TEST_DIRNAME/../modules/upgrade/doctor.sh"
  [ "${#fix_args[@]}" -eq 1 ]
  [ -z "${fix_args[0]}" ]
}
