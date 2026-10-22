#!/usr/bin/env bats
# Upstream feedback contract: agents working with dotfiles offer a safe issue
# report to fyodoriv/dotfiles, ask before posting, and say the author welcomes it.

DOTFILES_DIR="$BATS_TEST_DIRNAME/.."

section() {
  awk '/^## Report problems and ideas/{on=1; next} /^## /{on=0} on' "$DOTFILES_DIR/CONTRIBUTING.md"
}

@test "CONTRIBUTING.md welcomes reports and names the author" {
  section | grep -q "Fyodor, the author of dotfiles, is glad to get every report"
}

@test "CONTRIBUTING.md shows the safety steps: scrub, preview, yes before posting, second yes for a PR" {
  local text
  text="$(section)"
  [[ "$text" == *"agentbrew report --title"*"--repo fyodoriv/dotfiles"* ]]
  [[ "$text" == *"never posts anything on its own"* ]]
  [[ "$text" == *"Only after your yes"* ]]
  [[ "$text" == *"second yes"* ]]
  [[ "$text" == *"re-scan of the final text"* ]]
}

@test "CONTRIBUTING.md documents the opt-out" {
  section | grep -q "agentbrew report --off"
}

@test "AGENTS.md points every fork and clone at the report flow" {
  grep -q "CONTRIBUTING.md#report-problems-and-ideas" "$DOTFILES_DIR/AGENTS.md"
}

@test "Agentfile installs the report-upstream skill for every dotfiles user" {
  grep -qE '^  - report-upstream\b' "$DOTFILES_DIR/Agentfile.yaml"
}

@test "owner rules make the feedback loop a rule for every shareable app" {
  grep -q "Every app or tool I build to share ships an upstream feedback loop" "$DOTFILES_DIR/config/agentfile-owner-rules.yaml"
}

@test "Agentfile installs watch-issues and owner rules name the watched repos" {
  grep -qE '^  - watch-issues\b' "$DOTFILES_DIR/Agentfile.yaml"
  grep -q '/loop /watch-issues ~/apps/tooling/agentbrew ~/apps/tooling/dotfiles' "$DOTFILES_DIR/config/agentfile-owner-rules.yaml"
}
