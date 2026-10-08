#!/usr/bin/env bats
# Behaviour tests for .chezmoiscripts/run_after_uv-tools.sh.

setup() {
  fake_bin="$BATS_TEST_TMPDIR/fakebin"
  uv_bin="$BATS_TEST_TMPDIR/home/.local/bin"
  uv_tools="$BATS_TEST_TMPDIR/home/.local/share/uv/tools"
  calls="$BATS_TEST_TMPDIR/uv-calls"
  mkdir -p "$fake_bin" "$uv_bin" "$uv_tools" "$BATS_TEST_TMPDIR/src"
  : >"$calls"
  # Stub uv: no tools installed; `install` fails like real uv when a
  # non-uv executable already owns the name, unless --force is passed.
  cat >"$fake_bin/uv" <<EOF
#!/bin/bash
echo "\$*" >>"$calls"
case "\$1 \$2" in
  "tool list") exit 0 ;;
  "tool dir")
    if [ "\${3:-}" = "--bin" ]; then echo "$uv_bin"; else echo "$uv_tools"; fi
    exit 0 ;;
  "tool install")
    shift 2
    force=false; tool=""
    for a in "\$@"; do [ "\$a" = "--force" ] && force=true || tool="\$a"; done
    if [ -e "$uv_bin/\$tool" ] || [ -L "$uv_bin/\$tool" ]; then
      \$force || { echo "error: Executable already exists: \$tool (use \\\`--force\\\` to overwrite)" >&2; exit 2; }
    fi
    exit 0 ;;
esac
exit 0
EOF
  chmod +x "$fake_bin/uv"
}

run_uv_tools() {
  # CHEZMOI_SOURCE_DIR points at an empty dir, so the managed-endpoint
  # library is absent and installs are allowed.
  run env PATH="$fake_bin:/usr/bin:/bin" HOME="$BATS_TEST_TMPDIR/home" \
    CHEZMOI_SOURCE_DIR="$BATS_TEST_TMPDIR/src" \
    bash .chezmoiscripts/run_after_uv-tools.sh
}

@test "uv-tools skips a tool another installer already provides" {
  mkdir -p "$BATS_TEST_TMPDIR/pypoetry/bin"
  printf '#!/bin/sh\n' >"$BATS_TEST_TMPDIR/pypoetry/bin/poetry"
  chmod +x "$BATS_TEST_TMPDIR/pypoetry/bin/poetry"
  ln -s "$BATS_TEST_TMPDIR/pypoetry/bin/poetry" "$uv_bin/poetry"

  run_uv_tools

  [ "$status" -eq 0 ]
  [[ "$output" != *"failed"* ]]
  [[ "$output" == *"poetry already provided by"* ]]
  ! grep -q '^tool install.*poetry' "$calls"
  # The other installer's executable is untouched.
  [ "$(readlink "$uv_bin/poetry")" = "$BATS_TEST_TMPDIR/pypoetry/bin/poetry" ]
  # Tools with no collision still install.
  grep -q '^tool install jrnl$' "$calls"
}

@test "uv-tools reinstalls over a stale uv-managed shim" {
  ln -s "$uv_tools/poetry/bin/poetry" "$uv_bin/poetry"

  run_uv_tools

  [ "$status" -eq 0 ]
  [[ "$output" != *"failed"* ]]
  grep -q '^tool install --force poetry$' "$calls"
}

@test "uv-tools installs a tool with no existing executable" {
  run_uv_tools

  [ "$status" -eq 0 ]
  grep -q '^tool install poetry$' "$calls"
  [[ "$output" == *"uv-managed CLI tools up to date"* ]]
}
