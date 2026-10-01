#!/usr/bin/env bats
# check_symlink --fix must replace a stale symlink in place. Backing up the
# old link as `<dst>.backup` leaves a dangling link once its old target goes.

REPO_ROOT="$BATS_TEST_DIRNAME/.."

setup() {
  TEST_DIR="$(mktemp -d)"
  mkdir -p "$TEST_DIR/old" "$TEST_DIR/new" "$TEST_DIR/extra/relink-module"
  echo old > "$TEST_DIR/old/rc"
  echo new > "$TEST_DIR/new/rc"
  DST="$TEST_DIR/home-rc"
  cat > "$TEST_DIR/extra/relink-module/doctor.sh" <<DOCTOR
check_symlink "relink-module.rc" "$TEST_DIR/new/rc" "$DST"
DOCTOR
  export EXTRA_DOCTOR_DIR="$TEST_DIR/extra"
  # --fix only acts from the chezmoi source checkout, so report this repo as it.
  mkdir -p "$TEST_DIR/bin"
  cat > "$TEST_DIR/bin/chezmoi" <<STUB
#!/usr/bin/env bash
[ "\$1" = source-path ] && echo "$REPO_ROOT"
STUB
  chmod +x "$TEST_DIR/bin/chezmoi"
  export PATH="$TEST_DIR/bin:$PATH"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "symlink relink: stale symlink is replaced without a .backup link" {
  ln -s "$TEST_DIR/old/rc" "$DST"
  "$REPO_ROOT/bin/dotfiles-doctor" --module relink-module --fix >/dev/null 2>&1 || true
  [ "$(readlink "$DST")" = "$TEST_DIR/new/rc" ]
  [ ! -e "$DST.backup" ] && [ ! -L "$DST.backup" ]
}

@test "symlink relink: regular file is still backed up before linking" {
  echo mine > "$DST"
  "$REPO_ROOT/bin/dotfiles-doctor" --module relink-module --fix >/dev/null 2>&1 || true
  [ "$(readlink "$DST")" = "$TEST_DIR/new/rc" ]
  [ "$(cat "$DST.backup")" = "mine" ]
}
