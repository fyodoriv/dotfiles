#!/usr/bin/env bats
# End-to-end chezmoi cycle test on a clean HOME directory.
# Verifies file management (symlinks, copies, permissions, ignore rules).
# Lifecycle scripts (brew, macos, launchagents) are excluded — they are
# tested by running them on the real system, not in a temp dir.

setup() {
  # Skip if chezmoi is not installed
  if ! command -v chezmoi &>/dev/null; then
    skip "chezmoi not installed"
  fi

  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  REAL_DOTFILES="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

  mkdir -p "$TEST_HOME"

  # Pre-seed chezmoi config to bypass interactive prompts
  mkdir -p "$TEST_HOME/.config/chezmoi"
  cat > "$TEST_HOME/.config/chezmoi/chezmoi.yaml" << EOF
sourceDir: "$REAL_DOTFILES"
encryption: age
age:
  identity: "$TEST_HOME/.config/chezmoi/key.txt"
  recipient: unused-no-encryption-configured
data:
  profile: "full"
  is_enterprise: false
  work_email_domain: "example.com"
  github_enterprise_host: "github.example.com"
  dotfiles_dir: "apps/dotfiles"
  repos_dir: "apps"
  brew_skip: []
  auto_upgrade: false
  use_ai_tools: false
  use_encryption: false
  morning_hour: 8
  morning_minute: 30
  git_work_name: "Test"
  git_work_email: "test@example.com"
  git_personal_enabled: false
  git_personal_name: ""
  git_personal_email: ""

EOF

  # Run chezmoi init to render config from template (processes .chezmoiignore).
  # --promptDefaults makes promptOnce* functions return defaults without an
  # interactive prompt; data values pre-seeded above still win where the
  # template uses promptStringOnce/promptIntOnce/etc. With --prompt=false
  # the init aborts on the first promptOnce call (EOF), leaving chezmoi
  # state empty and triggering "config file template has changed" warnings
  # on subsequent verify runs.
  HOME="$TEST_HOME" chezmoi init \
    --source "$REAL_DOTFILES" \
    --no-tty \
    --promptDefaults \
    2>/dev/null || true
}

teardown() {
  rm -rf "$TEST_DIR"
}

chezmoi_apply() {
  HOME="$TEST_HOME" chezmoi apply \
    --source "$REAL_DOTFILES" \
    --exclude=scripts \
    --no-tty \
    2>/dev/null
}

chezmoi_verify() {
  HOME="$TEST_HOME" chezmoi verify \
    --source "$REAL_DOTFILES" \
    --exclude=scripts \
    2>/dev/null
}

@test "chezmoi apply succeeds on clean HOME" {
  run chezmoi_apply
  [ "$status" -eq 0 ]
}

@test "symlink files are created as symlinks to repo" {
  chezmoi_apply

  # Core symlinks (always present)
  [ -L "$TEST_HOME/.zshrc" ]
  [ "$(readlink "$TEST_HOME/.zshrc")" = "$REAL_DOTFILES/home/zshrc" ]

  [ -L "$TEST_HOME/.zshenv" ]
  [ "$(readlink "$TEST_HOME/.zshenv")" = "$REAL_DOTFILES/home/zshenv" ]

  [ -L "$TEST_HOME/.gitignore_global" ]
  [ -L "$TEST_HOME/.git-editor" ]
  [ -L "$TEST_HOME/.gitcommit_template" ]
}

@test "full profile includes opinionated symlinks" {
  chezmoi_apply

  [ -L "$TEST_HOME/.ideavimrc" ]
  [ "$(readlink "$TEST_HOME/.ideavimrc")" = "$REAL_DOTFILES/home/ideavimrc" ]

  [ -L "$TEST_HOME/.tmux.conf" ]
  [ "$(readlink "$TEST_HOME/.tmux.conf")" = "$REAL_DOTFILES/home/tmux.conf" ]
}

@test "copy-mode files are regular files (not symlinks)" {
  chezmoi_apply

  [ -f "$TEST_HOME/.gitconfig" ] && [ ! -L "$TEST_HOME/.gitconfig" ]
  [ -f "$TEST_HOME/.editorconfig" ] && [ ! -L "$TEST_HOME/.editorconfig" ]
  [ -f "$TEST_HOME/.hushlogin" ] && [ ! -L "$TEST_HOME/.hushlogin" ]
  [ -f "$TEST_HOME/.npmrc" ] && [ ! -L "$TEST_HOME/.npmrc" ]
  [ -f "$TEST_HOME/.tigrc" ] && [ ! -L "$TEST_HOME/.tigrc" ]
}

@test "gitconfig hooksPath uses chezmoi sourceDir (portable)" {
  chezmoi_apply

  # hooksPath should resolve to the actual source dir, not hardcoded ~/apps/dotfiles
  grep -q "hooksPath = $REAL_DOTFILES/git-hooks" "$TEST_HOME/.gitconfig"
}

@test "copy-mode file contents match source" {
  chezmoi_apply

  diff -q "$REAL_DOTFILES/dot_editorconfig" "$TEST_HOME/.editorconfig"
  # hushlogin is an empty marker file — just verify it exists
  [ -f "$TEST_HOME/.hushlogin" ]
}

@test "npmrc renders the declared config at 0600" {
  chezmoi_apply

  grep -q "^save-exact=true" "$TEST_HOME/.npmrc"
  grep -q "^prefer-offline=true" "$TEST_HOME/.npmrc"
  [ "$(stat -f '%Lp' "$TEST_HOME/.npmrc")" = "600" ]
}

# `npm login` writes the registry token into ~/.npmrc itself. A plain managed
# file deleted it on every apply, so the credential has to survive the render.
@test "npmrc apply preserves a locally added registry credential" {
  chezmoi_apply
  printf '//registry.npmjs.org/:_authToken=test-token-value\n' >> "$TEST_HOME/.npmrc"

  chezmoi_apply

  grep -q "^//registry.npmjs.org/:_authToken=test-token-value$" "$TEST_HOME/.npmrc"
  grep -q "^save-exact=true" "$TEST_HOME/.npmrc"
}

@test "npmrc apply does not duplicate a preserved credential" {
  chezmoi_apply
  printf '//registry.npmjs.org/:_authToken=test-token-value\n' >> "$TEST_HOME/.npmrc"

  chezmoi_apply
  chezmoi_apply

  [ "$(grep -c '_authToken' "$TEST_HOME/.npmrc")" -eq 1 ]
}

@test "XDG config files are deployed" {
  chezmoi_apply

  [ -f "$TEST_HOME/.config/starship.toml" ]
  [ -f "$TEST_HOME/.config/atuin/config.toml" ]
  [ -d "$TEST_HOME/.config/ghostty" ]
  [ -d "$TEST_HOME/.config/lazygit" ]
}

@test "private_dot_ssh gets correct permissions" {
  chezmoi_apply

  [ -d "$TEST_HOME/.ssh" ]
  # chezmoi sets private_dot_ directories to 0700
  local perms
  perms="$(stat -f '%A' "$TEST_HOME/.ssh")"
  [ "$perms" = "700" ]
}

@test "chezmoiignore excludes repo-only files from HOME" {
  chezmoi_apply

  # These should NOT appear in HOME (listed in .chezmoiignore)
  [ ! -e "$TEST_HOME/bin" ]
  [ ! -e "$TEST_HOME/tests" ]
  [ ! -e "$TEST_HOME/modules" ]
  [ ! -e "$TEST_HOME/Makefile" ]
  [ ! -e "$TEST_HOME/README.md" ]
  [ ! -e "$TEST_HOME/AGENTS.md" ]
  [ ! -e "$TEST_HOME/CLAUDE.md" ]
  [ ! -e "$TEST_HOME/macos.sh" ]
  [ ! -e "$TEST_HOME/launchagents" ]
  [ ! -e "$TEST_HOME/mcp" ]
  [ ! -e "$TEST_HOME/TASKS.md" ]
  # Regression: these repo files/dirs were leaking to ~ root (see .chezmoiignore)
  [ ! -e "$TEST_HOME/ARCHITECTURE.md" ]
  [ ! -e "$TEST_HOME/ROADMAP.md" ]
  [ ! -e "$TEST_HOME/VISION.md" ]
  [ ! -e "$TEST_HOME/agent-hooks" ]
  [ ! -e "$TEST_HOME/commands" ]
  [ ! -e "$TEST_HOME/scripts" ]
  [ ! -e "$TEST_HOME/templates" ]
  [ ! -e "$TEST_HOME/vscode" ]
}

@test "chezmoiignore excludes every non-source root entry from HOME" {
  chezmoi_apply

  local entry name leaked=()
  for entry in "$REAL_DOTFILES"/*; do
    name="$(basename "$entry")"
    case "$name" in
      dot_*|private_*|symlink_*|modify_*|executable_*|create_*|exact_*|readonly_*|encrypted_*|empty_*|literal_*|remove_*|run_*) continue ;;
    esac
    if [ -e "$TEST_HOME/$name" ]; then
      leaked+=("$name")
    fi
  done
  [ "${#leaked[@]}" -eq 0 ] || { echo "missing from .chezmoiignore: ${leaked[*]}"; return 1; }
}

@test "chezmoi verify reports no differences after apply" {
  chezmoi_apply
  run chezmoi_verify
  [ "$status" -eq 0 ]
}

@test "chezmoi apply is idempotent (second run is no-op)" {
  chezmoi_apply
  # Second apply should also succeed
  run chezmoi_apply
  [ "$status" -eq 0 ]
  # And verify still clean
  run chezmoi_verify
  [ "$status" -eq 0 ]
}

@test "core profile excludes full-only files" {
  # Override config to core profile and re-init
  cat > "$TEST_HOME/.config/chezmoi/chezmoi.yaml" << EOF
sourceDir: "$REAL_DOTFILES"
encryption: age
age:
  identity: "$TEST_HOME/.config/chezmoi/key.txt"
  recipient: unused-no-encryption-configured
data:
  profile: "core"
  is_enterprise: false
  work_email_domain: "example.com"
  github_enterprise_host: "github.example.com"
  dotfiles_dir: "apps/dotfiles"
  repos_dir: "apps"
  brew_skip: []
  auto_upgrade: false
  use_ai_tools: false
  use_encryption: false
  git_work_name: "Test"
  git_work_email: "test@example.com"
  git_personal_enabled: false
  git_personal_name: ""
  git_personal_email: ""

EOF
  HOME="$TEST_HOME" chezmoi init \
    --source "$REAL_DOTFILES" \
    --no-tty \
    --promptDefaults \
    2>/dev/null || true

  chezmoi_apply

  # Core files should exist
  [ -f "$TEST_HOME/.gitconfig" ]
  [ -L "$TEST_HOME/.zshrc" ]
  [ -f "$TEST_HOME/.editorconfig" ]

  # Full-only files should NOT exist
  [ ! -e "$TEST_HOME/.ideavimrc" ]
  [ ! -e "$TEST_HOME/.tmux.conf" ]
  [ ! -e "$TEST_HOME/.config/ghostty" ]
  [ ! -e "$TEST_HOME/.config/lazygit" ]
}

@test "enterprise=false excludes enterprise SSH config" {
  chezmoi_apply

  # Main SSH dir should exist
  [ -d "$TEST_HOME/.ssh" ]
  # Enterprise config should be excluded
  [ ! -f "$TEST_HOME/.ssh/config.enterprise" ]
}

@test "chezmoiignore age fallback defaults to false (skip encrypted)" {
  # Render .chezmoiignore WITHOUT use_encryption in data — simulates fresh init
  local ignore_tmpl="$REAL_DOTFILES/.chezmoiignore"
  # The dig fallback must be false: unset use_encryption → skip encrypted files
  grep -q 'dig "use_encryption" false' "$ignore_tmpl"
}
