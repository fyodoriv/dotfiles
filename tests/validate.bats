#!/usr/bin/env bats
# Tests for dotfiles-validate pre-share verification

DOTFILES_DIR="$BATS_TEST_DIRNAME/.."

# Each invocation of `dotfiles-validate --quick` takes ~10s because it
# scans the whole repo. Every test below checks a different substring
# of that output, so run the validator ONCE per file and cache both
# output and exit status in a shared temp file that every test reads.
setup_file() {
  export VALIDATE_CACHE_DIR="$(mktemp -d)"
  export VALIDATE_OUT="$VALIDATE_CACHE_DIR/out"
  export VALIDATE_STATUS="$VALIDATE_CACHE_DIR/status"
  bash "$DOTFILES_DIR/bin/dotfiles-validate" --quick > "$VALIDATE_OUT" 2>&1
  echo "$?" > "$VALIDATE_STATUS"
}

teardown_file() {
  rm -rf "$VALIDATE_CACHE_DIR"
}

# Helper: read cached status and output into the bats `$status` / `$output`
# contract without re-running the validator.
load_cached() {
  output="$(cat "$VALIDATE_OUT")"
  status="$(cat "$VALIDATE_STATUS")"
}

create_validate_fixture_repo() {
  local repo="$1"
  mkdir -p "$repo/bin" "$repo/lib"
  cp "$DOTFILES_DIR/bin/dotfiles-validate" "$repo/bin/dotfiles-validate"
  cp "$DOTFILES_DIR/lib/colors.sh" "$repo/lib/colors.sh"
  cp "$DOTFILES_DIR/lib/output.sh" "$repo/lib/output.sh"
  cp "$DOTFILES_DIR/lib/secret-scan.sh" "$repo/lib/secret-scan.sh"
  chmod +x "$repo/bin/dotfiles-validate"
  git -C "$repo" init -q
  git -C "$repo" add bin lib
}

@test "validate --quick exits 0 on clean repo" {
  load_cached
  [ "$status" -eq 0 ]
}

@test "validate --quick prints pass/fail summary" {
  load_cached
  [[ "$output" == *"total"* ]]
}

@test "validate --quick checks hardcoded paths" {
  load_cached
  [[ "$output" == *"hardcoded"* ]] || [[ "$output" == *"Hardcoded"* ]]
}

@test "validate --quick checks secrets" {
  load_cached
  [[ "$output" == *"secrets"* ]] || [[ "$output" == *"Secrets"* ]]
}

@test "validate --quick detects a secret even when the line mentions TODO or example" {
  local repo
  repo="$(mktemp -d)"
  create_validate_fixture_repo "$repo"
  echo 'API_KEY="sk_live_abcdefghijklmnop1234" # TODO rotate this example' > "$repo/leaky.sh" # dotfiles-secret-allowlist: writes a fixture that the scanner must catch
  git -C "$repo" add leaky.sh

  run bash "$repo/bin/dotfiles-validate" --quick

  rm -rf "$repo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Possible secret in: leaky.sh"* ]]
}

@test "validate --quick allows structured secret scan comments" {
  local repo
  repo="$(mktemp -d)"
  create_validate_fixture_repo "$repo"
  echo 'API_KEY="sk_live_intentionalfixture" # dotfiles-secret-allowlist: fake credential for scanner coverage' > "$repo/allowlisted.sh"
  git -C "$repo" add allowlisted.sh

  run bash "$repo/bin/dotfiles-validate" --quick

  rm -rf "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No secrets in tracked files"* ]]
}

@test "validate --quick reports a hardcoded path fixture with relative path" {
  local repo user_name
  repo="$(mktemp -d)"
  user_name="$(whoami)"
  create_validate_fixture_repo "$repo"
  cat > "$repo/bin/hardcoded-path" <<EOF
#!/bin/bash
echo "/Users/$user_name/workspace"
EOF
  chmod +x "$repo/bin/hardcoded-path"

  run bash "$repo/bin/dotfiles-validate" --quick

  rm -rf "$repo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Hardcoded user path in bin/hardcoded-path"* ]]
}

@test "validate --quick scans shared config for hardcoded user paths" {
  local repo
  repo="$(mktemp -d)"
  create_validate_fixture_repo "$repo"
  mkdir -p "$repo/home" "$repo/git-hooks"
  echo 'args: ["/Users/example/apps/tool/run_server.py"]' > "$repo/Agentfile.yaml"
  echo 'export TOOL_HOME="/Users/example/.tool"' > "$repo/home/zshrc"
  cat > "$repo/git-hooks/commit-msg" <<'EOF'
#!/bin/bash
strip_lib="/Users/example/apps/dotfiles/lib/strip-agent-attribution.sh"
EOF
  chmod +x "$repo/git-hooks/commit-msg"
  git -C "$repo" add Agentfile.yaml home/zshrc git-hooks/commit-msg

  run bash "$repo/bin/dotfiles-validate" --quick

  rm -rf "$repo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Hardcoded user path in Agentfile.yaml"* ]]
  [[ "$output" == *"Hardcoded user path in home/zshrc"* ]]
  [[ "$output" == *"Hardcoded user path in git-hooks/commit-msg"* ]]
}

@test "validate --quick ignores hardcoded path fixtures in docs and tests" {
  local repo
  repo="$(mktemp -d)"
  create_validate_fixture_repo "$repo"
  mkdir -p "$repo/docs" "$repo/tests"
  echo 'Example fixture: /Users/example/apps/dotfiles' > "$repo/docs/example.md"
  echo 'echo "/Users/example/test-fixture"' > "$repo/tests/example.bats"
  git -C "$repo" add docs/example.md tests/example.bats

  run bash "$repo/bin/dotfiles-validate" --quick

  rm -rf "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No hardcoded user paths in shared config"* ]]
}

@test "validate --quick reports an enterprise hostname fixture with relative path" {
  local repo
  repo="$(mktemp -d)"
  create_validate_fixture_repo "$repo"
  mkdir -p "$repo/home"
  echo "clone from github.company.example.com" > "$repo/home/enterprise-host"

  run bash "$repo/bin/dotfiles-validate" --quick

  rm -rf "$repo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Enterprise hostname in: home/enterprise-host"* ]]
}

@test "validate --quick reports a tracked env fixture with relative path" {
  local repo
  repo="$(mktemp -d)"
  create_validate_fixture_repo "$repo"
  echo "FEATURE_FLAG=true" > "$repo/.env"
  git -C "$repo" add -f .env

  run bash "$repo/bin/dotfiles-validate" --quick

  rm -rf "$repo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Tracked .env file: .env"* ]]
}

@test "validate --quick reports a missing shebang fixture with relative path" {
  local repo
  repo="$(mktemp -d)"
  create_validate_fixture_repo "$repo"
  echo "echo no shebang" > "$repo/bin/no-shebang"
  chmod +x "$repo/bin/no-shebang"

  run bash "$repo/bin/dotfiles-validate" --quick

  rm -rf "$repo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing shebang: bin/no-shebang"* ]]
}

@test "validate --quick skips tool shim symlinks to binaries in the shebang check" {
  local repo
  repo="$(mktemp -d)"
  create_validate_fixture_repo "$repo"
  ln -s /bin/ls "$repo/bin/ls"

  run bash "$repo/bin/dotfiles-validate" --quick

  rm -rf "$repo"
  [[ "$output" != *"Missing shebang: bin/ls"* ]]
}

@test "validate --quick reports a world-writable script fixture with relative path" {
  local repo
  repo="$(mktemp -d)"
  create_validate_fixture_repo "$repo"
  cat > "$repo/bin/world-writable" <<'EOF'
#!/bin/bash
echo world writable
EOF
  chmod 777 "$repo/bin/world-writable"

  run bash "$repo/bin/dotfiles-validate" --quick

  rm -rf "$repo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"World-writable: bin/world-writable"* ]]
}

@test "validate --quick checks script hygiene" {
  load_cached
  [[ "$output" == *"shebang"* ]] || [[ "$output" == *"executable"* ]]
}

@test "validate --quick reports skipped share gates" {
  load_cached
  [[ "$output" == *"Skipped TASKS.md lint, shellcheck, and tests"* ]]
}

@test "validate --quick remains network-free in the base flow" {
  local repo stubs marker
  repo="$(mktemp -d)"
  create_validate_fixture_repo "$repo"
  stubs="$repo/stubs"
  marker="$repo/network-called"
  mkdir -p "$stubs"
  cat > "$stubs/ssh" <<EOF
#!/bin/bash
echo ssh >> "$marker"
exit 99
EOF
  cat > "$stubs/brew" <<EOF
#!/bin/bash
echo brew >> "$marker"
exit 99
EOF
  chmod +x "$stubs/ssh" "$stubs/brew"

  run env PATH="$stubs:$PATH" bash "$repo/bin/dotfiles-validate" --quick

  [ "$status" -eq 0 ]
  [ ! -e "$marker" ]
  rm -rf "$repo"
}

@test "validate --help exits 0" {
  run bash "$DOTFILES_DIR/bin/dotfiles-validate" --help
  [ "$status" -eq 0 ]
}

@test "validate --help shows usage" {
  run bash "$DOTFILES_DIR/bin/dotfiles-validate" --help
  [[ "$output" == *"dotfiles-validate"* ]]
}

@test "validate full fails when TASKS.md lint fails" {
  local repo
  repo="$(mktemp -d)"
  create_validate_fixture_repo "$repo"
  cat > "$repo/Makefile" <<'MAKE'
lint-tasks:
	@exit 1
lint:
	@:
test-all:
	@:
MAKE
  echo "not a task queue" > "$repo/TASKS.md"
  git -C "$repo" add Makefile
  git -C "$repo" add -f TASKS.md

  run bash "$repo/bin/dotfiles-validate"

  rm -rf "$repo"
  [ "$status" -eq 1 ]
  [[ "$output" == *"TASKS.md lint failed"* ]]
}

@test "dotfiles validate dispatches to dotfiles-validate" {
  run bash "$DOTFILES_DIR/bin/dotfiles" validate --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"dotfiles-validate"* ]]
}

@test "validate --quick checks enterprise references" {
  load_cached
  [[ "$output" == *"enterprise"* ]] || [[ "$output" == *"Enterprise"* ]]
}

@test "validate --quick checks world-writable scripts" {
  load_cached
  [[ "$output" == *"world-writable"* ]] || [[ "$output" == *"World-writable"* ]] || [[ "$output" == *"writable"* ]]
}

@test "adoption checklist includes the pre-share validation gate" {
  grep -Fq 'dotfiles validate --quick' "$DOTFILES_DIR/docs/adoption-checklist.md"
  grep -Fq 'Run full `dotfiles validate` before announcing the fork' "$DOTFILES_DIR/docs/adoption-checklist.md"
}

@test "team rollout guide explains quick versus full validation" {
  grep -Fq 'Pre-announcement validation gate' "$DOTFILES_DIR/docs/team-onboarding.md"
  grep -Fq '`--quick` skips lint and tests' "$DOTFILES_DIR/docs/team-onboarding.md"
  grep -Fq 'full bats suite' "$DOTFILES_DIR/docs/team-onboarding.md"
}

@test "README links pre-share validation to rollout docs" {
  grep -Fq 'Run `dotfiles validate` before sharing' "$DOTFILES_DIR/README.md"
  grep -Fq 'docs/team-onboarding.md#pre-announcement-validation-gate' "$DOTFILES_DIR/README.md"
}
