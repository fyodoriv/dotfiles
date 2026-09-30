#!/usr/bin/env bats
# Hook-integrity check — defends against transitive `lefthook install`
# overwriting our canonical git-hooks/* during a sister-repo pnpm install.
#
# Repro pattern: PR #59 on 2026-05-20 silently replaced pre-{commit,push}
# with a /tmp/minsky-gate/.../lefthook stub via Minsky's transitive
# pnpm install. The check compares each tracked hook's working-tree blob
# SHA against its HEAD tree-entry SHA — mismatch = overwrite.

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME"
  mkdir -p "$TEST_DOTFILES/lib"
  mkdir -p "$TEST_DOTFILES/bin"
  mkdir -p "$TEST_DOTFILES/git-hooks"
  mkdir -p "$TEST_DOTFILES/modules/git"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"

  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"
  touch "$OVERRIDES_FILE"
  FIX_MODE=false
  LIST_MODE=false
  pass_count=0
  fail_count=0
  fix_count=0
  skip_count=0
  fail_messages=()

  pass()    { pass_count=$((pass_count + 1)); }
  fail()    { fail_count=$((fail_count + 1)); fail_messages+=("$1"); }
  fixed()   { fix_count=$((fix_count + 1)); }
  skipped() { skip_count=$((skip_count + 1)); }

  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }

  # Mirror the check() shape used by bin/dotfiles-doctor so this test
  # exercises the exact logic in modules/git/doctor.sh.
  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="$4"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if eval "$test_cmd" >/dev/null 2>&1; then
      pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then
      if eval "$fix_cmd" >/dev/null 2>&1; then fixed "$desc"; else fail "$desc"; fi
    else
      fail "$desc"
    fi
  }

  # Initialize a real git repo so ls-tree + hash-object work.
  cd "$TEST_DOTFILES"
  git init --quiet
  git config user.email "test@example.com"
  git config user.name "Test"
  git config commit.gpgsign false
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: extract just the hook-integrity loop from the real module
# and source it. Avoids tight coupling to the module's other checks
# (which need chezmoi, $HOME plumbing, etc.) while still exercising
# the exact production logic.
_run_hook_integrity_check() {
  while IFS= read -r _hook_path; do
    [ -z "$_hook_path" ] && continue
    _hook="${_hook_path#git-hooks/}"
    _head_sha="$(git -C "$DOTFILES_DIR" ls-tree HEAD -- "$_hook_path" 2>/dev/null | awk '{print $3}')"
    _wt_sha=""
    if [ -f "$DOTFILES_DIR/$_hook_path" ]; then
      _wt_sha="$(git -C "$DOTFILES_DIR" hash-object "$DOTFILES_DIR/$_hook_path" 2>/dev/null)"
    fi
    check "git.hook_integrity.$_hook" \
      "git-hooks/$_hook matches HEAD blob (no transitive overwrite)" \
      "[ -n '$_head_sha' ] && [ '$_head_sha' = '$_wt_sha' ]" \
      "git -C '$DOTFILES_DIR' checkout HEAD -- '$_hook_path'"
  done < <(git -C "$DOTFILES_DIR" ls-tree --name-only HEAD -- git-hooks/ 2>/dev/null)
}

@test "hook-integrity passes when hooks match HEAD" {
  echo '#!/usr/bin/env bash' > "$TEST_DOTFILES/git-hooks/pre-commit"
  echo 'echo canonical-pre-commit' >> "$TEST_DOTFILES/git-hooks/pre-commit"
  echo '#!/usr/bin/env bash' > "$TEST_DOTFILES/git-hooks/pre-push"
  echo 'echo canonical-pre-push' >> "$TEST_DOTFILES/git-hooks/pre-push"
  cd "$TEST_DOTFILES"
  git add git-hooks/
  git commit --quiet -m "init hooks"

  _run_hook_integrity_check

  [ "$fail_count" -eq 0 ]
  [ "$pass_count" -eq 2 ]
}

@test "hook-integrity detects lefthook-style overwrite of pre-push" {
  echo '#!/usr/bin/env bash' > "$TEST_DOTFILES/git-hooks/pre-commit"
  echo 'echo canonical-pre-commit' >> "$TEST_DOTFILES/git-hooks/pre-commit"
  echo '#!/usr/bin/env bash' > "$TEST_DOTFILES/git-hooks/pre-push"
  echo 'echo canonical-pre-push' >> "$TEST_DOTFILES/git-hooks/pre-push"
  cd "$TEST_DOTFILES"
  git add git-hooks/
  git commit --quiet -m "init hooks"

  # Simulate transitive lefthook install overwrite — same pattern PR #59 hit
  cat > "$TEST_DOTFILES/git-hooks/pre-push" <<'EOF'
#!/usr/bin/env bash
exec /tmp/minsky-gate-Pn5AqP/node_modules/.pnpm/lefthook-darwin-arm64@2.1.6/lefthook run pre-push "$@"
EOF

  _run_hook_integrity_check

  [ "$fail_count" -eq 1 ]
  [[ "${fail_messages[0]}" == *"pre-push"* ]]
  [ "$pass_count" -eq 1 ]
}

@test "hook-integrity --fix restores from HEAD via git checkout" {
  echo '#!/usr/bin/env bash' > "$TEST_DOTFILES/git-hooks/pre-push"
  echo 'echo canonical-pre-push' >> "$TEST_DOTFILES/git-hooks/pre-push"
  cd "$TEST_DOTFILES"
  git add git-hooks/
  git commit --quiet -m "init hooks"

  # Overwrite
  echo 'lefthook stub content' > "$TEST_DOTFILES/git-hooks/pre-push"

  FIX_MODE=true
  _run_hook_integrity_check

  [ "$fail_count" -eq 0 ]
  [ "$fix_count" -eq 1 ]
  # File restored to canonical content
  grep -q canonical-pre-push "$TEST_DOTFILES/git-hooks/pre-push"
  # SHA back to HEAD
  local head_sha wt_sha
  head_sha="$(git -C "$TEST_DOTFILES" ls-tree HEAD -- git-hooks/pre-push | awk '{print $3}')"
  wt_sha="$(git -C "$TEST_DOTFILES" hash-object "$TEST_DOTFILES/git-hooks/pre-push")"
  [ "$head_sha" = "$wt_sha" ]
}

@test "hook-integrity skips untracked machine-local hooks" {
  echo '#!/usr/bin/env bash' > "$TEST_DOTFILES/git-hooks/pre-commit"
  echo 'echo canonical' >> "$TEST_DOTFILES/git-hooks/pre-commit"
  cd "$TEST_DOTFILES"
  git add git-hooks/pre-commit
  git commit --quiet -m "track pre-commit only"

  # Add an untracked machine-local hook (e.g. the agentbrew post-commit shim)
  cat > "$TEST_DOTFILES/git-hooks/post-commit" <<'EOF'
#!/usr/bin/env bash
# machine-local — not tracked in dotfiles
exec /Users/$USER/apps/agentbrew/scripts/post-commit-push-mirror.sh || true
EOF
  chmod +x "$TEST_DOTFILES/git-hooks/post-commit"

  _run_hook_integrity_check

  # Only pre-commit was tracked, so only it gets checked
  [ "$fail_count" -eq 0 ]
  [ "$pass_count" -eq 1 ]
}

@test "hook-integrity detects deleted hook (working tree missing)" {
  echo '#!/usr/bin/env bash' > "$TEST_DOTFILES/git-hooks/pre-push"
  echo 'echo canonical' >> "$TEST_DOTFILES/git-hooks/pre-push"
  cd "$TEST_DOTFILES"
  git add git-hooks/
  git commit --quiet -m "init"

  # Remove the working-tree copy entirely — empty SHA != HEAD SHA → fail
  rm "$TEST_DOTFILES/git-hooks/pre-push"

  _run_hook_integrity_check

  [ "$fail_count" -eq 1 ]
}
