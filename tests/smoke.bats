#!/usr/bin/env bats
# Smoke tests — verify basic script hygiene across the entire repo

DOTFILES_DIR="$BATS_TEST_DIRNAME/.."

@test "all core scripts have set -e or set -euo pipefail" {
  local missing=()
  for script in "$DOTFILES_DIR"/macos.sh "$DOTFILES_DIR"/macos-visual.sh "$DOTFILES_DIR"/macos-apps.sh; do
    [ ! -f "$script" ] && continue
    if ! grep -qE "^set -[A-Za-z]*e" "$script"; then
      missing+=("$(basename "$script")")
    fi
  done
  [ ${#missing[@]} -eq 0 ] || { echo "Missing set -e: ${missing[*]}"; return 1; }
}

@test "all bin scripts are executable" {
  local non_exec=()
  for script in "$DOTFILES_DIR"/bin/*; do
    [ ! -f "$script" ] && continue
    if [ ! -x "$script" ]; then
      non_exec+=("$(basename "$script")")
    fi
  done
  [ ${#non_exec[@]} -eq 0 ] || { echo "Not executable: ${non_exec[*]}"; return 1; }
}

@test "all bin scripts have a shebang line" {
  local missing=()
  for script in "$DOTFILES_DIR"/bin/*; do
    [ ! -f "$script" ] && continue
    [ -L "$script" ] && continue
    file -b "$script" | grep -q 'Mach-O' && continue
    local first_line
    first_line=$(head -1 "$script")
    if [[ ! "$first_line" =~ ^#! ]]; then
      missing+=("$(basename "$script")")
    fi
  done
  [ ${#missing[@]} -eq 0 ] || { echo "Missing shebang: ${missing[*]}"; return 1; }
}

@test "dotfiles --help exits 0" {
  run bash "$DOTFILES_DIR/bin/dotfiles" --help
  [ "$status" -eq 0 ]
}

@test "launchagent plists have no hardcoded home paths" {
  local hardcoded=()
  for plist in "$DOTFILES_DIR"/launchagents/*.plist "$DOTFILES_DIR"/launchagents/*.plist.tmpl; do
    [ ! -f "$plist" ] && continue
    if grep -q "/Users/" "$plist"; then
      hardcoded+=("$(basename "$plist")")
    fi
  done
  [ ${#hardcoded[@]} -eq 0 ] || { echo "Hardcoded /Users/ in: ${hardcoded[*]}"; return 1; }
}

@test "no hardcoded home directory in bin scripts or shell config" {
  # A literal /Users/<name>/ path only works on one machine (rule 3). Tools
  # that edit ~/.zshrc (it symlinks into home/) can write one back in.
  local found=() file
  for file in "$DOTFILES_DIR"/bin/* "$DOTFILES_DIR"/home/*; do
    [ -f "$file" ] || continue
    if grep -qE '/Users/[A-Za-z0-9._-]+/' "$file" && ! grep -qE '/Users/Shared/' "$file"; then
      found+=("${file#"$DOTFILES_DIR"/}")
    fi
  done
  [ ${#found[@]} -eq 0 ] || { echo "Hardcoded home path in: ${found[*]}"; return 1; }
}

@test "no hardcoded usr-local python3 interpreter in tests" {
  # The arm64 + endpoint-security migration removed the usr-local
  # (framework/intel) python3 from operator machines. Test harnesses that
  # hardcode that interpreter path fail with exit 127 on those hosts —
  # observed 2026-06-12 when the entire local-ai-loop/agent bats family
  # broke. Tests must use PATH `python3` (dotfiles bin shim → signed uv
  # python). The needle is built from parts so this file doesn't flag
  # itself.
  local needle="/usr/local/bin/"
  needle="${needle}python3"
  local found=()
  for spec in "$DOTFILES_DIR"/tests/*.bats; do
    [ ! -f "$spec" ] && continue
    if grep -qF "$needle" "$spec"; then
      found+=("$(basename "$spec")")
    fi
  done
  [ ${#found[@]} -eq 0 ] || { echo "Hardcoded interpreter in: ${found[*]}"; return 1; }
}

@test "dotfiles-doctor includes chezmoi health checks" {
  # Scope to smallest module so doctor runs in ~3s instead of ~30s —
  # the chezmoi section runs unconditionally, so one module is enough.
  # Will fail due to real system checks, that's ok.
  # Use a unique lock so this test doesn't compete with doctor.bats's
  # setup_file (which also runs cursor-only doctors in parallel).
  local lock_dir; lock_dir="$(mktemp -d)"
  run env DOTFILES_LOCK="$lock_dir/dotfiles.lock" \
    bash "$DOTFILES_DIR/bin/dotfiles-doctor" --module cursor 2>&1
  rm -rf "$lock_dir"
  # Output should contain the Chezmoi section header
  [[ "$output" == *"Chezmoi"* ]]
  # Should have parsed at least some chezmoi doctor results
  [[ "$output" == *"chezmoi version"* ]] || [[ "$output" == *"chezmoi executable"* ]]
}

@test "CDP launchagents are gated behind full profile" {
  local script="$DOTFILES_DIR/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  # The should_skip_agent function must gate all CDP Chrome agents
  grep -q 'agent-browser-chrome|debug-chrome|tooling-chrome|chrome-debug' "$script"
  # The PROFILE variable must be set from chezmoi template data
  grep -q 'PROFILE="{{ .profile }}"' "$script"
}

@test "company-specific doctor checks are gated behind IS_ENTERPRISE" {
  # Chrome work profile check must be enterprise-only
  grep -q 'IS_ENTERPRISE.*true' "$DOTFILES_DIR/modules/chrome/doctor.sh"
  # dotfiles-doctor must read IS_ENTERPRISE from chezmoi
  grep -q 'IS_ENTERPRISE' "$DOTFILES_DIR/bin/dotfiles-doctor"
}

@test "chezmoi source files use correct naming conventions" {
  # Verify symlink template files exist (contain path to home/)
  [ -f "$DOTFILES_DIR/symlink_dot_zshrc.tmpl" ]
  # gitconfig is copy-mode template (uses chezmoi.sourceDir for hooksPath)
  [ -f "$DOTFILES_DIR/dot_gitconfig.tmpl" ]
  # Verify actual config content lives in home/
  [ -f "$DOTFILES_DIR/home/zshrc" ]
  [ -f "$DOTFILES_DIR/home/gitconfig" ]
  # Verify copy mode files exist
  [ -f "$DOTFILES_DIR/dot_editorconfig" ]
  # Verify private dir exists
  [ -d "$DOTFILES_DIR/private_dot_ssh" ]
}
