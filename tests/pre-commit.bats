#!/usr/bin/env bats
# Tests for pre-commit hook — deletion protection for critical directories

load test_helper

HOOK="$BATS_TEST_DIRNAME/../git-hooks/pre-commit"

setup() {
  # A global core.hooksPath (set by dotfiles itself) would run the installed
  # hook instead of the copy under test.
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=.git/hooks
  TEST_DIR="$(mktemp -d)"
  TEST_REPO="$TEST_DIR/repo"
  git init --quiet "$TEST_REPO"

  # Simulate dotfiles repo by creating the marker file
  mkdir -p "$TEST_REPO/bin"
  touch "$TEST_REPO/bin/dotfiles-doctor"

  # Create tracked files in protected directories
  mkdir -p "$TEST_REPO/bin" "$TEST_REPO/tests" "$TEST_REPO/lib" \
           "$TEST_REPO/modules/git" "$TEST_REPO/skills/dev"
  echo "script" > "$TEST_REPO/bin/my-script"
  echo "test" > "$TEST_REPO/tests/my-test.bats"
  echo "lib" > "$TEST_REPO/lib/colors.sh"
  echo "doctor" > "$TEST_REPO/modules/git/doctor.sh"
  echo "skill" > "$TEST_REPO/skills/dev/SKILL.md"
  echo "readme" > "$TEST_REPO/README.md"
  echo "0.7.0" > "$TEST_REPO/.tasks-lint-version"

  git -C "$TEST_REPO" add -A
  git -C "$TEST_REPO" commit --no-verify -m "chore: initial" --quiet

  # Install the hook
  cp "$HOOK" "$TEST_REPO/.git/hooks/pre-commit"
  chmod +x "$TEST_REPO/.git/hooks/pre-commit"

  cat > "$TEST_DIR/npx" <<'STUB'
#!/bin/bash
target="${*: -1}"
if [ -f "$target" ] && [ "$(head -1 "$target")" = "# Tasks" ]; then
  exit 0
fi
echo "TASKS.md must start with # Tasks"
exit 1
STUB
  chmod +x "$TEST_DIR/npx"
  export PATH="$TEST_DIR:$PATH"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── Protected directory deletion blocking ────────────────────────

@test "pre-commit blocks deletion of bin/ files" {
  cd "$TEST_REPO"
  git rm --quiet bin/my-script
  run git commit -m "chore: delete script"
  [ "$status" -ne 0 ]
  [[ "$output" == *"protected file(s) staged for deletion"* ]]
  [[ "$output" == *"bin/my-script"* ]]
}

@test "pre-commit blocks deletion of tests/ files" {
  cd "$TEST_REPO"
  git rm --quiet tests/my-test.bats
  run git commit -m "chore: delete test"
  [ "$status" -ne 0 ]
  [[ "$output" == *"protected file(s) staged for deletion"* ]]
  [[ "$output" == *"tests/my-test.bats"* ]]
}

@test "pre-commit blocks deletion of lib/ files" {
  cd "$TEST_REPO"
  git rm --quiet lib/colors.sh
  run git commit -m "chore: delete lib"
  [ "$status" -ne 0 ]
  [[ "$output" == *"protected file(s) staged for deletion"* ]]
}

@test "pre-commit blocks deletion of modules/ files" {
  cd "$TEST_REPO"
  git rm --quiet modules/git/doctor.sh
  run git commit -m "chore: delete module"
  [ "$status" -ne 0 ]
  [[ "$output" == *"protected file(s) staged for deletion"* ]]
  # Specific path must appear so the user sees WHICH module is being lost.
  [[ "$output" == *"modules/git/doctor.sh"* ]]
}

@test "pre-commit blocks module deletion staged via 'git add -A' after manual rm" {
  # Same end-state as 'git rm' (deletion staged) but a different path through
  # the developer's hands — manual rm of the file followed by `git add -A`.
  # Multi-agent worktree corruption can also produce this shape, so the
  # protected-dir guard must catch it regardless of how the deletion landed
  # in the index. Closes test-module-deletion-protection.
  cd "$TEST_REPO"
  rm modules/git/doctor.sh
  git add -A
  run git commit -m "chore: rm + add -A removed module"
  [ "$status" -ne 0 ]
  [[ "$output" == *"protected file(s) staged for deletion"* ]]
  [[ "$output" == *"modules/git/doctor.sh"* ]]
}

@test "pre-commit blocks deletion of skills/ files" {
  cd "$TEST_REPO"
  git rm --quiet skills/dev/SKILL.md
  run git commit -m "chore: delete skill"
  [ "$status" -ne 0 ]
  [[ "$output" == *"protected file(s) staged for deletion"* ]]
}

@test "pre-commit allows untracking a gitignored bin/ file that stays on disk" {
  cd "$TEST_REPO"
  echo "bin/my-script" > .gitignore
  git add .gitignore
  git rm --quiet --cached bin/my-script
  run git commit -m "chore: untrack generated script"
  [ "$status" -eq 0 ]
  [ -f bin/my-script ]
}

@test "pre-commit still blocks deleting a gitignored bin/ file from disk" {
  cd "$TEST_REPO"
  echo "bin/my-script" > .gitignore
  git add .gitignore
  git rm --quiet bin/my-script
  run git commit -m "chore: delete generated script"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bin/my-script"* ]]
}

@test "pre-commit allows the verified AgentBrew memory-library retirement" {
  cd "$TEST_REPO"
  cat > bin/dotfiles-memory <<'SHIM'
#!/bin/bash
agentbrew_bin="${DOTFILES_MEMORY_AGENTBREW_BIN:-agentbrew}"
exec "$agentbrew_bin" memory "$@"
SHIM
  chmod +x bin/dotfiles-memory
  echo "retired memory implementation" > lib/dotfiles-memory.sh
  git add bin/dotfiles-memory lib/dotfiles-memory.sh
  git commit --no-verify -m "chore: seed memory shim" --quiet

  git rm --quiet lib/dotfiles-memory.sh
  run git commit -m "chore: retire dotfiles memory library"

  [ "$status" -eq 0 ]
  [ ! -e lib/dotfiles-memory.sh ]
}

# ── Non-protected deletions pass through ─────────────────────────

@test "pre-commit allows deletion of non-protected files" {
  cd "$TEST_REPO"
  git rm --quiet README.md
  run git commit --no-gpg-sign -m "chore: remove readme"
  [ "$status" -eq 0 ]
}

# ── Bypass with --no-verify ──────────────────────────────────────

@test "pre-commit allows protected deletions listed in DOTFILES_INTENDED_DELETIONS" {
  cd "$TEST_REPO"
  git rm --quiet modules/git/doctor.sh bin/my-script
  run env DOTFILES_INTENDED_DELETIONS="modules/git/ bin/my-script" git commit -m "refactor: remove git module"
  [ "$status" -eq 0 ]
}

@test "pre-commit still blocks protected deletions DOTFILES_INTENDED_DELETIONS does not list" {
  cd "$TEST_REPO"
  git rm --quiet modules/git/doctor.sh lib/colors.sh
  run env DOTFILES_INTENDED_DELETIONS="modules/git/" git commit -m "refactor: remove git module"
  [ "$status" -ne 0 ]
  [[ "$output" == *"lib/colors.sh"* ]]
  [[ "$output" != *"modules/git/doctor.sh"* ]]
}

@test "pre-commit names DOTFILES_INTENDED_DELETIONS, not --no-verify, for intended deletions" {
  cd "$TEST_REPO"
  git rm --quiet bin/my-script
  run git commit -m "chore: delete script"
  [ "$status" -ne 0 ]
  [[ "$output" == *"DOTFILES_INTENDED_DELETIONS"* ]]
  [[ "$output" != *"If intentional: git commit --no-verify"* ]]
}

@test "pre-commit can be bypassed with --no-verify for intentional deletions" {
  cd "$TEST_REPO"
  git rm --quiet bin/my-script
  run git commit --no-verify -m "chore: intentional delete"
  [ "$status" -eq 0 ]
}

@test "pre-commit blocks malformed staged TASKS.md in dotfiles repo" {
  cd "$TEST_REPO"
  cat > Makefile <<'MAKE'
lint:
	@:
MAKE
  echo "not a task queue" > TASKS.md
  git add Makefile
  git add -f TASKS.md

  run env DOTFILES_ALLOW_BLOCKED_NODE_PUBLISHER=1 git commit -m "chore: malformed tasks"
  [ "$status" -ne 0 ]
  [[ "$output" == *"TASKS.md lint failed"* ]]
  [[ "$output" == *"TASKS.md must start with # Tasks"* ]]
}

# ── Multiple deletions ───────────────────────────────────────────

@test "pre-commit reports count of all protected deletions" {
  cd "$TEST_REPO"
  git rm --quiet bin/my-script tests/my-test.bats lib/colors.sh
  run git commit -m "chore: mass delete"
  [ "$status" -ne 0 ]
  [[ "$output" == *"3 protected file(s)"* ]]
}

# ── Mass deletions and forbidden file types ──────────────────────

@test "pre-commit blocks more deletions than MAX_DELETES outside protected dirs" {
  cd "$TEST_REPO"
  mkdir -p docs
  for i in $(seq 1 51); do echo "$i" > "docs/page-$i.md"; done
  git add docs
  git commit --no-verify -m "chore: add docs" --quiet
  git rm --quiet -r docs
  run git commit -m "chore: remove docs"
  [ "$status" -ne 0 ]
  [[ "$output" == *"51 file deletions staged (limit: 50)"* ]]
}

@test "pre-commit allows deletions up to MAX_DELETES outside protected dirs" {
  cd "$TEST_REPO"
  mkdir -p docs
  for i in $(seq 1 50); do echo "$i" > "docs/page-$i.md"; done
  git add docs
  git commit --no-verify -m "chore: add docs" --quiet
  git rm --quiet -r docs
  run git commit --no-gpg-sign -m "chore: remove docs"
  [ "$status" -eq 0 ]
}

@test "pre-commit blocks staged private keys and certificates" {
  cd "$TEST_REPO"
  echo "key" > id_ed25519
  echo "cert" > server.pem
  git add id_ed25519 server.pem
  run git commit -m "chore: add keys"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Sensitive file types staged"* ]]
  [[ "$output" == *"id_ed25519"* ]]
  [[ "$output" == *"server.pem"* ]]
}

@test "pre-commit allows plain .env.example next to the forbidden list" {
  cd "$TEST_REPO"
  echo "KEY=" > .env.example
  git add .env.example
  run git commit --no-gpg-sign -m "chore: add env example"
  [ "$status" -eq 0 ]
}

# ── Only triggers in dotfiles repo ───────────────────────────────

@test "pre-commit skips protected-dir check in non-dotfiles repos" {
  OTHER="$TEST_DIR/other"
  git init --quiet "$OTHER"
  mkdir -p "$OTHER/bin"
  echo "script" > "$OTHER/bin/tool"
  git -C "$OTHER" add -A
  git -C "$OTHER" commit --no-verify -m "chore: init" --quiet

  # Install hook but without dotfiles-doctor marker
  cp "$HOOK" "$OTHER/.git/hooks/pre-commit"
  chmod +x "$OTHER/.git/hooks/pre-commit"

  cd "$OTHER"
  git rm --quiet bin/tool
  run git commit -m "chore: remove tool"
  [ "$status" -eq 0 ]
}

@test "pre-commit delegates to executable repo-local hooks/pre-commit" {
  OTHER="$TEST_DIR/delegated"
  git init --quiet "$OTHER"
  echo "readme" > "$OTHER/README.md"
  git -C "$OTHER" add README.md
  git -C "$OTHER" commit --no-verify -m "chore: init" --quiet

  mkdir -p "$OTHER/hooks"
  cat > "$OTHER/hooks/pre-commit" <<'SCRIPT'
#!/bin/bash
echo "repo-local pre-commit ran" >&2
exit 42
SCRIPT
  chmod +x "$OTHER/hooks/pre-commit"

  cp "$HOOK" "$OTHER/.git/hooks/pre-commit"
  chmod +x "$OTHER/.git/hooks/pre-commit"

  cd "$OTHER"
  echo "change" >> README.md
  git add README.md
  run git commit -m "chore: change"
  [ "$status" -ne 0 ]
  [[ "$output" == *"repo-local pre-commit ran"* ]]
}

@test "pre-commit leak gate handles a repo with no private env" {
  OTHER="$TEST_DIR/leak-gate"
  git init --quiet "$OTHER"
  mkdir -p "$OTHER/lib"
  : > "$OTHER/lib/oss-readiness.sh"
  echo "readme" > "$OTHER/README.md"
  git -C "$OTHER" add lib/oss-readiness.sh README.md
  git -C "$OTHER" commit --no-verify -m "chore: init" --quiet

  cp "$HOOK" "$OTHER/.git/hooks/pre-commit"
  chmod +x "$OTHER/.git/hooks/pre-commit"

  cd "$OTHER"
  git config user.email public@example.com
  echo "safe change" >> README.md
  git add README.md
  run env -u OSS_READINESS_INTERNAL_PATTERN -u OSS_READINESS_PRIVATE_EMAIL_PATTERN git commit --no-gpg-sign -m "chore: safe change"
  [ "$status" -eq 0 ]
}
