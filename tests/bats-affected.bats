#!/usr/bin/env bats
# Tests for bin/bats-affected — affected test file resolution

DOTFILES_DIR="$BATS_TEST_DIRNAME/.."
SCRIPT="$DOTFILES_DIR/bin/bats-affected"

setup_file() {
  export TEST_REPO="$BATS_FILE_TMPDIR/repo"
  mkdir -p "$TEST_REPO"/{bin,lib,modules/git,tests,git-hooks,home,.chezmoiscripts,launchagents,.github/scripts,.github/workflows,skills/update-tooling}

  # Initialize a git repo with basic structure
  git -C "$TEST_REPO" init -q
  git -C "$TEST_REPO" config user.email "test@test.com"
  git -C "$TEST_REPO" config user.name "Test"

  # Create bin scripts
  for name in dotfiles dotfiles-doctor dotfiles-audit dotfiles-sync \
              dotfiles-add dotfiles-unmanage dotfiles-enterprise \
              dotfiles-uninstall dotfiles-stats dotfiles-new-module \
              dotfiles-brew-add dotfiles-defaults-add dotfiles-defaults-preview \
              dotfiles-profile dotfiles-quickstart dotfiles-upgrade dotfiles-validate \
              cheat cleanup morning cached-run git-maintain gh git; do
    printf '#!/bin/bash\necho "%s"\n' "$name" > "$TEST_REPO/bin/$name"
    chmod +x "$TEST_REPO/bin/$name"
  done

  # Create lib files (some bin scripts reference them)
  echo '# colors' > "$TEST_REPO/lib/colors.sh"
  echo '# stats' > "$TEST_REPO/lib/stats.sh"
  echo '# output' > "$TEST_REPO/lib/output.sh"

  # Make cleanup source colors.sh and morning source stats.sh
  printf '#!/bin/bash\nsource lib/colors.sh\n' > "$TEST_REPO/bin/cleanup"
  printf '#!/bin/bash\nsource lib/stats.sh\n' > "$TEST_REPO/bin/morning"

  # Create test files
  for name in cli doctor audit dotfiles-sync add-unmanage enterprise \
              uninstall stats scaffolding smoke cleanup morning validate \
              defaults-preview quickstart dotfiles-upgrade dotfiles-new-module \
              dotfiles-brew-add dotfiles-defaults-add dotfiles-profile \
              cached-run git-maintain gh-wrapper git-wrapper output chezmoi \
              pre-commit brew-audit coverage tasks-lint verify-counts \
              agent-artifact-coverage update-tooling-skill; do
    echo "# $name tests" > "$TEST_REPO/tests/$name.bats"
  done

  # Create test_helper
  echo '# shared helpers' > "$TEST_REPO/tests/test_helper.bash"

  # Create other source files
  echo '# module' > "$TEST_REPO/modules/git/doctor.sh"
  echo '# macos' > "$TEST_REPO/macos.sh"
  echo '# hook' > "$TEST_REPO/git-hooks/pre-commit"
  echo '# home' > "$TEST_REPO/home/zshrc"
  echo '# tmpl' > "$TEST_REPO/symlink_dot_zshrc.tmpl"
  echo '# brew audit helper' > "$TEST_REPO/.github/scripts/brew-audit-manifest.sh"
  echo '# coverage helper' > "$TEST_REPO/.github/scripts/check-shell-coverage.sh"
  echo '# ci workflow' > "$TEST_REPO/.github/workflows/ci.yml"
  echo '# brew audit workflow' > "$TEST_REPO/.github/workflows/brew-audit.yml"
  echo '1' > "$TEST_REPO/.shell-coverage-floor"
  echo 'skills: []' > "$TEST_REPO/Agentfile.yaml"
  echo '# update-tooling' > "$TEST_REPO/skills/update-tooling/SKILL.md"
  echo 'lint-tasks: ; @true' > "$TEST_REPO/Makefile"

  # Initial commit (--no-verify to skip pre-commit hooks in test repos)
  git -C "$TEST_REPO" add -A
  git -C "$TEST_REPO" commit -q --no-verify -m "chore: init"

  # Copy the real bats-affected script and its doc-path list into the test repo
  cp "$SCRIPT" "$TEST_REPO/bin/bats-affected"
  chmod +x "$TEST_REPO/bin/bats-affected"
  cp "$DOTFILES_DIR/tests/verify-counts-doc-paths.sh" "$TEST_REPO/tests/verify-counts-doc-paths.sh"
  git -C "$TEST_REPO" add bin/bats-affected tests/verify-counts-doc-paths.sh
  git -C "$TEST_REPO" commit -q --no-verify -m "chore: add bats-affected"
}

setup() {
  # Reset working tree to clean committed state (no per-test git init)
  git -C "$TEST_REPO" checkout . 2>/dev/null
  git -C "$TEST_REPO" clean -fd 2>/dev/null
}

teardown() {
  :
}

# Helper: modify a file and check which tests are affected
affected_for() {
  local file="$1"
  echo "# change" >> "$TEST_REPO/$file"
  (cd "$TEST_REPO" && bash bin/bats-affected)
}

# Helper: extract just test basenames from output
basenames() {
  while IFS= read -r line; do
    [ -n "$line" ] && basename "$line" .bats
  done
}

assert_affected_includes() {
  local file="$1" expected="$2" result
  result=$(affected_for "$file")
  echo "$result" | basenames | grep -qx "$expected"
}

# ── Script hygiene ───────────────────────────────────────────────────

@test "bats-affected is executable" {
  [ -x "$SCRIPT" ]
}

@test "bats-affected has correct shebang" {
  head -1 "$SCRIPT" | grep -q '#!/bin/bash'
}

@test "bats-affected uses strict mode" {
  grep -q 'set -euo pipefail' "$SCRIPT"
}

@test "--help shows usage and exits 0" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"bats-affected"* ]]
}

@test "-h shows usage and exits 0" {
  run bash "$SCRIPT" -h
  [ "$status" -eq 0 ]
}

# ── No changes → no output ──────────────────────────────────────────

@test "no changes produces no output" {
  run bash -c "cd '$TEST_REPO' && bash bin/bats-affected"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "deleted test file is not emitted as an affected test" {
  rm "$TEST_REPO/tests/smoke.bats"
  git -C "$TEST_REPO" add tests/smoke.bats

  run bash -c "cd '$TEST_REPO' && bash bin/bats-affected"
  [ "$status" -eq 0 ]
  [[ "$output" != *"tests/smoke.bats"* ]]
}

# ── bin/ → test mapping ─────────────────────────────────────────────

@test "bin/dotfiles change triggers cli.bats" {
  result=$(affected_for "bin/dotfiles")
  echo "$result" | basenames | grep -q "cli"
}

@test "bin/cheat change triggers cli.bats" {
  result=$(affected_for "bin/cheat")
  echo "$result" | basenames | grep -q "cli"
}

@test "bin/dotfiles-doctor change triggers doctor.bats" {
  result=$(affected_for "bin/dotfiles-doctor")
  echo "$result" | basenames | grep -q "doctor"
}

@test "bin/dotfiles-audit change triggers audit.bats" {
  result=$(affected_for "bin/dotfiles-audit")
  echo "$result" | basenames | grep -q "audit"
}

@test "bin/dotfiles-sync change triggers dotfiles-sync.bats" {
  result=$(affected_for "bin/dotfiles-sync")
  echo "$result" | basenames | grep -q "dotfiles-sync"
}

@test "bin/dotfiles-validate change triggers validate.bats" {
  assert_affected_includes "bin/dotfiles-validate" "validate"
}

@test "bin/dotfiles-defaults-preview change triggers defaults-preview.bats" {
  assert_affected_includes "bin/dotfiles-defaults-preview" "defaults-preview"
}

@test "bin/dotfiles-quickstart change triggers quickstart.bats" {
  assert_affected_includes "bin/dotfiles-quickstart" "quickstart"
}

@test "bin/dotfiles-upgrade change triggers dotfiles-upgrade.bats" {
  assert_affected_includes "bin/dotfiles-upgrade" "dotfiles-upgrade"
}

@test "bin/dotfiles-add change triggers add-unmanage.bats" {
  result=$(affected_for "bin/dotfiles-add")
  echo "$result" | basenames | grep -q "add-unmanage"
}

@test "bin/dotfiles-unmanage change triggers add-unmanage.bats" {
  result=$(affected_for "bin/dotfiles-unmanage")
  echo "$result" | basenames | grep -q "add-unmanage"
}

@test "bin/dotfiles-new-module change triggers scaffolding.bats" {
  result=$(affected_for "bin/dotfiles-new-module")
  echo "$result" | basenames | grep -q "scaffolding"
}

@test "bin/dotfiles-new-module change triggers focused dotfiles-new-module.bats" {
  assert_affected_includes "bin/dotfiles-new-module" "dotfiles-new-module"
}

@test "bin/dotfiles-brew-add change triggers scaffolding.bats" {
  result=$(affected_for "bin/dotfiles-brew-add")
  echo "$result" | basenames | grep -q "scaffolding"
}

@test "bin/dotfiles-brew-add change triggers focused dotfiles-brew-add.bats" {
  assert_affected_includes "bin/dotfiles-brew-add" "dotfiles-brew-add"
}

@test "bin/dotfiles-defaults-add change triggers focused dotfiles-defaults-add.bats" {
  assert_affected_includes "bin/dotfiles-defaults-add" "dotfiles-defaults-add"
}

@test "bin/dotfiles-profile change triggers focused dotfiles-profile.bats" {
  assert_affected_includes "bin/dotfiles-profile" "dotfiles-profile"
}

@test "bin/dotfiles-stats change triggers stats.bats" {
  assert_affected_includes "bin/dotfiles-stats" "stats"
}

@test "bin/dotfiles-enterprise change triggers enterprise.bats" {
  result=$(affected_for "bin/dotfiles-enterprise")
  echo "$result" | basenames | grep -q "enterprise"
}

@test "bin/dotfiles-uninstall change triggers uninstall.bats" {
  result=$(affected_for "bin/dotfiles-uninstall")
  echo "$result" | basenames | grep -q "uninstall"
}

@test "bin/cleanup change triggers cleanup.bats" {
  result=$(affected_for "bin/cleanup")
  echo "$result" | basenames | grep -q "cleanup"
}

@test "bin/cached-run change triggers cached-run.bats" {
  result=$(affected_for "bin/cached-run")
  echo "$result" | basenames | grep -q "cached-run"
}

@test "bin/gh change triggers gh-wrapper.bats and smoke.bats" {
  result=$(affected_for "bin/gh")
  echo "$result" | basenames | grep -q "gh-wrapper"
  echo "$result" | basenames | grep -q "gh-wrapper-leak-guard"
  echo "$result" | basenames | grep -q "smoke"
}

@test "bin/git change triggers git-wrapper.bats and smoke.bats" {
  result=$(affected_for "bin/git")
  echo "$result" | basenames | grep -q "git-wrapper"
  echo "$result" | basenames | grep -q "smoke"
}

@test "bin/ changes always include smoke.bats" {
  result=$(affected_for "bin/cleanup")
  echo "$result" | basenames | grep -q "smoke"
}

# ── lib/ → test mapping (transitive) ────────────────────────────────

@test "lib/output.sh change triggers output.bats" {
  result=$(affected_for "lib/output.sh")
  echo "$result" | basenames | grep -q "output"
}

@test "lib/stats.sh change triggers stats.bats" {
  result=$(affected_for "lib/stats.sh")
  echo "$result" | basenames | grep -q "stats"
}

@test "lib/colors.sh change triggers tests for scripts that source it" {
  result=$(affected_for "lib/colors.sh")
  echo "$result" | basenames | grep -q "cleanup"
}

@test "lib/stats.sh change triggers tests for scripts that source it" {
  result=$(affected_for "lib/stats.sh")
  echo "$result" | basenames | grep -q "morning"
}

# ── test file itself ─────────────────────────────────────────────────

@test "changing a test file triggers that test file" {
  result=$(affected_for "tests/cli.bats")
  echo "$result" | basenames | grep -q "cli"
}

@test "update-tooling skill changes trigger its focused contract test" {
  assert_affected_includes "skills/update-tooling/SKILL.md" "update-tooling-skill"
}

@test "Agentfile changes trigger agent artifact and update-tooling tests" {
  result=$(affected_for "Agentfile.yaml")
  echo "$result" | basenames | grep -qx "agent-artifact-coverage"
  echo "$result" | basenames | grep -qx "update-tooling-skill"
}

# ── test_helper triggers all ─────────────────────────────────────────

@test "test_helper.bash change triggers all tests" {
  result=$(affected_for "tests/test_helper.bash")
  local count
  count=$(echo "$result" | wc -l | tr -d ' ')
  # Should return all .bats files
  local total
  total=$(ls "$TEST_REPO"/tests/*.bats | wc -l | tr -d ' ')
  [ "$count" -eq "$total" ]
}

# ── modules/, home/, macos, git-hooks ────────────────────────────────

@test "modules/ change triggers doctor.bats and smoke.bats" {
  result=$(affected_for "modules/git/doctor.sh")
  echo "$result" | basenames | grep -q "doctor"
  echo "$result" | basenames | grep -q "smoke"
}

@test "home/ change triggers chezmoi.bats and smoke.bats" {
  result=$(affected_for "home/zshrc")
  echo "$result" | basenames | grep -q "chezmoi"
  echo "$result" | basenames | grep -q "smoke"
}

@test "git-hooks/ change triggers pre-commit.bats" {
  result=$(affected_for "git-hooks/pre-commit")
  echo "$result" | basenames | grep -q "pre-commit"
}

@test "git-hooks/commit-msg change triggers commit-msg.bats" {
  result=$(affected_for "git-hooks/commit-msg")
  echo "$result" | basenames | grep -q "commit-msg"
}

@test "git-hooks/pre-push change triggers pre-push.bats" {
  result=$(affected_for "git-hooks/pre-push")
  echo "$result" | basenames | grep -q "pre-push"
}

@test "macos.sh change triggers smoke.bats" {
  result=$(affected_for "macos.sh")
  echo "$result" | basenames | grep -q "smoke"
}

# ── CI helpers, coverage floor, and Makefile gates ──────────────────

@test "brew audit helper change triggers brew-audit.bats" {
  assert_affected_includes ".github/scripts/brew-audit-manifest.sh" "brew-audit"
}

@test "brew audit workflow change triggers brew-audit.bats" {
  assert_affected_includes ".github/workflows/brew-audit.yml" "brew-audit"
}

@test "coverage helper change triggers coverage.bats" {
  assert_affected_includes ".github/scripts/check-shell-coverage.sh" "coverage"
}

@test "coverage floor change triggers coverage.bats" {
  assert_affected_includes ".shell-coverage-floor" "coverage"
}

@test "coverage workflow change triggers coverage.bats" {
  assert_affected_includes ".github/workflows/ci.yml" "coverage"
}

@test "ci workflow task lint changes trigger tasks-lint.bats" {
  assert_affected_includes ".github/workflows/ci.yml" "tasks-lint"
}

@test "Makefile changes trigger task lint focused tests" {
  assert_affected_includes "Makefile" "tasks-lint"
}

@test "Makefile changes trigger count focused tests" {
  assert_affected_includes "Makefile" "verify-counts"
}

@test "README.md changes trigger verify-counts.bats" {
  echo "# readme" > "$TEST_REPO/README.md"
  git -C "$TEST_REPO" add README.md
  assert_affected_includes "README.md" "verify-counts"
}

@test "AGENTS.md changes trigger verify-counts.bats" {
  echo "# agents" > "$TEST_REPO/AGENTS.md"
  git -C "$TEST_REPO" add AGENTS.md
  assert_affected_includes "AGENTS.md" "verify-counts"
}

@test "docs/faq.md changes trigger verify-counts.bats" {
  mkdir -p "$TEST_REPO/docs"
  echo "# faq" > "$TEST_REPO/docs/faq.md"
  git -C "$TEST_REPO" add docs/faq.md
  assert_affected_includes "docs/faq.md" "verify-counts"
}

@test "CONTRIBUTING.md changes trigger verify-counts.bats" {
  echo "# contributing" > "$TEST_REPO/CONTRIBUTING.md"
  git -C "$TEST_REPO" add CONTRIBUTING.md
  assert_affected_includes "CONTRIBUTING.md" "verify-counts"
}

@test "human-blocked-actions doc changes trigger verify-counts.bats" {
  mkdir -p "$TEST_REPO/docs/human-blocked-actions"
  echo "# sample" > "$TEST_REPO/docs/human-blocked-actions/sample.md"
  git -C "$TEST_REPO" add docs/human-blocked-actions/sample.md
  assert_affected_includes "docs/human-blocked-actions/sample.md" "verify-counts"
}

@test "user-story doc changes trigger verify-counts.bats" {
  mkdir -p "$TEST_REPO/docs/user-stories"
  echo "# sample" > "$TEST_REPO/docs/user-stories/sample.md"
  git -C "$TEST_REPO" add docs/user-stories/sample.md
  assert_affected_includes "docs/user-stories/sample.md" "verify-counts"
}

@test "TASKS.md changes trigger verify-counts.bats" {
  echo "# Tasks" > "$TEST_REPO/TASKS.md"
  git -C "$TEST_REPO" add -f TASKS.md
  assert_affected_includes "TASKS.md" "verify-counts"
}

@test "CHANGELOG.md changes trigger verify-counts.bats" {
  echo "# Changelog" > "$TEST_REPO/CHANGELOG.md"
  git -C "$TEST_REPO" add CHANGELOG.md
  assert_affected_includes "CHANGELOG.md" "verify-counts"
}

@test "Agentfile.yaml changes trigger verify-counts.bats" {
  echo "version: 1" > "$TEST_REPO/Agentfile.yaml"
  git -C "$TEST_REPO" add Agentfile.yaml
  assert_affected_includes "Agentfile.yaml" "verify-counts"
}

@test "every verify-counts doc path list entry triggers verify-counts.bats" {
  # shellcheck source=verify-counts-doc-paths.sh
  source "$DOTFILES_DIR/tests/verify-counts-doc-paths.sh"
  for doc in "${VERIFY_COUNTS_DOC_FILES[@]}"; do
    mkdir -p "$(dirname "$TEST_REPO/$doc")"
    echo "# doc" > "$TEST_REPO/$doc"
    git -C "$TEST_REPO" add "$doc"
    assert_affected_includes "$doc" "verify-counts" || {
      echo "missing verify-counts mapping for: $doc"
      return 1
    }
    git -C "$TEST_REPO" reset -q HEAD -- "$doc" 2>/dev/null || true
    git -C "$TEST_REPO" checkout -q -- "$doc" 2>/dev/null || rm -f "$TEST_REPO/$doc"
  done
}

@test "Makefile changes trigger coverage focused tests" {
  assert_affected_includes "Makefile" "coverage"
}

@test "make test uses repo-local selector so untracked bats files run" {
  mkdir -p "$TEST_REPO/tmp/fake-bin"
  printf '#!/bin/sh\nexit 0\n' > "$TEST_REPO/tmp/fake-bin/bats-affected"
  chmod +x "$TEST_REPO/tmp/fake-bin/bats-affected"
  cat > "$TEST_REPO/tests/untracked-proof.bats" <<'EOF'
#!/usr/bin/env bats
@test "untracked proof runs" {
  [ -n "${PROOF_FILE:-}" ]
  touch "$PROOF_FILE"
}
EOF
  cat > "$TEST_REPO/Makefile" <<'EOF'
test:
	@affected=$$(./bin/bats-affected); \
	if [ -z "$$affected" ]; then \
	  echo "No affected test files"; \
	else \
	  echo "$$affected" | xargs bats; \
	fi
EOF

  proof_file="$TEST_REPO/tmp/untracked-proof-ran"
  run bash -c "cd '$TEST_REPO' && PROOF_FILE='$proof_file' PATH='$TEST_REPO/tmp/fake-bin':\$PATH make test"
  [ "$status" -eq 0 ]
  [ -f "$proof_file" ]
  [[ "$output" != *"No affected test files"* ]]
}

# ── Output is deduped and sorted ─────────────────────────────────────

@test "output has no duplicate lines" {
  result=$(affected_for "bin/cleanup")
  local lines dupes
  lines=$(echo "$result" | wc -l | tr -d ' ')
  dupes=$(echo "$result" | sort | uniq -d | wc -l | tr -d ' ')
  [ "$dupes" -eq 0 ]
}

@test "output is sorted" {
  result=$(affected_for "lib/colors.sh")
  local sorted
  sorted=$(echo "$result" | sort)
  [ "$result" = "$sorted" ]
}
