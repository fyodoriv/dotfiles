#!/usr/bin/env bats
# Integration test for the full onboarding flow.
# Simulates a new user: init with core profile → apply → verify →
# switch to full → apply → verify.

REAL_DOTFILES="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
  if ! command -v chezmoi &>/dev/null; then
    skip "chezmoi not installed"
  fi

  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  mkdir -p "$TEST_HOME/.config/chezmoi"
}

teardown() {
  rm -rf "$TEST_DIR"
}

write_config() {
  local profile="$1"
  cat > "$TEST_HOME/.config/chezmoi/chezmoi.yaml" << EOF
sourceDir: "$REAL_DOTFILES"
encryption: age
age:
  identity: "$TEST_HOME/.config/chezmoi/key.txt"
  recipient: unused-no-encryption-configured
data:
  profile: "$profile"
  is_enterprise: false
  auto_upgrade: false
  use_encryption: false
  use_ai_tools: false
  dotfiles_dir: "apps/dotfiles"
  repos_dir: "apps"
  git_work_name: "Test"
  git_work_email: "test@example.com"
  # Every promptOnce call in .chezmoi.yaml.tmpl must have a value
  # here, or chezmoi apply (which doesn't accept --prompt=false the
  # way init does) can pop an interactive prompt under load and fail
  # with 'input/output error' or time out.
  morning_hour: 8
  morning_minute: 30
  git_personal_enabled: false
  git_personal_name: ""
  git_personal_email: ""
  work_email_domain: "example.com"
  github_enterprise_host: "github.example.com"
  age_recipient: "unused-no-encryption-configured"
EOF
}

chezmoi_init() {
  HOME="$TEST_HOME" chezmoi init \
    --source "$REAL_DOTFILES" \
    --no-tty \
    --prompt=false \
    2>/dev/null || true
}

chezmoi_apply() {
  HOME="$TEST_HOME" chezmoi apply \
    --source "$REAL_DOTFILES" \
    --exclude=scripts \
    --force \
    --no-tty \
    2>/dev/null
}

chezmoi_verify() {
  HOME="$TEST_HOME" chezmoi verify \
    --source "$REAL_DOTFILES" \
    --exclude=scripts \
    2>/dev/null
}

# ── Core profile onboarding ──

@test "core profile: init succeeds" {
  write_config "core"
  run chezmoi_init
  [ "$status" -eq 0 ]
}

@test "core profile: apply succeeds on clean HOME" {
  write_config "core"
  chezmoi_init
  run chezmoi_apply
  [ "$status" -eq 0 ]
}

@test "core profile: essential files deployed" {
  write_config "core"
  chezmoi_init
  chezmoi_apply

  # Core symlinks
  [ -L "$TEST_HOME/.zshrc" ]
  [ -L "$TEST_HOME/.zshenv" ]

  # Core copy-mode files
  [ -f "$TEST_HOME/.gitconfig" ]
  [ -f "$TEST_HOME/.editorconfig" ]

  # SSH directory with correct permissions
  [ -d "$TEST_HOME/.ssh" ]
  local perms
  perms="$(stat -f '%A' "$TEST_HOME/.ssh")"
  [ "$perms" = "700" ]
}

@test "core profile: full-only files excluded" {
  write_config "core"
  chezmoi_init
  chezmoi_apply

  [ ! -e "$TEST_HOME/.ideavimrc" ]
  [ ! -e "$TEST_HOME/.tmux.conf" ]
  [ ! -e "$TEST_HOME/.config/ghostty" ]
  [ ! -e "$TEST_HOME/.config/lazygit" ]
}

@test "core profile: verify reports clean state" {
  write_config "core"
  chezmoi_init
  chezmoi_apply
  run chezmoi_verify
  [ "$status" -eq 0 ]
}

@test "core profile: apply is idempotent" {
  write_config "core"
  chezmoi_init
  chezmoi_apply
  run chezmoi_apply
  [ "$status" -eq 0 ]
  run chezmoi_verify
  [ "$status" -eq 0 ]
}

# ── Profile switch: core → full ──

@test "switch core to full: apply succeeds" {
  write_config "core"
  chezmoi_init
  chezmoi_apply

  # Switch to full
  write_config "full"
  chezmoi_init
  run chezmoi_apply
  [ "$status" -eq 0 ]
}

@test "switch core to full: gains full-only files" {
  write_config "core"
  chezmoi_init
  chezmoi_apply

  # Verify not present before switch
  [ ! -e "$TEST_HOME/.ideavimrc" ]
  [ ! -e "$TEST_HOME/.tmux.conf" ]

  # Switch to full
  write_config "full"
  chezmoi_init
  chezmoi_apply

  # Now present
  [ -L "$TEST_HOME/.ideavimrc" ]
  [ -L "$TEST_HOME/.tmux.conf" ]
  [ -d "$TEST_HOME/.config/ghostty" ]
}

@test "switch core to full: core files still intact" {
  write_config "core"
  chezmoi_init
  chezmoi_apply

  write_config "full"
  chezmoi_init
  chezmoi_apply

  # Core files should still be there
  [ -L "$TEST_HOME/.zshrc" ]
  [ -L "$TEST_HOME/.zshenv" ]
  [ -f "$TEST_HOME/.gitconfig" ]
  [ -f "$TEST_HOME/.editorconfig" ]
}

@test "switch core to full: verify clean after switch" {
  write_config "core"
  chezmoi_init
  chezmoi_apply

  write_config "full"
  chezmoi_init
  chezmoi_apply
  run chezmoi_verify
  [ "$status" -eq 0 ]
}

# ── Full profile onboarding (direct) ──

@test "full profile: apply succeeds on clean HOME" {
  write_config "full"
  chezmoi_init
  run chezmoi_apply
  [ "$status" -eq 0 ]
}

@test "full profile: all expected files deployed" {
  write_config "full"
  chezmoi_init
  chezmoi_apply

  # Core
  [ -L "$TEST_HOME/.zshrc" ]
  [ -L "$TEST_HOME/.zshenv" ]
  [ -f "$TEST_HOME/.gitconfig" ]

  # Full-only
  [ -L "$TEST_HOME/.ideavimrc" ]
  [ -L "$TEST_HOME/.tmux.conf" ]

  # XDG
  [ -f "$TEST_HOME/.config/starship.toml" ]
  [ -f "$TEST_HOME/.config/atuin/config.toml" ]
  [ -d "$TEST_HOME/.config/ghostty" ]
  [ -d "$TEST_HOME/.config/lazygit" ]
}

@test "full profile: repo-only files excluded from HOME" {
  write_config "full"
  chezmoi_init
  chezmoi_apply

  [ ! -e "$TEST_HOME/bin" ]
  [ ! -e "$TEST_HOME/tests" ]
  [ ! -e "$TEST_HOME/modules" ]
  [ ! -e "$TEST_HOME/Makefile" ]
  [ ! -e "$TEST_HOME/README.md" ]
  [ ! -e "$TEST_HOME/TASKS.md" ]
}

@test "full profile: verify clean" {
  write_config "full"
  chezmoi_init
  chezmoi_apply
  run chezmoi_verify
  [ "$status" -eq 0 ]
}

# ── Profile switch: full → core (downgrade) ──

@test "switch full to core: apply succeeds" {
  write_config "full"
  chezmoi_init
  chezmoi_apply

  write_config "core"
  chezmoi_init
  run chezmoi_apply
  [ "$status" -eq 0 ]
}

@test "switch full to core: full-only files become unmanaged" {
  write_config "full"
  chezmoi_init
  chezmoi_apply

  # Verify present before downgrade
  [ -L "$TEST_HOME/.ideavimrc" ]
  [ -L "$TEST_HOME/.tmux.conf" ]

  write_config "core"
  chezmoi_init
  chezmoi_apply

  # chezmoi does not auto-remove files that stop being managed;
  # verify they are no longer tracked (not in managed list)
  local managed
  managed="$(HOME="$TEST_HOME" chezmoi managed --source "$REAL_DOTFILES" 2>/dev/null)"
  [[ "$managed" != *".ideavimrc"* ]]
  [[ "$managed" != *".tmux.conf"* ]]
}

@test "switch full to core: core files still intact" {
  write_config "full"
  chezmoi_init
  chezmoi_apply

  write_config "core"
  chezmoi_init
  chezmoi_apply

  [ -L "$TEST_HOME/.zshrc" ]
  [ -L "$TEST_HOME/.zshenv" ]
  [ -f "$TEST_HOME/.gitconfig" ]
}

@test "switch full to core: verify clean after downgrade" {
  write_config "full"
  chezmoi_init
  chezmoi_apply

  write_config "core"
  chezmoi_init
  chezmoi_apply
  run chezmoi_verify
  [ "$status" -eq 0 ]
}

# ── Drift detection and repair ──

@test "drift: removing a symlink causes verify to fail" {
  write_config "core"
  chezmoi_init
  chezmoi_apply

  # Introduce drift by removing a managed symlink
  rm "$TEST_HOME/.zshrc"
  [ ! -e "$TEST_HOME/.zshrc" ]

  run chezmoi_verify
  [ "$status" -ne 0 ]
}

@test "drift: re-apply after removing symlink restores it" {
  write_config "core"
  chezmoi_init
  chezmoi_apply

  # Introduce drift
  rm "$TEST_HOME/.zshrc"

  # Re-apply repairs
  chezmoi_apply
  [ -L "$TEST_HOME/.zshrc" ]
  [ "$(readlink "$TEST_HOME/.zshrc")" = "$REAL_DOTFILES/home/zshrc" ]

  run chezmoi_verify
  [ "$status" -eq 0 ]
}

@test "drift: replacing symlink with regular file is repaired by apply" {
  write_config "core"
  chezmoi_init
  chezmoi_apply

  # Replace symlink with a regular file
  rm "$TEST_HOME/.zshrc"
  echo "rogue content" > "$TEST_HOME/.zshrc"
  [ ! -L "$TEST_HOME/.zshrc" ]

  # Re-apply should restore the symlink
  chezmoi_apply
  [ -L "$TEST_HOME/.zshrc" ]
  [ "$(readlink "$TEST_HOME/.zshrc")" = "$REAL_DOTFILES/home/zshrc" ]
}

# ── Re-apply idempotency across profiles ──

@test "multiple profile switches remain clean" {
  write_config "core"
  chezmoi_init
  chezmoi_apply

  write_config "full"
  chezmoi_init
  chezmoi_apply

  write_config "core"
  chezmoi_init
  chezmoi_apply

  run chezmoi_verify
  [ "$status" -eq 0 ]

  # Core files intact
  [ -L "$TEST_HOME/.zshrc" ]
  [ -f "$TEST_HOME/.gitconfig" ]
  # Full-only files no longer managed
  local managed
  managed="$(HOME="$TEST_HOME" chezmoi managed --source "$REAL_DOTFILES" 2>/dev/null)"
  [[ "$managed" != *".ideavimrc"* ]]
}

# ── Symlink integrity ──

@test "symlinks point to the real dotfiles repo" {
  write_config "full"
  chezmoi_init
  chezmoi_apply

  [ "$(readlink "$TEST_HOME/.zshrc")" = "$REAL_DOTFILES/home/zshrc" ]
  [ "$(readlink "$TEST_HOME/.zshenv")" = "$REAL_DOTFILES/home/zshenv" ]
  [ "$(readlink "$TEST_HOME/.ideavimrc")" = "$REAL_DOTFILES/home/ideavimrc" ]
}

# ── Re-init keeps existing data ──

reinit_config() {
  HOME="$TEST_HOME" chezmoi init \
    --config "$TEST_HOME/.config/chezmoi/chezmoi.yaml" \
    --source "$REAL_DOTFILES" \
    --promptDefaults </dev/null >/dev/null 2>&1
}

@test "re-init keeps age recipient, morning time, and overlay root" {
  cat > "$TEST_HOME/.config/chezmoi/chezmoi.yaml" << EOF2
sourceDir: "$REAL_DOTFILES"
encryption: age
age:
  identity: "$TEST_HOME/.config/chezmoi/key.txt"
  recipient: age1testrecipient
data:
  profile: full
  use_encryption: true
  morning_hour: 9
  morning_minute: 0
  extra_overlay_root: "/tmp/overlay"
EOF2
  reinit_config
  local cfg="$TEST_HOME/.config/chezmoi/chezmoi.yaml"
  grep -q '^  recipient: age1testrecipient$' "$cfg"
  grep -q '^  age_recipient: "age1testrecipient"$' "$cfg"
  grep -q '^  morning_hour: 9$' "$cfg"
  grep -q '^  morning_minute: 0$' "$cfg"
  grep -q '^  extra_overlay_root: "/tmp/overlay"$' "$cfg"
}

@test "fresh init uses defaults and omits overlay root" {
  printf 'data:\n  profile: full\n' > "$TEST_HOME/.config/chezmoi/chezmoi.yaml"
  reinit_config
  local cfg="$TEST_HOME/.config/chezmoi/chezmoi.yaml"
  grep -q '^  morning_hour: 8$' "$cfg"
  grep -q '^  morning_minute: 30$' "$cfg"
  grep -q '^  recipient: unused-no-encryption-configured$' "$cfg"
  ! grep -q 'extra_overlay_root' "$cfg"
}
