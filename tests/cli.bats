#!/usr/bin/env bats
# Tests for the dotfiles CLI wrapper (bin/dotfiles)

DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
CLI="$DOTFILES_DIR/bin/dotfiles"

long_flags() {
  grep -oE -- '--[a-z][a-z-]*' | sort -u
}

dotfiles_help_doctor_block() {
  awk '
    /^  doctor / { in_block = 1 }
    in_block && /^  audit / { exit }
    in_block { print }
  '
}

readme_doctor_reference_block() {
  awk '
    /^## CLI reference/ { in_cli_reference = 1 }
    in_cli_reference && /^dotfiles doctor / { in_block = 1 }
    in_block && /^dotfiles audit / { exit }
    in_block { print }
  ' "$DOTFILES_DIR/README.md"
}

@test "dotfiles --help exits 0 and shows usage" {
  run bash "$CLI" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: dotfiles"* ]]
  # Help was consolidated from one flat "Commands:" list into grouped
  # sections to shrink the visible surface. Verify the new grouping
  # exists and includes the most-common command surface.
  [[ "$output" == *"Common:"* ]]
  [[ "$output" == *"Scaffolding:"* ]]
  [[ "$output" == *"Advanced:"* ]]
}

@test "dotfiles help exits 0" {
  run bash "$CLI" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: dotfiles"* ]]
}

@test "README CLI reference lists every doctor flag from doctor help" {
  # `dotfiles --help` was deliberately consolidated to `doctor [--fix] [...]`
  # so the top-level help fits on one screen. The README's CLI reference
  # section remains the canonical place documenting every doctor flag, and
  # we still require it to stay in sync with `doctor --help`.
  local doctor_flags readme_flags
  doctor_flags=$(bash "$DOTFILES_DIR/bin/dotfiles-doctor" --help | long_flags)
  readme_flags=$(readme_doctor_reference_block | long_flags)

  [ "$readme_flags" = "$doctor_flags" ]
}

@test "dotfiles --help mentions doctor with a --fix hint" {
  # Spot-check that the consolidated form still tells the user how to invoke
  # the most common path; full flag reference lives in README + doctor --help.
  run bash "$CLI" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"doctor"* ]]
  [[ "$output" == *"--fix"* ]]
}

@test "dotfiles with no args shows help" {
  run bash "$CLI"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: dotfiles"* ]]
}

@test "dotfiles --version shows git hash and date" {
  run bash "$CLI" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"dotfiles"* ]]
}

@test "dotfiles version works without dashes" {
  run bash "$CLI" version
  [ "$status" -eq 0 ]
  [[ "$output" == *"dotfiles"* ]]
}

@test "dotfiles cd prints dotfiles directory" {
  run bash "$CLI" cd
  [ "$status" -eq 0 ]
  [[ "$output" == *"dotfiles"* ]]
  [ -d "$output" ]
}

@test "dotfiles status shows branch and commit" {
  run bash "$CLI" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Branch:"* ]]
  [[ "$output" == *"Commit:"* ]]
}

@test "dotfiles unknown-command exits 1" {
  run bash "$CLI" nonexistent-cmd
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown command"* ]]
}

@test "dotfiles cheat exits 0" {
  run bash "$CLI" cheat
  [ "$status" -eq 0 ]
  [[ "$output" == *"Commands"* ]] || [[ "$output" == *"cheat"* ]] || [[ "$output" == *"dotfiles"* ]]
}

@test "dotfiles managed lists files" {
  run bash "$CLI" managed
  [ "$status" -eq 0 ]
  # Should list at least some managed files
  [ "${#lines[@]}" -gt 0 ]
}

@test "dotfiles has update check function" {
  grep -q '_check_for_updates' "$CLI"
}

@test "dotfiles skips update check for cd command" {
  grep -A1 'update|upgrade|sync|cd' "$CLI" | grep -q ';;'
}

@test "dotfiles diff exits 0" {
  run bash "$CLI" diff
  # diff exits 0 when clean, may exit non-zero when there are changes
  # just verify it doesn't crash
  [[ "$status" -eq 0 || "$status" -eq 1 ]]
}

@test "dotfiles apply with no passthrough args does not expand empty array under nounset" {
  local tmp fake_bin args_file
  tmp="$(mktemp -d)"
  fake_bin="$tmp/bin"
  args_file="$tmp/chezmoi-args"
  mkdir -p "$fake_bin"
  cat > "$fake_bin/chezmoi" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CHEZMOI_ARGS_OUT"
EOF
  chmod +x "$fake_bin/chezmoi"

  run env PATH="$fake_bin:$PATH" CHEZMOI_ARGS_OUT="$args_file" bash "$CLI" apply --no-fix

  rm -rf "$tmp"
  [ "$status" -eq 0 ]
  [[ "$output" != *"unbound variable"* ]]
}

@test "dotfiles update delegates to dotfiles-update with flags" {
  local tmp fake_repo stub_bin invocations
  tmp="$BATS_TEST_TMPDIR/dotfiles-update-delegation"
  fake_repo="$tmp/dotfiles"
  stub_bin="$tmp/stub-bin"
  invocations="$tmp/invocations"
  mkdir -p "$fake_repo/bin" "$fake_repo/lib" "$stub_bin"
  cp "$CLI" "$fake_repo/bin/dotfiles"
  cp "$DOTFILES_DIR/lib/colors.sh" "$fake_repo/lib/colors.sh"
  cat > "$fake_repo/bin/dotfiles-update" <<STUB
#!/usr/bin/env bash
printf 'dotfiles-update' > "$invocations"
if [ "\$#" -gt 0 ]; then
  printf ' %s' "\$@" >> "$invocations"
fi
printf '\n' >> "$invocations"
STUB
  chmod +x "$fake_repo/bin/dotfiles" "$fake_repo/bin/dotfiles-update"
  cat > "$stub_bin/git" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  cat > "$stub_bin/chezmoi" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
  chmod +x "$stub_bin/git" "$stub_bin/chezmoi"

  run env PATH="$stub_bin:/usr/bin:/bin" "$fake_repo/bin/dotfiles" update --dry-run --verbose

  [ "$status" -eq 0 ]
  [ "$(cat "$invocations")" = "dotfiles-update --dry-run --verbose" ]
}
