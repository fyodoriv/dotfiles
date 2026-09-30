#!/usr/bin/env bats
# Stale-symlink-after-relocation check — defends against the
# 2026-05-15 silent breakage when the dotfiles repo moved from
# `~/apps/dotfiles` to `~/apps/tooling/dotfiles`. Every chezmoi-managed
# symlink (~/.zshrc, ~/.gitconfig, ~/.zshenv, …) still pointed at the
# old gone path; doctor had no check that caught it.
#
# Test strategy: replicate the helper logic (`_chezmoi_broken_managed_symlinks`)
# from modules/chezmoi/doctor.sh and exercise it against synthetic
# `chezmoi managed` output produced by a stub `chezmoi` binary on PATH.
# The bats test does NOT override $HOME — that triggered a Python+macOS
# pipx hang in tests/module-local-ai-opencode-mcp-format.bats (now
# documented in that file's header). Instead the helper takes the
# chezmoi-output path explicitly, and the test wires the stub via PATH.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  STUB_DIR="$TEST_DIR/stubs"
  mkdir -p "$STUB_DIR"

  # Synthetic targets — some valid, some broken
  mkdir -p "$TEST_DIR/files"
  touch "$TEST_DIR/files/realfile"

  # Build the managed-symlinks list. The stub `chezmoi` binary reads
  # this file when invoked with `managed --include=symlinks ...`.
  MANAGED_LIST="$TEST_DIR/managed.txt"

  # Stub chezmoi binary: implements just enough of `chezmoi managed
  # --path-style=absolute --include=symlinks` for the test. Other
  # invocations (apply, version) are no-ops so the helper's "is chezmoi
  # available" precheck passes.
  cat > "$STUB_DIR/chezmoi" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"managed --path-style=absolute --include=symlinks"*) cat "$MANAGED_LIST" ;;
  *"--version"*) echo "stub chezmoi 0.0.0" ;;
  *"apply"*) echo "stub: would apply" ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$STUB_DIR/chezmoi"

  # Helper under test — copy of the production logic from
  # modules/chezmoi/doctor.sh::_chezmoi_broken_managed_symlinks.
  _chezmoi_broken_managed_symlinks() {
    local -a broken=()
    local managed
    while IFS= read -r managed; do
      [ -z "$managed" ] && continue
      if [ -L "$managed" ] && [ ! -e "$managed" ]; then
        broken+=("$managed")
      fi
    done < <(PATH="$STUB_DIR:$PATH" chezmoi managed --path-style=absolute --include=symlinks 2>/dev/null)
    if [ "${#broken[@]}" -gt 0 ]; then
      printf '%s\n' "${broken[@]}"
      return 1
    fi
    return 0
  }
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "passes when chezmoi reports no managed symlinks" {
  : > "$MANAGED_LIST"
  _chezmoi_broken_managed_symlinks
}

@test "passes when all managed symlinks resolve to existing targets" {
  ln -s "$TEST_DIR/files/realfile" "$TEST_DIR/files/symlink-good-1"
  ln -s "$TEST_DIR/files/realfile" "$TEST_DIR/files/symlink-good-2"
  cat > "$MANAGED_LIST" <<EOF
$TEST_DIR/files/symlink-good-1
$TEST_DIR/files/symlink-good-2
EOF
  _chezmoi_broken_managed_symlinks
}

@test "fails when a managed symlink points to a non-existent target (relocation scenario)" {
  # Synthesize the exact 2026-05-15 breakage: a symlink at the home dir
  # pointing at an old dotfiles path that no longer exists.
  ln -s "$TEST_DIR/never-was/zshrc" "$TEST_DIR/files/symlink-broken"
  cat > "$MANAGED_LIST" <<EOF
$TEST_DIR/files/symlink-broken
EOF

  run _chezmoi_broken_managed_symlinks
  [ "$status" -ne 0 ]
  [[ "$output" == *"symlink-broken"* ]]
}

@test "fails and lists ALL broken symlinks when multiple are stale" {
  ln -s "$TEST_DIR/gone/a" "$TEST_DIR/files/sl-a"
  ln -s "$TEST_DIR/gone/b" "$TEST_DIR/files/sl-b"
  ln -s "$TEST_DIR/files/realfile" "$TEST_DIR/files/sl-ok"
  cat > "$MANAGED_LIST" <<EOF
$TEST_DIR/files/sl-a
$TEST_DIR/files/sl-b
$TEST_DIR/files/sl-ok
EOF

  run _chezmoi_broken_managed_symlinks
  [ "$status" -ne 0 ]
  # Both broken entries are listed
  [[ "$output" == *"sl-a"* ]]
  [[ "$output" == *"sl-b"* ]]
  # The healthy one is NOT in the broken list
  [[ "$output" != *"sl-ok"* ]]
}

@test "passes when a managed entry is not a symlink at all (regular file or dir)" {
  # chezmoi `managed --include=symlinks` should only emit symlinks, but
  # we defensively gate on `[ -L "$path" ]` in case the filter ever
  # widens or someone runs without --include=symlinks. Make sure a
  # regular file in the list doesn't trip a false positive.
  cat > "$MANAGED_LIST" <<EOF
$TEST_DIR/files/realfile
EOF
  _chezmoi_broken_managed_symlinks
}

@test "passes when chezmoi managed lists a path that doesn't exist on disk at all" {
  # Defensive: if `chezmoi managed` lists something we haven't even
  # touched yet (race condition during sync), [ -L ] returns false and
  # the entry is correctly ignored — not a "broken symlink".
  cat > "$MANAGED_LIST" <<EOF
$TEST_DIR/files/never-created-on-disk
EOF
  _chezmoi_broken_managed_symlinks
}
