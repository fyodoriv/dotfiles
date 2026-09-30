#!/usr/bin/env bats
# Tests for setup-dock script

load test_helper

DOCK_CMD="$BATS_TEST_DIRNAME/../bin/setup-dock"

@test "setup-dock script exists and is executable" {
  [ -f "$DOCK_CMD" ]
  [ -x "$DOCK_CMD" ]
}

@test "setup-dock script has correct shebang" {
  head -1 "$DOCK_CMD" | grep -q '#!/bin/bash'
}

@test "setup-dock script uses strict mode" {
  grep -q 'set -euo pipefail' "$DOCK_CMD"
}

@test "setup-dock script sources colors.sh" {
  grep -q 'source.*lib/colors.sh' "$DOCK_CMD"
}

@test "setup-dock supports --dry-run flag" {
  grep -q 'DRY_RUN=' "$DOCK_CMD"
  grep -q '\-\-dry-run' "$DOCK_CMD"
}

@test "setup-dock supports --yes flag to skip confirmation" {
  grep -q 'SKIP_CONFIRM=' "$DOCK_CMD"
  grep -q '\-\-yes' "$DOCK_CMD"
}

@test "setup-dock backs up current Dock before changes" {
  grep -q 'defaults export com.apple.dock' "$DOCK_CMD"
  grep -q 'DOCK_BACKUP=' "$DOCK_CMD"
}

@test "setup-dock stores backup in ~/.dotfiles-snapshots" {
  grep -q 'SNAPSHOTS_DIR.*dotfiles-snapshots' "$DOCK_CMD"
}

@test "setup-dock shows restore command in backup message" {
  grep -q 'defaults import com.apple.dock' "$DOCK_CMD"
}

@test "setup-dock dry-run exits 0 without modifying Dock" {
  grep -q 'dry-run.*Would clear Dock' "$DOCK_CMD"
  grep -q 'No changes made' "$DOCK_CMD"
}

@test "setup-dock adds primary workflow apps" {
  grep -q 'WebStorm.app' "$DOCK_CMD"
  grep -q 'Ghostty.app' "$DOCK_CMD"
  grep -q 'Google Chrome.app' "$DOCK_CMD"
}

@test "setup-dock adds communication apps" {
  grep -q 'Slack.app' "$DOCK_CMD"
  grep -q 'zoom.us.app' "$DOCK_CMD"
}

@test "setup-dock adds folder shortcuts" {
  grep -q 'add_folder "/Applications"' "$DOCK_CMD"
  grep -q 'add_folder.*DOTFILES_REPOS_DIR' "$DOCK_CMD"
  grep -q 'add_folder "$HOME/Downloads"' "$DOCK_CMD"
}

@test "setup-dock clears Dock before adding apps" {
  grep -q 'persistent-apps -array$' "$DOCK_CMD"
  grep -q 'persistent-others -array$' "$DOCK_CMD"
}

@test "setup-dock restarts Dock after changes" {
  grep -q 'killall Dock' "$DOCK_CMD"
}

@test "setup-dock uses gum for confirmation when available" {
  grep -q 'gum confirm' "$DOCK_CMD"
}
