#!/usr/bin/env bats
# Tests for the scheduled Brewfile manifest audit workflow.

BREW_AUDIT_WORKFLOW="$BATS_TEST_DIRNAME/../.github/workflows/brew-audit.yml"
BREW_AUDIT_SCRIPT="$BATS_TEST_DIRNAME/../.github/scripts/brew-audit-manifest.sh"
CI_DOCS="$BATS_TEST_DIRNAME/../docs/ci-setup.md"

setup() {
  TEST_DIR="$(mktemp -d)"
  mkdir -p "$TEST_DIR/bin"
  export PATH="$TEST_DIR/bin:$PATH"
}

teardown() {
  rm -rf "$TEST_DIR"
}

write_fake_brew() {
  cat > "$TEST_DIR/bin/brew" <<'BREW'
#!/bin/bash
set -euo pipefail

case "$*" in
  info* | livecheck*)
    if [ "${HOMEBREW_NO_AUTO_UPDATE:-}" != "1" ]; then
      echo "expected HOMEBREW_NO_AUTO_UPDATE=1 for $*" >&2
      exit 8
    fi
    ;;
esac

case "$*" in
  "info --json=v2 --formula good")
    echo '{"formulae":[{"name":"good","full_name":"good","disabled":false,"deprecated":false}],"casks":[]}'
    ;;
  "info --json=v2 --formula missing")
    echo "No available formula with the name missing" >&2
    exit 1
    ;;
  "info --json=v2 --formula disabled")
    echo '{"formulae":[{"name":"disabled","full_name":"disabled","disabled":true,"disable_date":"2026-01-01","disable_reason":"upstream gone","deprecated":false}],"casks":[]}'
    ;;
  "info --json=v2 --formula deprecated")
    echo '{"formulae":[{"name":"deprecated","full_name":"deprecated","disabled":false,"deprecated":true,"deprecation_date":"2026-01-02","deprecation_reason":"use replacement"}],"casks":[]}'
    ;;
  "info --json=v2 --formula oldname")
    echo '{"formulae":[{"name":"newname","full_name":"newname","disabled":false,"deprecated":false,"oldnames":["oldname"]}],"casks":[]}'
    ;;
  "info --json=v2 --formula live-newer")
    echo '{"formulae":[{"name":"live-newer","full_name":"live-newer","disabled":false,"deprecated":false}],"casks":[]}'
    ;;
  "info --json=v2 --formula live-slow")
    echo '{"formulae":[{"name":"live-slow","full_name":"live-slow","disabled":false,"deprecated":false}],"casks":[]}'
    ;;
  "info --json=v2 --formula metadata-slow")
    sleep "${FAKE_BREW_METADATA_SLEEP:-5}"
    echo '{"formulae":[{"name":"metadata-slow","full_name":"metadata-slow","disabled":false,"deprecated":false}],"casks":[]}'
    ;;
  "info --json=v2 --cask good-cask")
    echo '{"formulae":[],"casks":[{"token":"good-cask","disabled":false,"deprecated":false}]}'
    ;;
  "livecheck --json --quiet --formula live-newer")
    echo '[{"formula":"live-newer","status":"newer versions available","version":{"current":"1.0","latest":"1.1"}}]'
    ;;
  "livecheck --json --quiet --formula live-slow")
    sleep "${FAKE_BREW_LIVECHECK_SLEEP:-5}"
    echo '[{"status":"up-to-date","version":{"current":"1.0","latest":"1.0"}}]'
    ;;
  livecheck*)
    echo '[{"status":"up-to-date","version":{"current":"1.0","latest":"1.0"}}]'
    ;;
  list* | outdated*)
    echo "installed-package checks are not allowed in manifest audit" >&2
    exit 9
    ;;
  *)
    echo "unexpected brew invocation: $*" >&2
    exit 2
    ;;
esac
BREW
  chmod +x "$TEST_DIR/bin/brew"
}

write_manifest() {
  cat > "$TEST_DIR/Brewfile.tmpl" <<'BREWFILE'
brew "good"
cask "good-cask"
brew "missing"
brew "disabled"
brew "deprecated"
brew "oldname"
brew "live-newer"
BREWFILE
}

@test "brew audit workflow delegates manifest checks to helper script" {
  grep -q '.github/scripts/brew-audit-manifest.sh .chezmoiscripts/run_onchange_brew.sh.tmpl' "$BREW_AUDIT_WORKFLOW"
}

@test "brew audit workflow no longer gates checks on installed runner packages" {
  ! grep -q 'brew list' "$BREW_AUDIT_WORKFLOW"
  ! grep -q 'brew outdated' "$BREW_AUDIT_WORKFLOW"
  ! grep -q 'not installed on runner' "$BREW_AUDIT_WORKFLOW"
}

@test "brew audit workflow grants issue write permission for actionable findings" {
  grep -q 'issues: write' "$BREW_AUDIT_WORKFLOW"
  grep -Fq 'AUDIT_LIST: ${{ steps.audit.outputs.list }}' "$BREW_AUDIT_WORKFLOW"
  grep -Fq -- '--body-file "$body_file"' "$BREW_AUDIT_WORKFLOW"
}

@test "brew audit helper checks formula and cask metadata without installing packages" {
  write_fake_brew
  write_manifest
  output_file="$TEST_DIR/github-output"

  run env GITHUB_OUTPUT="$output_file" "$BREW_AUDIT_SCRIPT" "$TEST_DIR/Brewfile.tmpl"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Checked 6 formulae and 1 casks"* ]]
  grep -q '^found=true$' "$output_file"
  grep -q 'formula `missing`: missing from Homebrew metadata' "$output_file"
  grep -q 'formula `disabled`: disabled since 2026-01-01 (upstream gone)' "$output_file"
  grep -q 'formula `deprecated`: deprecated since 2026-01-02 (use replacement)' "$output_file"
  grep -q 'formula `oldname`: metadata resolves to `newname`; update the Brewfile entry' "$output_file"
  grep -q 'formula `live-newer`: livecheck reports upstream 1.1 while Homebrew metadata has 1.0' "$output_file"
}

@test "brew audit helper bounds livecheck runtime and keeps metadata findings" {
  write_fake_brew
  cat > "$TEST_DIR/Brewfile.tmpl" <<'BREWFILE'
brew "disabled"
brew "live-slow"
BREWFILE
  output_file="$TEST_DIR/github-output"

  run env GITHUB_OUTPUT="$output_file" BREW_AUDIT_LIVECHECK_TIMEOUT=1 "$BREW_AUDIT_SCRIPT" "$TEST_DIR/Brewfile.tmpl"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Livecheck timeout: 1s per entry"* ]]
  grep -q '^found=true$' "$output_file"
  grep -q 'formula `disabled`: disabled since 2026-01-01 (upstream gone)' "$output_file"
  grep -q 'formula `live-slow`: livecheck timed out after 1s' "$output_file"
}

@test "brew audit helper bounds metadata runtime and keeps other findings" {
  write_fake_brew
  cat > "$TEST_DIR/Brewfile.tmpl" <<'BREWFILE'
brew "disabled"
brew "metadata-slow"
BREWFILE
  output_file="$TEST_DIR/github-output"

  start="$(date +%s)"
  run env GITHUB_OUTPUT="$output_file" BREW_AUDIT_METADATA_TIMEOUT=1 BREW_AUDIT_SKIP_LIVECHECK=1 FAKE_BREW_METADATA_SLEEP=10 "$BREW_AUDIT_SCRIPT" "$TEST_DIR/Brewfile.tmpl"
  elapsed="$(($(date +%s) - start))"

  [ "$status" -eq 0 ]
  [ "$elapsed" -lt 7 ]
  [[ "$output" == *"Metadata timeout: 1s per entry with HOMEBREW_NO_AUTO_UPDATE=1"* ]]
  grep -q '^found=true$' "$output_file"
  grep -q 'formula `disabled`: disabled since 2026-01-01 (upstream gone)' "$output_file"
  grep -q 'formula `metadata-slow`: metadata lookup timed out after 1s' "$output_file"
}

@test "brew audit helper can skip network-dependent livecheck checks" {
  write_fake_brew
  cat > "$TEST_DIR/Brewfile.tmpl" <<'BREWFILE'
brew "live-newer"
BREWFILE
  output_file="$TEST_DIR/github-output"

  run env GITHUB_OUTPUT="$output_file" BREW_AUDIT_SKIP_LIVECHECK=1 "$BREW_AUDIT_SCRIPT" "$TEST_DIR/Brewfile.tmpl"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Livecheck skipped because BREW_AUDIT_SKIP_LIVECHECK=1"* ]]
  grep -q '^found=false$' "$output_file"
  ! grep -q 'livecheck reports upstream' "$output_file"
}

@test "brew audit helper reports clean metadata as found=false" {
  write_fake_brew
  cat > "$TEST_DIR/Brewfile.tmpl" <<'BREWFILE'
brew "good"
cask "good-cask"
BREWFILE
  output_file="$TEST_DIR/github-output"

  run env GITHUB_OUTPUT="$output_file" "$BREW_AUDIT_SCRIPT" "$TEST_DIR/Brewfile.tmpl"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Checked 1 formulae and 1 casks"* ]]
  grep -q '^found=false$' "$output_file"
  [[ "$output" == *"All Brewfile entries resolved"* ]]
}

@test "CI docs explain metadata-based brew audit behavior" {
  grep -Fq 'gh workflow run brew-audit.yml' "$CI_DOCS"
  grep -Fq 'Homebrew metadata and livecheck' "$CI_DOCS"
  grep -Fq 'Packages do not need to be installed on the runner' "$CI_DOCS"
  grep -Fq 'BREW_AUDIT_METADATA_TIMEOUT' "$CI_DOCS"
  grep -Fq 'HOMEBREW_NO_AUTO_UPDATE=1' "$CI_DOCS"
  grep -Fq 'BREW_AUDIT_LIVECHECK_TIMEOUT' "$CI_DOCS"
  grep -Fq 'BREW_AUDIT_SKIP_LIVECHECK=1' "$CI_DOCS"
}
