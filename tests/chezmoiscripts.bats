#!/usr/bin/env bats
# Tests for .chezmoiscripts/ lifecycle scripts — bootstrap, brew, macos, launchagents, cache-inits

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$BATS_TEST_DIRNAME/.."
  export HOME="$TEST_HOME"
  mkdir -p "$HOME"

  # Mock bin directory
  MOCK_BIN="$TEST_DIR/bin"
  mkdir -p "$MOCK_BIN"
  export PATH="$MOCK_BIN:$PATH"

  # Tests must run in env isolation. chezmoi exports DOTFILES_REPOS_DIR from
  # ~/.config/dotfiles/env.sh on every shell startup; without unsetting it,
  # any HOME-relative probe (e.g. lib/agentbrew-locate.sh) resolves against
  # the operator's real home instead of $TEST_HOME and tests find the real
  # checkout instead of the fixture they created.
  # BASH_ENV can also prepend the real dotfiles wrappers to PATH in child
  # shells, bypassing the per-test command stubs.
  unset BASH_ENV DOTFILES_REPOS_DIR DOTFILES_DIR DOTFILES_IS_AGENT \
    CHEZMOI_SOURCE_DIR CHEZMOI_WORKING_TREE
  export DOTFILES_ALLOW_BLOCKED_NODE_PUBLISHER=1
}

write_fake_claude() {
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/claude" <<'MOCK'
#!/bin/bash
printf '%s\n' "${ANTHROPIC_MODEL:-__unset__}" > "$HOME/claude-model"
printf '%s\n' "$*" > "$HOME/claude-args"
MOCK
  chmod +x "$HOME/.local/bin/claude"
}

write_fake_devin_version() {
  local version="$1"
  local kind="${2:-real}"
  local bin_dir="$HOME/.local/share/devin/cli/_versions/$version/bin"
  mkdir -p "$bin_dir"

  if [ "$kind" = "real" ]; then
    printf '\xcf\xfa\xed\xfe' > "$bin_dir/devin"
  else
    cat > "$bin_dir/devin" <<'MOCK'
#!/bin/bash
echo "stub devin"
MOCK
  fi
  chmod +x "$bin_dir/devin"
}

point_current_devin_version() {
  local version="$1"
  local versions_dir="$HOME/.local/share/devin/cli/_versions"
  ln -sfn "$versions_dir/$version" "$versions_dir/current"
}

render_git_personal_includeif_script() {
  local mode="$1"
  local source="$TEST_DOTFILES/.chezmoiscripts/run_onchange_after_git-personal-includeif.sh.tmpl"
  local rendered="$TEST_DIR/git-personal-includeif-$mode.sh"

  if [ "$mode" = "enabled" ]; then
    awk '
      /^\{\{ if dig "git_personal_enabled"/ { next }
      /^\{\{- end \}\}/ { next }
      { print }
    ' "$source" > "$rendered"
  else
    awk '
      /^\{\{ if dig "git_personal_enabled"/ { skip = 1; next }
      /^\{\{- end \}\}/ { skip = 0; next }
      !skip { print }
    ' "$source" > "$rendered"
  fi

  chmod +x "$rendered"
  printf '%s\n' "$rendered"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# ── run_once_bootstrap.sh ────────────────────────────────────────

@test "bootstrap: script exists and is executable" {
  [ -f "$TEST_DOTFILES/.chezmoiscripts/run_once_bootstrap.sh" ]
}

@test "bootstrap: uses strict mode" {
  grep -q 'set -euo pipefail' "$TEST_DOTFILES/.chezmoiscripts/run_once_bootstrap.sh"
}

@test "bootstrap: exits 1 when Xcode CLT missing" {
  # Mock xcode-select to fail
  cat > "$MOCK_BIN/xcode-select" << 'MOCK'
#!/bin/bash
if [ "${1:-}" = "-p" ]; then exit 1; fi
if [ "${1:-}" = "--install" ]; then exit 0; fi
MOCK
  chmod +x "$MOCK_BIN/xcode-select"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_once_bootstrap.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Installing Xcode Command Line Tools"* ]]
}

@test "bootstrap: continues when Xcode CLT present" {
  # Mock xcode-select to succeed
  cat > "$MOCK_BIN/xcode-select" << 'MOCK'
#!/bin/bash
[ "${1:-}" = "-p" ] && echo "/Library/Developer/CommandLineTools" && exit 0
MOCK
  chmod +x "$MOCK_BIN/xcode-select"

  # Mock brew (already installed)
  cat > "$MOCK_BIN/brew" << 'MOCK'
#!/bin/bash
if [ "${1:-}" = "--version" ]; then echo "Homebrew 4.3.0"; fi
MOCK
  chmod +x "$MOCK_BIN/brew"

  # Mock chezmoi (already installed)
  cat > "$MOCK_BIN/chezmoi" << 'MOCK'
#!/bin/bash
true
MOCK
  chmod +x "$MOCK_BIN/chezmoi"

  # Ensure gitconfig.local exists to skip interactive prompt
  touch "$HOME/.gitconfig.local"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_once_bootstrap.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Xcode Command Line Tools"* ]]
  [[ "$output" == *"Bootstrap complete"* ]]
}

@test "bootstrap: skips git config setup when gitconfig.local exists" {
  cat > "$MOCK_BIN/xcode-select" << 'MOCK'
#!/bin/bash
[ "${1:-}" = "-p" ] && echo "/Library/Developer/CommandLineTools" && exit 0
MOCK
  chmod +x "$MOCK_BIN/xcode-select"

  cat > "$MOCK_BIN/brew" << 'MOCK'
#!/bin/bash
if [ "${1:-}" = "--version" ]; then echo "Homebrew 4.3.0"; fi
MOCK
  chmod +x "$MOCK_BIN/brew"

  cat > "$MOCK_BIN/chezmoi" << 'MOCK'
#!/bin/bash
true
MOCK
  chmod +x "$MOCK_BIN/chezmoi"

  # Pre-create gitconfig.local
  touch "$HOME/.gitconfig.local"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_once_bootstrap.sh"
  [ "$status" -eq 0 ]
  # Should NOT prompt for git identity
  [[ "$output" != *"Setting up git identity"* ]]
}

@test "bootstrap: checks both Apple Silicon and Intel brew paths" {
  grep -q '/opt/homebrew/bin/brew' "$TEST_DOTFILES/.chezmoiscripts/run_once_bootstrap.sh"
  grep -q '/usr/local/bin/brew' "$TEST_DOTFILES/.chezmoiscripts/run_once_bootstrap.sh"
}

@test "bootstrap: DOTFILES_DIR resolver tolerates chezmoi tmpdir invocation" {
  # Regression test: chezmoi stages scripts in a tmpdir (e.g.
  # /var/folders/.../chezmoi-XXX/) before running them. The old resolver
  # was `cd "$(dirname $0)/.." && pwd || echo "$HOME/apps/dotfiles"` —
  # because `cd <tmpdir>/..` succeeds, the `||` fallback never fired and
  # DOTFILES_DIR silently became the tmpdir's parent. gitconfig.local
  # setup then skipped because the marker file wasn't there.
  #
  # This test stages the bootstrap script in a tmpdir, mocks chezmoi
  # source-path to point at a fake repo with the marker file, and
  # asserts the resolver finds the repo (not the tmpdir).

  cat > "$MOCK_BIN/xcode-select" << 'MOCK'
#!/bin/bash
[ "${1:-}" = "-p" ] && echo "/Library/Developer/CommandLineTools" && exit 0
MOCK
  chmod +x "$MOCK_BIN/xcode-select"
  cat > "$MOCK_BIN/brew" << 'MOCK'
#!/bin/bash
[ "${1:-}" = "--version" ] && echo "Homebrew 4.3.0"
MOCK
  chmod +x "$MOCK_BIN/brew"

  # Build a fake dotfiles checkout with the marker file the resolver
  # probes for, then mock chezmoi source-path to return it.
  local fake_repo="$TEST_DIR/fake-dotfiles"
  mkdir -p "$fake_repo"
  cat > "$fake_repo/gitconfig.local.example" << 'EX'
[user]
  name = Example
  email = example@example.com
EX
  cat > "$MOCK_BIN/chezmoi" << MOCK
#!/bin/bash
[ "\${1:-}" = "source-path" ] && echo "$fake_repo" && exit 0
exit 0
MOCK
  chmod +x "$MOCK_BIN/chezmoi"

  # Stage the bootstrap script in a tmpdir-style location. The first
  # resolver branch (cd dirname/..) will resolve to TEST_DIR which does
  # NOT contain gitconfig.local.example — forcing the chezmoi branch.
  local tmpdir_staging="$TEST_DIR/chezmoi-cache/.chezmoiscripts"
  mkdir -p "$tmpdir_staging"
  cp "$TEST_DOTFILES/.chezmoiscripts/run_once_bootstrap.sh" "$tmpdir_staging/"

  # Pipe name + email so the interactive `read` prompt doesn't block.
  # The gitconfig.local copy + prompts only run once; the resolver hit
  # the chezmoi branch BEFORE the prompts fired.
  run bash -c "printf 'Test User\ntest@example.com\n' | bash '$tmpdir_staging/run_once_bootstrap.sh'"
  [ "$status" -eq 0 ]
  # gitconfig.local should have been created from the fake repo's example
  [ -f "$HOME/.gitconfig.local" ]
  grep -q "example@example.com" "$HOME/.gitconfig.local"
}

@test "bootstrap: DOTFILES_DIR resolver continues gracefully when no checkout found" {
  cat > "$MOCK_BIN/xcode-select" << 'MOCK'
#!/bin/bash
[ "${1:-}" = "-p" ] && echo "/Library/Developer/CommandLineTools" && exit 0
MOCK
  chmod +x "$MOCK_BIN/xcode-select"
  cat > "$MOCK_BIN/brew" << 'MOCK'
#!/bin/bash
[ "${1:-}" = "--version" ] && echo "Homebrew 4.3.0"
MOCK
  chmod +x "$MOCK_BIN/brew"

  # chezmoi exists but source-path returns nothing
  cat > "$MOCK_BIN/chezmoi" << 'MOCK'
#!/bin/bash
exit 1
MOCK
  chmod +x "$MOCK_BIN/chezmoi"

  # Override the fallback location so it points at an empty tmpdir
  export DOTFILES_REPOS_DIR="$TEST_DIR/empty-apps"

  # Stage in a tmpdir where dirname/.. doesn't have the marker file
  local tmpdir_staging="$TEST_DIR/chezmoi-cache/.chezmoiscripts"
  mkdir -p "$tmpdir_staging"
  cp "$TEST_DOTFILES/.chezmoiscripts/run_once_bootstrap.sh" "$tmpdir_staging/"

  run bash "$tmpdir_staging/run_once_bootstrap.sh"
  # Must exit cleanly (not 1) — bootstrap continues even when DOTFILES_DIR
  # resolution fails; gitconfig setup just skips with a soft warning.
  [ "$status" -eq 0 ]
  [[ "$output" == *"Could not resolve dotfiles repo path"* ]]
  [[ "$output" == *"Bootstrap complete"* ]]
}

# ── run_onchange_brew.sh.tmpl ────────────────────────────────────

@test "brew template: uses strict mode" {
  grep -q 'set -euo pipefail' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
}

@test "brew template: exits gracefully when brew missing" {
  grep -q 'command -v brew' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
  grep -q 'exit 0' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
}

@test "brew template: core packages are always included" {
  # Core packages should be outside any profile conditional
  grep -q 'brew "git-delta"' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
  grep -q 'brew "fzf"' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
  grep -q 'brew "starship"' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
  grep -q 'brew "ripgrep"' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
}

@test "brew template: full-only packages gated by profile" {
  # tmux, ghostty, extras should be inside {{ if eq .profile "full" }}
  local in_full_block=false
  while IFS= read -r line; do
    if [[ "$line" == *'if eq .profile "full"'* ]]; then in_full_block=true; fi
    if $in_full_block && [[ "$line" == *'brew "tmux"'* ]]; then
      # Found tmux inside full block — pass
      return 0
    fi
    if $in_full_block && [[ "$line" == *'end'* ]]; then in_full_block=false; fi
  done < "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
  # If we get here, tmux was not in the full block
  false
}

@test "brew template: enterprise packages gated by is_enterprise" {
  grep -q '{{ if .is_enterprise' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
  # cloudflared should be in the enterprise block
  # (awscli was moved to a user-dir install — see run_after_uv-tools.sh / TASKS.md)
  local in_enterprise=false
  while IFS= read -r line; do
    if [[ "$line" == *'if .is_enterprise'* ]]; then in_enterprise=true; fi
    if $in_enterprise && [[ "$line" == *'brew "cloudflared"'* ]]; then return 0; fi
    if $in_enterprise && [[ "$line" == *'end'* ]]; then in_enterprise=false; fi
  done < "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
  false
}

@test "brew template: brew_skip filter uses portable sed backup syntax" {
  grep -q 'range .brew_skip' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
  grep -q "sed -i.bak " "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
  grep -q 'rm -f "$RENDERED.bak"' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
}

@test "brew template: excludes blocked desktop app casks" {
  ! grep -qiE 'cask "(raycast|lunar)"' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
}

@test "brew template: uses tealdeer instead of deprecated tldr formula" {
  grep -q 'brew "tealdeer"' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
  ! grep -q 'brew "tldr"' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
}

@test "brew template: no inline organisation-specific tap blocks" {
  # The brew template used to ship an inline `brew tap` block guarded
  # by `is_enterprise && contains <hostname-fragment>`. That block
  # moved to the overlay's brewfile/Brewfile when it left dotfiles;
  # the EXTRA_BREWFILE hook is the supported way to plug additional
  # taps in. Reintroducing an inline tap would silently undo that
  # boundary.
  ! grep -q '^[[:space:]]*if brew tap ' \
    "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
  ! grep -q '^[[:space:]]*brew install [a-z][a-z0-9_-]*/[a-z][a-z0-9_-]*/' \
    "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
}

@test "brew template: uses temp file with cleanup trap" {
  grep -q 'mktemp' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
  grep -q "trap 'rm -f" "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
}

# ── run_onchange_brew.sh.tmpl: EXTRA_BREWFILE overlay hook ───────
# Pin the contract that an organisation-specific overlay can plug
# in an additional Brewfile via $EXTRA_BREWFILE (env var) or the
# chezmoi data key `extra_brewfile`. Mirrors $EXTRA_DOCTOR_DIR.

@test "brew template: declares EXTRA_BREWFILE with env var precedence" {
  # Env var beats chezmoi data; both default empty when neither is set.
  grep -Fq 'EXTRA_BREWFILE="${EXTRA_BREWFILE:-' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
}

@test "brew template: reads chezmoi data key extra_brewfile via dig" {
  # dig "extra_brewfile" "" . returns "" when the key is absent so the
  # rendered shell stays a literal `EXTRA_BREWFILE="${EXTRA_BREWFILE:-}"`.
  grep -Fq 'dig "extra_brewfile" "" .' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
}

@test "brew template: guards overlay invocation behind a file-exists check" {
  # Both the variable being non-empty AND the path existing must hold.
  # Either alone would silently regress (calling `brew bundle` on a
  # missing file aborts the lifecycle script, configured-but-absent
  # overlays must not break a fresh checkout).
  grep -Fq '[ -n "$EXTRA_BREWFILE" ] && [ -f "$EXTRA_BREWFILE" ]' \
    "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
}

@test "brew template: invokes brew bundle against the overlay path" {
  grep -Fq 'brew bundle --no-upgrade --file="$EXTRA_BREWFILE"' \
    "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
}

# Render the brew template with an injected `extra_brewfile` value into a
# plain bash script we can execute against a mocked `brew`. The `set .`
# prefix mutates the chezmoi data dict for this single render so the test
# is hermetic against the developer's actual chezmoi config — we feed
# every data key the template touches inline so the test does not depend
# on the user's `~/.config/chezmoi/chezmoi.yaml`.
_render_brew_with_extra_brewfile() {
  local extra="$1"
  local out="$TEST_DIR/run_onchange_brew.rendered.sh"
  # Seed the data context with non-enterprise defaults so the
  # hostname-specific conditional block compiles out and the rendered
  # script only exercises the core brewfile + EXTRA_BREWFILE branches.
  local prefix=''
  prefix+='{{- $_ := set . "profile" "full" -}}'
  prefix+='{{- $_ := set . "is_enterprise" false -}}'
  prefix+='{{- $_ := set . "github_enterprise_host" "github.example.com" -}}'
  prefix+='{{- $_ := set . "brew_skip" (list) -}}'
  if [ -n "$extra" ]; then
    prefix+="{{- \$_ := set . \"extra_brewfile\" \"$extra\" -}}"
  fi
  {
    printf '%s\n' "$prefix"
    cat "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
  } | chezmoi execute-template --source "$TEST_DOTFILES" > "$out"
  chmod +x "$out"
  printf '%s\n' "$out"
}

# Mock `brew` so the rendered lifecycle script runs end-to-end without a
# real Homebrew install. Logs every call with its args to $HOME/brew-calls.log.
_install_mock_brew() {
  cat > "$MOCK_BIN/brew" <<'MOCK'
#!/bin/bash
printf '%s\n' "brew $*" >> "$HOME/brew-calls.log"
exit 0
MOCK
  chmod +x "$MOCK_BIN/brew"
}

@test "brew template: renders overlay branch when chezmoi data extra_brewfile is set and file exists" {
  # (a) Render the template against a temp HOME with a fake overlay
  # Brewfile, (b) assert the rendered script invokes `brew bundle --file=`
  # against the overlay path. Together with the no-overlay test below
  # this pins the EXTRA_BREWFILE behaviour end-to-end.
  TEST_DOTFILES="$BATS_TEST_DIRNAME/.."  # use the real source for chezmoi
  local overlay_dir="$TEST_DIR/overlay/brewfile"
  local overlay_file="$overlay_dir/Brewfile"
  mkdir -p "$overlay_dir"
  printf 'brew "test-overlay-pkg"\n' > "$overlay_file"
  _install_mock_brew

  local rendered
  rendered="$(_render_brew_with_extra_brewfile "$overlay_file")"
  run bash "$rendered"

  [ "$status" -eq 0 ]
  [ -s "$HOME/brew-calls.log" ]
  grep -Fq "brew bundle --no-upgrade --file=$overlay_file" "$HOME/brew-calls.log"
  [[ "$output" == *"Running overlay brew bundle from $overlay_file"* ]]
  [[ "$output" == *"Overlay Brewfile applied"* ]]
}

@test "brew template: skips overlay branch when neither env nor chezmoi data is set" {
  # (c) When no EXTRA_BREWFILE env var is exported and chezmoi data has
  # no `extra_brewfile`, the rendered script must not call `brew bundle`
  # for an overlay. The main brewfile call still happens — that's the
  # baseline `brew bundle --file=` we exclude from the assertion.
  TEST_DOTFILES="$BATS_TEST_DIRNAME/.."
  _install_mock_brew

  local rendered
  rendered="$(_render_brew_with_extra_brewfile "")"
  unset EXTRA_BREWFILE
  run bash "$rendered"

  [ "$status" -eq 0 ]
  [[ "$output" != *"overlay brew bundle"* ]]
  [[ "$output" != *"Overlay Brewfile applied"* ]]
  # Only the main brewfile call should appear; no overlay bundle invocation.
  ! grep -E 'brew bundle .* --file=[^$]' "$HOME/brew-calls.log" \
    | grep -vE '/(tmp|var)' >/dev/null
}

@test "brew template: skips overlay branch when chezmoi data points at a missing file" {
  # Configured-but-absent overlay path must be a silent no-op, not a hard
  # failure. Otherwise a fresh laptop without the overlay checked out would
  # abort `chezmoi apply` in the middle of the brew lifecycle.
  TEST_DOTFILES="$BATS_TEST_DIRNAME/.."
  _install_mock_brew

  local missing_path="$TEST_DIR/overlay/does-not-exist/Brewfile"
  local rendered
  rendered="$(_render_brew_with_extra_brewfile "$missing_path")"
  run bash "$rendered"

  [ "$status" -eq 0 ]
  [[ "$output" != *"overlay brew bundle"* ]]
  [[ "$output" != *"Overlay Brewfile applied"* ]]
  ! grep -Fq "brew bundle --no-upgrade --file=$missing_path" "$HOME/brew-calls.log"
}

@test "brew template: env var EXTRA_BREWFILE overrides chezmoi data when both are set" {
  # The env var wins because the rendered shell uses `${EXTRA_BREWFILE:-...}`
  # — the chezmoi-data value is only the fallback default.
  TEST_DOTFILES="$BATS_TEST_DIRNAME/.."
  _install_mock_brew

  local data_path="$TEST_DIR/overlay-from-data/Brewfile"
  local env_dir="$TEST_DIR/overlay-from-env"
  local env_path="$env_dir/Brewfile"
  mkdir -p "$env_dir" "$(dirname "$data_path")"
  printf 'brew "from-env"\n' > "$env_path"
  printf 'brew "from-data"\n' > "$data_path"

  local rendered
  rendered="$(_render_brew_with_extra_brewfile "$data_path")"
  EXTRA_BREWFILE="$env_path" run bash "$rendered"

  [ "$status" -eq 0 ]
  grep -Fq "brew bundle --no-upgrade --file=$env_path" "$HOME/brew-calls.log"
  ! grep -Fq "brew bundle --no-upgrade --file=$data_path" "$HOME/brew-calls.log"
}

# ── run_after_claude-wrapper.sh ─────────────────────────────────

@test "claude wrapper: no-op when real CLI is missing" {
  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_claude-wrapper.sh"

  [ "$status" -eq 0 ]
  [ ! -e "$HOME/bin/claude" ]
}

@test "claude wrapper: creates executable wrapper in ~/bin" {
  write_fake_claude

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_claude-wrapper.sh"

  [ "$status" -eq 0 ]
  [ -x "$HOME/bin/claude" ]
  grep -Fq 'unset ANTHROPIC_MODEL' "$HOME/bin/claude"
  grep -Fq 'exec "$REAL_CLAUDE" "$@"' "$HOME/bin/claude"
}

@test "claude wrapper: replaces stale enterprise-error wrapper content" {
  write_fake_claude
  mkdir -p "$HOME/bin"
  cat > "$HOME/bin/claude" <<'STALE'
#!/bin/bash
echo "inaccessible on Enterprise accounts"
unset ANTHROPIC_MODEL
STALE
  chmod +x "$HOME/bin/claude"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_claude-wrapper.sh"

  [ "$status" -eq 0 ]
  ! grep -Fq 'inaccessible on Enterprise accounts' "$HOME/bin/claude"
  grep -Fq 'Managed by dotfiles' "$HOME/bin/claude"
}

@test "claude wrapper: strips ANTHROPIC_MODEL before execing real CLI" {
  write_fake_claude
  bash "$TEST_DOTFILES/.chezmoiscripts/run_after_claude-wrapper.sh"

  run env ANTHROPIC_MODEL=leaked "$HOME/bin/claude" one two

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/claude-model")" = "__unset__" ]
  # Wrapper injects `--name "[<basename(PWD)>]"` ahead of user args when the
  # user didn't already pass one (Ghostty-tab-title visibility — see wrapper
  # comments). User's positional args are preserved at the tail.
  args="$(cat "$HOME/claude-args")"
  [[ "$args" == "--name "*" --permission-mode bypassPermissions one two" ]]
}

@test "claude wrapper: injects --name with cwd basename when user didn't pass one" {
  write_fake_claude
  bash "$TEST_DOTFILES/.chezmoiscripts/run_after_claude-wrapper.sh"

  # Use a stable predictable cwd so the basename is deterministic.
  local prev_pwd=$PWD
  mkdir -p "$TEST_DIR/some-folder"
  cd "$TEST_DIR/some-folder"

  run "$HOME/bin/claude" foo

  cd "$prev_pwd"
  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/claude-args")" = "--name [some-folder] --permission-mode bypassPermissions foo" ]
}

@test "claude wrapper: respects user-provided --name (long form)" {
  write_fake_claude
  bash "$TEST_DOTFILES/.chezmoiscripts/run_after_claude-wrapper.sh"

  run "$HOME/bin/claude" --name my-session

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/claude-args")" = "--permission-mode bypassPermissions --name my-session" ]
}

@test "claude wrapper: respects user-provided -n (short form)" {
  write_fake_claude
  bash "$TEST_DOTFILES/.chezmoiscripts/run_after_claude-wrapper.sh"

  run "$HOME/bin/claude" -n short

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/claude-args")" = "--permission-mode bypassPermissions -n short" ]
}

@test "claude wrapper: respects user-provided permission mode" {
  write_fake_claude
  bash "$TEST_DOTFILES/.chezmoiscripts/run_after_claude-wrapper.sh"

  run "$HOME/bin/claude" --permission-mode auto prompt

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/claude-args")" = "--name [$(basename "$PWD")] --permission-mode auto prompt" ]
}

@test "claude wrapper: treats dangerously-skip-permissions as explicit permission mode" {
  write_fake_claude
  bash "$TEST_DOTFILES/.chezmoiscripts/run_after_claude-wrapper.sh"

  run "$HOME/bin/claude" --dangerously-skip-permissions prompt

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/claude-args")" = "--name [$(basename "$PWD")] --dangerously-skip-permissions prompt" ]
}

# ── run_after_devin-caffeinate.sh ─────────────────────────────────

@test "devin wrapper: no-op when real CLI is missing" {
  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_devin-caffeinate.sh"

  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/bin/devin" ]
}

@test "devin wrapper: installs restart-safe direct exec wrapper" {
  write_fake_devin_version "2026.5.1-1" real
  point_current_devin_version "2026.5.1-1"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_devin-caffeinate.sh"

  [ "$status" -eq 0 ]
  [ -x "$HOME/.local/bin/devin" ]
  grep -Fq 'exec "$REAL_DEVIN" "$@"' "$HOME/.local/bin/devin"
  ! grep -Fq 'caffeinate' "$HOME/.local/bin/devin"
  [[ "$output" == *"Devin wrapper installed"* ]]
}

@test "devin wrapper: rolls back stub current binary to newest real version" {
  local versions_dir="$HOME/.local/share/devin/cli/_versions"
  write_fake_devin_version "2026.5.1-1" real
  write_fake_devin_version "2026.5.2-1" real
  write_fake_devin_version "2026.5.3-1" stub
  touch -t 202605010101 "$versions_dir/2026.5.1-1"
  touch -t 202605020101 "$versions_dir/2026.5.2-1"
  touch -t 202605030101 "$versions_dir/2026.5.3-1"
  point_current_devin_version "2026.5.3-1"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_devin-caffeinate.sh"

  [ "$status" -eq 0 ]
  [ "$(readlink "$versions_dir/current")" = "$versions_dir/2026.5.2-1" ]
  [ -x "$HOME/.local/bin/devin" ]
  [[ "$output" == *"rolling back to last real version"* ]]
  [[ "$output" == *"Rolled back devin current"* ]]
}

@test "devin wrapper: leaves a real current binary in place" {
  local versions_dir="$HOME/.local/share/devin/cli/_versions"
  write_fake_devin_version "2026.5.2-1" real
  point_current_devin_version "2026.5.2-1"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_devin-caffeinate.sh"

  [ "$status" -eq 0 ]
  [ "$(readlink "$versions_dir/current")" = "$versions_dir/2026.5.2-1" ]
  [[ "$output" != *"Rolled back devin current"* ]]
}

@test "devin wrapper: keeps an already-correct wrapper untouched" {
  write_fake_devin_version "2026.5.1-1" real
  point_current_devin_version "2026.5.1-1"
  bash "$TEST_DOTFILES/.chezmoiscripts/run_after_devin-caffeinate.sh"
  printf '\n# sentinel\n' >> "$HOME/.local/bin/devin"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_devin-caffeinate.sh"

  [ "$status" -eq 0 ]
  grep -Fq '# sentinel' "$HOME/.local/bin/devin"
  [ "$output" = "" ]
}

@test "devin wrapper: replaces stale caffeinate wrapper content" {
  write_fake_devin_version "2026.5.1-1" real
  point_current_devin_version "2026.5.1-1"
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/devin" <<'STALE'
#!/bin/bash
export ANTHROPIC_MODEL=stale
exec caffeinate -di devin-real "$@"
STALE
  chmod +x "$HOME/.local/bin/devin"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_devin-caffeinate.sh"

  [ "$status" -eq 0 ]
  grep -Fq 'exec "$REAL_DEVIN" "$@"' "$HOME/.local/bin/devin"
  ! grep -Fq 'caffeinate' "$HOME/.local/bin/devin"
  ! grep -Fq 'ANTHROPIC_MODEL' "$HOME/.local/bin/devin"
}

@test "devin wrapper: replaces symlinked wrapper" {
  write_fake_devin_version "2026.5.1-1" real
  point_current_devin_version "2026.5.1-1"
  mkdir -p "$HOME/.local/bin"
  ln -s /usr/local/bin/devin "$HOME/.local/bin/devin"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_devin-caffeinate.sh"

  [ "$status" -eq 0 ]
  [ -f "$HOME/.local/bin/devin" ]
  [ ! -L "$HOME/.local/bin/devin" ]
  grep -Fq 'exec "$REAL_DEVIN" "$@"' "$HOME/.local/bin/devin"
}

@test "devin wrapper: execs directly for interactive sessions" {
  write_fake_devin_version "2026.5.1-1" real
  point_current_devin_version "2026.5.1-1"
  bash "$TEST_DOTFILES/.chezmoiscripts/run_after_devin-caffeinate.sh"

  cat > "$MOCK_BIN/caffeinate" <<'MOCK'
#!/bin/bash
echo "caffeinate should not run" >&2
exit 99
MOCK
  chmod +x "$MOCK_BIN/caffeinate"

  cat > "$HOME/.local/share/devin/cli/_versions/current/bin/devin" <<'MOCK'
#!/bin/bash
printf '%s\n' "$@" > "$HOME/devin-args"
MOCK
  chmod +x "$HOME/.local/share/devin/cli/_versions/current/bin/devin"

  run "$HOME/.local/bin/devin" chat

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/devin-args")" = "chat" ]
}

@test "devin wrapper: skips watchdog for single-turn print modes" {
  write_fake_devin_version "2026.5.1-1" real
  point_current_devin_version "2026.5.1-1"
  bash "$TEST_DOTFILES/.chezmoiscripts/run_after_devin-caffeinate.sh"

  cat > "$MOCK_BIN/caffeinate" <<'MOCK'
#!/bin/bash
echo "caffeinate should not run" >&2
exit 99
MOCK
  chmod +x "$MOCK_BIN/caffeinate"

  cat > "$HOME/.local/share/devin/cli/_versions/current/bin/devin" <<'MOCK'
#!/bin/bash
printf '%s\n' "$@" >> "$HOME/devin-args"
MOCK
  chmod +x "$HOME/.local/share/devin/cli/_versions/current/bin/devin"

  run "$HOME/.local/bin/devin" -p hello
  [ "$status" -eq 0 ]
  run "$HOME/.local/bin/devin" --print world
  [ "$status" -eq 0 ]
  [ "$(sed -n '1p' "$HOME/devin-args")" = "-p" ]
  [ "$(sed -n '2p' "$HOME/devin-args")" = "hello" ]
  [ "$(sed -n '3p' "$HOME/devin-args")" = "--print" ]
  [ "$(sed -n '4p' "$HOME/devin-args")" = "world" ]
}

@test "devin wrapper: carries the title-watchdog block" {
  write_fake_devin_version "2026.5.1-1" real
  point_current_devin_version "2026.5.1-1"
  bash "$TEST_DOTFILES/.chezmoiscripts/run_after_devin-caffeinate.sh"

  # The watchdog block has three load-bearing pieces:
  #   - the tag that the installer uses to detect freshness
  #   - the OSC 2 emission that sets the title
  #   - the cleanup trap that reaps the background watchdog
  grep -Fq 'title-watchdog-from-cwd' "$HOME/.local/bin/devin"
  grep -Fq "printf '\\e]2;%s\\a'" "$HOME/.local/bin/devin"
  grep -Fq "trap _cleanup EXIT INT TERM HUP" "$HOME/.local/bin/devin"
}

@test "devin wrapper: print mode bypasses the watchdog entirely" {
  write_fake_devin_version "2026.5.1-1" real
  point_current_devin_version "2026.5.1-1"
  bash "$TEST_DOTFILES/.chezmoiscripts/run_after_devin-caffeinate.sh"

  # The -p/--print branch is BEFORE the watchdog setup, so an `exec` lands
  # there directly. Static check: the print-branch exec sits before any
  # `printf '\e]2;` emission, which means single-turn invocations never
  # mutate the operator's title.
  local exec_line title_line
  exec_line=$(grep -n '^    -p|--print)' "$HOME/.local/bin/devin" | cut -d: -f1)
  title_line=$(grep -n "printf '\\\\e\\]2;" "$HOME/.local/bin/devin" | head -1 | cut -d: -f1)
  [ -n "$exec_line" ]
  [ -n "$title_line" ]
  [ "$exec_line" -lt "$title_line" ]
}

# ── run_after_agentbrew-sync.sh ───────────────────────────────────

@test "agentbrew sync: uses PATH agentbrew with sync --agentfile" {
  local resolved_dotfiles
  resolved_dotfiles="$(cd "$TEST_DOTFILES" && pwd)"
  cat > "$MOCK_BIN/agentbrew" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" > "$HOME/agentbrew-args"
MOCK
  chmod +x "$MOCK_BIN/agentbrew"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_agentbrew-sync.sh"

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/agentbrew-args")" = "sync --no-recommended --agentfile $resolved_dotfiles/Agentfile.yaml" ]
  [[ "$output" == *"agentbrew synced from Agentfile"* ]]
}

@test "agentbrew sync: falls back to local tsx checkout" {
  local resolved_dotfiles
  resolved_dotfiles="$(cd "$TEST_DOTFILES" && pwd)"
  mkdir -p "$HOME/apps/agentbrew/node_modules/.bin" "$HOME/apps/agentbrew/src"
  cat > "$HOME/apps/agentbrew/node_modules/.bin/tsx" <<'MOCK'
#!/bin/bash
printf '%s\n' "$*" > "$HOME/tsx-args"
MOCK
  chmod +x "$HOME/apps/agentbrew/node_modules/.bin/tsx"

  run env PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "$TEST_DOTFILES/.chezmoiscripts/run_after_agentbrew-sync.sh"

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/tsx-args")" = "$HOME/apps/agentbrew/src/cli.ts sync --no-recommended --agentfile $resolved_dotfiles/Agentfile.yaml" ]
  [[ "$output" == *"agentbrew synced from Agentfile"* ]]
}

@test "agentbrew sync: resolves DOTFILES_DIR via chezmoi source-path under tmpdir execution" {
  # When `dotfiles apply` runs the script, chezmoi copies it to /var/folders/.../
  # before executing — so `$(dirname "$0")/..` resolves to a tmpdir, NOT the
  # repo. The script must fall back to either `chezmoi source-path` or a
  # known layout. We simulate this by copying the script to a tmpdir and
  # mocking chezmoi to return the test dotfiles dir.
  local resolved_dotfiles
  resolved_dotfiles="$(cd "$TEST_DOTFILES" && pwd)"

  local script_tmp="$TEST_DIR/tmp-script"
  mkdir -p "$script_tmp"
  cp "$TEST_DOTFILES/.chezmoiscripts/run_after_agentbrew-sync.sh" "$script_tmp/run.sh"
  chmod +x "$script_tmp/run.sh"

  # Mock chezmoi to return the real dotfiles dir
  cat > "$MOCK_BIN/chezmoi" <<MOCK
#!/bin/bash
[ "\$1" = "source-path" ] && printf '%s\n' '$resolved_dotfiles'
MOCK
  chmod +x "$MOCK_BIN/chezmoi"

  # Mock node + the dist/cli.js so the script reaches sync
  mkdir -p "$HOME/apps/tooling/agentbrew/dist"
  touch "$HOME/apps/tooling/agentbrew/dist/cli.js"
  chmod +x "$HOME/apps/tooling/agentbrew/dist/cli.js"
  cat > "$MOCK_BIN/node" <<'MOCK'
#!/bin/bash
shift
printf '%s' "$*" > "$HOME/dist-args"
MOCK
  chmod +x "$MOCK_BIN/node"

  run env PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin" bash "$script_tmp/run.sh"

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/dist-args")" = "sync --no-recommended --agentfile $resolved_dotfiles/Agentfile.yaml" ]
}

@test "agentbrew sync: locates checkout at ~/apps/tooling/agentbrew (monorepo layout)" {
  local resolved_dotfiles
  resolved_dotfiles="$(cd "$TEST_DOTFILES" && pwd)"
  mkdir -p "$HOME/apps/tooling/agentbrew/dist"
  # Real Windsurf CLI invokes `node $dist/cli.js`. The script calls node with
  # the cli.js path as argv[1], so we mock node itself to record argv[2..].
  cat > "$MOCK_BIN/node" <<'MOCK'
#!/bin/bash
shift  # drop the cli.js path
printf '%s' "$*" > "$HOME/dist-args"
MOCK
  chmod +x "$MOCK_BIN/node"
  touch "$HOME/apps/tooling/agentbrew/dist/cli.js"
  chmod +x "$HOME/apps/tooling/agentbrew/dist/cli.js"

  run env PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "$TEST_DOTFILES/.chezmoiscripts/run_after_agentbrew-sync.sh"

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/dist-args")" = "sync --no-recommended --agentfile $resolved_dotfiles/Agentfile.yaml" ]
  [[ "$output" == *"agentbrew synced from Agentfile"* ]]
}

@test "agentbrew sync: prefers dist/cli.js over tsx when both exist" {
  local resolved_dotfiles
  resolved_dotfiles="$(cd "$TEST_DOTFILES" && pwd)"
  mkdir -p "$HOME/apps/agentbrew/node_modules/.bin" \
           "$HOME/apps/agentbrew/src" \
           "$HOME/apps/agentbrew/dist"

  # tsx should NOT be invoked when dist/cli.js exists.
  cat > "$HOME/apps/agentbrew/node_modules/.bin/tsx" <<'MOCK'
#!/bin/bash
printf 'tsx invoked\n' > "$HOME/wrong-path-marker"
MOCK
  chmod +x "$HOME/apps/agentbrew/node_modules/.bin/tsx"

  # Mock node so we can record what dist/cli.js was called with.
  cat > "$MOCK_BIN/node" <<'MOCK'
#!/bin/bash
shift
printf '%s' "$*" > "$HOME/dist-args"
MOCK
  chmod +x "$MOCK_BIN/node"
  touch "$HOME/apps/agentbrew/dist/cli.js"
  chmod +x "$HOME/apps/agentbrew/dist/cli.js"

  run env PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "$TEST_DOTFILES/.chezmoiscripts/run_after_agentbrew-sync.sh"

  [ "$status" -eq 0 ]
  [ "$(cat "$HOME/dist-args")" = "sync --no-recommended --agentfile $resolved_dotfiles/Agentfile.yaml" ]
  [ ! -f "$HOME/wrong-path-marker" ]
}

@test "agentbrew sync: skips when Agentfile is missing" {
  local fixture_dotfiles
  fixture_dotfiles="$TEST_DIR/dotfiles-without-agentfile"
  mkdir -p "$fixture_dotfiles/.chezmoiscripts" "$fixture_dotfiles/lib"
  cp "$TEST_DOTFILES/.chezmoiscripts/run_after_agentbrew-sync.sh" "$fixture_dotfiles/.chezmoiscripts/run_after_agentbrew-sync.sh"
  cp "$TEST_DOTFILES/lib/agentbrew-locate.sh" "$fixture_dotfiles/lib/agentbrew-locate.sh"
  # No Agentfile.yaml — script must detect the missing file and skip.

  cat > "$MOCK_BIN/agentbrew" <<'MOCK'
#!/bin/bash
echo "agentbrew should not run" >&2
exit 99
MOCK
  chmod +x "$MOCK_BIN/agentbrew"

  run bash "$fixture_dotfiles/.chezmoiscripts/run_after_agentbrew-sync.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"No Agentfile.yaml in dotfiles"* ]]
  [[ "$output" != *"agentbrew should not run"* ]]
}

@test "agentbrew sync: skips when no CLI is available" {
  run env PATH="$MOCK_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    bash "$TEST_DOTFILES/.chezmoiscripts/run_after_agentbrew-sync.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"agentbrew not available"* ]]
}

@test "agentbrew sync: reports sync failures as non-fatal" {
  cat > "$MOCK_BIN/agentbrew" <<'MOCK'
#!/bin/bash
echo "sync exploded"
exit 42
MOCK
  chmod +x "$MOCK_BIN/agentbrew"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_agentbrew-sync.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"sync exploded"* ]]
  [[ "$output" == *"agentbrew sync failed (non-fatal)"* ]]
}

# ── run_onchange_after_git-personal-includeif.sh.tmpl ─────────────

@test "git personal includeIf: injects managed block and preserves existing content" {
  script="$(render_git_personal_includeif_script enabled)"
  cat > "$HOME/.gitconfig.local" <<'CONFIG'
[user]
	name = Work User
	email = work@example.com
CONFIG

  run bash "$script"

  [ "$status" -eq 0 ]
  grep -Fq '[user]' "$HOME/.gitconfig.local"
  grep -Fq '# BEGIN git-personal-includeif' "$HOME/.gitconfig.local"
  grep -Fq 'hasconfig:remote.*.url:https://github.com/*/*' "$HOME/.gitconfig.local"
  grep -Fq 'hasconfig:remote.*.url:git@github.com:*/*' "$HOME/.gitconfig.local"
  grep -Fq 'hasconfig:remote.*.url:ssh://git@github.com/*/*' "$HOME/.gitconfig.local"
}

@test "git personal includeIf: removes managed block when disabled" {
  script="$(render_git_personal_includeif_script disabled)"
  cat > "$HOME/.gitconfig.local" <<'CONFIG'
[user]
	name = Work User

# BEGIN git-personal-includeif (managed by dotfiles — do not edit)
[includeIf "hasconfig:remote.*.url:https://github.com/*/*"]
	path = ~/.gitconfig.personal
# END git-personal-includeif
CONFIG

  run bash "$script"

  [ "$status" -eq 0 ]
  grep -Fq '[user]' "$HOME/.gitconfig.local"
  ! grep -Fq '# BEGIN git-personal-includeif' "$HOME/.gitconfig.local"
  [ ! -e "$HOME/.gitconfig.local.tmp" ]
}

@test "git personal includeIf: refreshes block without leaving temp file" {
  script="$(render_git_personal_includeif_script enabled)"
  cat > "$HOME/.gitconfig.local" <<'CONFIG'
[core]
	editor = vim

# BEGIN git-personal-includeif (managed by dotfiles — do not edit)
stale = true
# END git-personal-includeif
CONFIG

  run bash "$script"

  [ "$status" -eq 0 ]
  grep -Fq '[core]' "$HOME/.gitconfig.local"
  ! grep -Fq 'stale = true' "$HOME/.gitconfig.local"
  [ "$(grep -cF '# BEGIN git-personal-includeif' "$HOME/.gitconfig.local")" -eq 1 ]
  [ ! -e "$HOME/.gitconfig.local.tmp" ]
}

# ── run_onchange_macos.sh.tmpl ───────────────────────────────────

@test "macos template: uses strict mode" {
  grep -q 'set -euo pipefail' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_macos.sh.tmpl"
}

@test "macos template: always runs core macos.sh" {
  grep -q 'bash.*macos.sh' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_macos.sh.tmpl"
}

@test "macos template: visual and app scripts gated by full profile" {
  grep -q 'if eq .profile "full"' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_macos.sh.tmpl"
  grep -q 'macos-visual.sh' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_macos.sh.tmpl"
  grep -q 'macos-apps.sh' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_macos.sh.tmpl"
}

@test "macos template: includes sha256sum hashes for change detection" {
  grep -q 'sha256sum' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_macos.sh.tmpl"
  local hash_count
  hash_count=$(grep -c 'sha256sum' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_macos.sh.tmpl")
  [ "$hash_count" -eq 4 ]
}

# ── run_onchange_launchagents.sh.tmpl ────────────────────────────

@test "launchagents template: uses strict mode" {
  grep -q 'set -euo pipefail' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
}

@test "launchagents template: defines should_skip_agent function" {
  grep -q 'should_skip_agent()' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
}

@test "launchagents template: CDP agents require full profile" {
  grep -q 'agent-browser-chrome|debug-chrome|tooling-chrome|chrome-debug' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  # Verify they check for full profile
  local script="$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  awk '/agent-browser-chrome\|debug-chrome\|tooling-chrome\|chrome-debug/,/;;/' "$script" | grep -q 'PROFILE.*!=.*full'
}

@test "launchagents template: cursor-priority supports Ghostty and WebStorm" {
  local script="$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  local cursor_priority_block
  cursor_priority_block=$(awk '/cursor-priority\)/,/;;/' "$script")
  [[ "$cursor_priority_block" == *"Ghostty"* ]]
  [[ "$cursor_priority_block" == *"WebStorm"* ]]
}

@test "launchagents template: upgrade agent requires auto_upgrade=true" {
  local script="$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  awk '/upgrade\)/,/;;/' "$script" | grep -q 'AUTO_UPGRADE.*!=.*true'
}

@test "launchagents template: graceful skip when launchctl missing" {
  grep -q 'command -v launchctl' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  grep -q 'exit 0' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
}

@test "launchagents template: processes both .plist.tmpl and .plist files" {
  grep -q '\.plist\.tmpl' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  grep -q '\.plist;' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl" || \
  grep -q '\*.plist' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
}

@test "launchagents template: tracks and reports failures" {
  grep -q 'failed=0' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  grep -q 'failed=$((failed + 1))' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  grep -q 'LaunchAgent(s) need manual follow-up' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
}

@test "launchagents template: rendered hash changes when existing plist content changes" {
  if ! command -v chezmoi &>/dev/null; then
    skip "chezmoi not installed"
  fi

  local fixture="$TEST_DIR/dotfiles-fixture"
  cp -R "$TEST_DOTFILES" "$fixture"

  local source="$fixture/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  local before="$TEST_DIR/launchagents-before.sh"
  local after="$TEST_DIR/launchagents-after.sh"

  {
    printf '{{- $_ := set . "profile" "full" -}}\n'
    cat "$source"
  } | chezmoi execute-template --source "$fixture" > "$before"
  printf '\n<!-- regression sentinel -->\n' >> "$fixture/launchagents/com.dotfiles.dotfiles-sync.plist.tmpl"
  {
    printf '{{- $_ := set . "profile" "full" -}}\n'
    cat "$source"
  } | chezmoi execute-template --source "$fixture" > "$after"

  local before_hash after_hash
  before_hash="$(grep '^# launchagents hash:' "$before")"
  after_hash="$(grep '^# launchagents hash:' "$after")"

  [ "$before_hash" != "$after_hash" ]
}

@test "launchagents: should_skip_agent skips morning on core profile" {
  # Source the function in an isolated env
  PROFILE="core"
  AUTO_UPGRADE="false"
  eval "$(sed -n '/^should_skip_agent/,/^}/p' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl")"

  # morning requires full profile
  should_skip_agent "morning"
}

@test "launchagents: should_skip_agent allows morning on full profile" {
  PROFILE="full"
  AUTO_UPGRADE="false"
  eval "$(sed -n '/^should_skip_agent/,/^}/p' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl")"

  # morning should NOT be skipped on full
  ! should_skip_agent "morning"
}

@test "launchagents: should_skip_agent skips cursor-at-login on core profile" {
  PROFILE="core"
  AUTO_UPGRADE="false"
  eval "$(sed -n '/^should_skip_agent/,/^}/p' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl")"

  should_skip_agent "cursor-at-login"
}

@test "launchagents: should_skip_agent gates cursor-at-login on Cursor.app presence" {
  grep -A3 'cursor-at-login)' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl" | grep -q '/Applications/Cursor.app'
}

@test "launchagents: should_skip_agent skips dotfiles-upgrade when auto_upgrade=false" {
  PROFILE="full"
  AUTO_UPGRADE="false"
  eval "$(sed -n '/^should_skip_agent/,/^}/p' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl")"

  should_skip_agent "dotfiles-upgrade"
}

@test "launchagents: should_skip_agent allows dotfiles-upgrade when auto_upgrade=true" {
  PROFILE="full"
  AUTO_UPGRADE="true"
  eval "$(sed -n '/^should_skip_agent/,/^}/p' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl")"

  ! should_skip_agent "dotfiles-upgrade"
}

@test "launchagents: should_skip_agent skips both sync agents when auto_sync=false" {
  PROFILE="full"
  AUTO_SYNC="false"
  eval "$(sed -n '/^should_skip_agent/,/^}/p' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl")"

  should_skip_agent "dotfiles-sync"
  should_skip_agent "tooling-sync"
}

@test "launchagents: should_skip_agent keeps both sync agents by default" {
  PROFILE="full"
  unset AUTO_SYNC
  eval "$(sed -n '/^should_skip_agent/,/^}/p' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl")"

  ! should_skip_agent "dotfiles-sync"
  ! should_skip_agent "tooling-sync"
}

@test "launchagents template: auto_sync re-renders the lifecycle script" {
  grep -q '^# auto_sync: {{ dig "auto_sync" true . }}' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
}

@test "sync doctor skips scheduled-sync checks when auto_sync=false" {
  grep -q 'dig "auto_sync" true' "$TEST_DOTFILES/modules/sync/doctor.sh"
  grep -q '_AUTO_SYNC_ENABLED" != "false"' "$TEST_DOTFILES/modules/sync/doctor.sh"
}

@test "launchagents: exactly one agent runs the weekly upgrade" {
  local count
  count="$(grep -l 'bin/dotfiles-upgrade' "$TEST_DOTFILES"/launchagents/*.plist* | wc -l | tr -d ' ')"
  [ "$count" -eq 1 ]
}

@test "launchagents: the lifecycle script removes duplicate agents" {
  local script="$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl"
  grep -q 'source "$SOURCE_DIR/lib/launchagent-duplicates.sh"' "$script"
  grep -q 'launchagent_remove_duplicates "$HOME/Library/LaunchAgents" "$SOURCE_DIR"' "$script"
  grep -q 'remove_skipped_agent "$short" "$dst_name" && return 0' "$script"
  # chezmoi re-runs the script only when its rendered text changes; the
  # duplicate rules' hash in the header makes a rules fix re-run it.
  grep -q 'include "lib/launchagent-duplicates.sh" | sha256sum' "$script"
}

@test "launchagents: should_skip_agent allows core agents regardless of profile" {
  PROFILE="core"
  AUTO_UPGRADE="false"
  eval "$(sed -n '/^should_skip_agent/,/^}/p' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl")"

  # Core agents (capslock-control, dotfiles-sync, etc.) should not be skipped
  ! should_skip_agent "capslock-control"
  ! should_skip_agent "dotfiles-sync"
  ! should_skip_agent "dotfiles-doctor"
  ! should_skip_agent "cleanup"
  ! should_skip_agent "git-maintain"
}

# ── run_after_cache-inits.sh ─────────────────────────────────────

@test "cache-inits: uses strict mode" {
  grep -q 'set -euo pipefail' "$TEST_DOTFILES/.chezmoiscripts/run_after_cache-inits.sh"
}

@test "cache-inits: creates cache directories" {
  # Mock all tools as missing
  cat > "$MOCK_BIN/fzf" << 'MOCK'
#!/bin/bash
exit 1
MOCK
  chmod +x "$MOCK_BIN/fzf"

  mkdir -p "$HOME/.cache/zsh"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_cache-inits.sh"
  [ -d "$HOME/.cache/zsh" ]
  [ -d "$HOME/.cache/node-compile" ]
  [ -d "$HOME/.notes" ]
}

@test "cache-inits: caches fzf init when fzf available" {
  cat > "$MOCK_BIN/fzf" << 'MOCK'
#!/bin/bash
if [ "${1:-}" = "--zsh" ]; then echo "# fzf zsh init"; fi
MOCK
  chmod +x "$MOCK_BIN/fzf"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_cache-inits.sh"
  [ -f "$HOME/.cache/zsh/fzf.zsh" ]
  grep -q "fzf zsh init" "$HOME/.cache/zsh/fzf.zsh"
}

@test "cache-inits: caches zoxide init when zoxide available" {
  cat > "$MOCK_BIN/zoxide" << 'MOCK'
#!/bin/bash
if [ "${1:-}" = "init" ]; then echo "# zoxide init"; fi
MOCK
  chmod +x "$MOCK_BIN/zoxide"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_cache-inits.sh"
  [ -f "$HOME/.cache/zsh/zoxide.zsh" ]
  grep -q "zoxide init" "$HOME/.cache/zsh/zoxide.zsh"
}

@test "cache-inits: caches fnm init when fnm available" {
  cat > "$MOCK_BIN/fnm" << 'MOCK'
#!/bin/bash
if [ "${1:-}" = "env" ]; then echo "# fnm env"; fi
MOCK
  chmod +x "$MOCK_BIN/fnm"

  cat > "$MOCK_BIN/uname" << 'MOCK'
#!/bin/bash
echo "arm64"
MOCK
  chmod +x "$MOCK_BIN/uname"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_cache-inits.sh"
  [ -f "$HOME/.cache/zsh/fnm.zsh" ]
}

@test "cache-inits: guards each tool with command -v check" {
  # Verify each tool init is gated behind a command -v check
  # This ensures missing tools don't crash the script
  local script="$TEST_DOTFILES/.chezmoiscripts/run_after_cache-inits.sh"
  for tool in fzf zoxide starship fnm; do
    grep -q "command -v $tool" "$script" || {
      echo "Missing command -v guard for $tool"
      return 1
    }
  done
}

@test "cache-inits: caches starship init when starship available" {
  cat > "$MOCK_BIN/starship" << 'MOCK'
#!/bin/bash
if [ "${1:-}" = "init" ]; then echo "# starship zsh init"; fi
MOCK
  chmod +x "$MOCK_BIN/starship"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_cache-inits.sh"

  [ "$status" -eq 0 ]
  [ -f "$HOME/.cache/zsh/starship.zsh" ]
  grep -q "starship zsh init" "$HOME/.cache/zsh/starship.zsh"
}

@test "cache-inits: failing tool does not corrupt an existing cache file" {
  # Login-shell regression: a broken upgrade that exits non-zero must NOT
  # truncate the previously-cached init to zero bytes — otherwise users
  # log into a shell with no prompt or completion until they re-run
  # `dotfiles apply` with a working tool.
  mkdir -p "$HOME/.cache/zsh"
  printf '# previous fzf cache\n' > "$HOME/.cache/zsh/fzf.zsh"

  cat > "$MOCK_BIN/fzf" << 'MOCK'
#!/bin/bash
echo "fzf is broken" >&2
exit 1
MOCK
  chmod +x "$MOCK_BIN/fzf"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_cache-inits.sh"

  [ "$status" -eq 0 ]
  [ -s "$HOME/.cache/zsh/fzf.zsh" ]
  grep -Fq 'previous fzf cache' "$HOME/.cache/zsh/fzf.zsh"
  [[ "$output" != *"Cached fzf"* ]]
  # Lingering temp files would leak across applies — verify the helper
  # cleans up the failed tmpfile before returning.
  ! find "$HOME/.cache/zsh" -name 'fzf.zsh.*' -print -quit | grep -q .
}

@test "cache-inits: idempotent rerun keeps stable content and no temp leftovers" {
  cat > "$MOCK_BIN/fzf" << 'MOCK'
#!/bin/bash
if [ "${1:-}" = "--zsh" ]; then echo "# fzf zsh init"; fi
MOCK
  chmod +x "$MOCK_BIN/fzf"

  bash "$TEST_DOTFILES/.chezmoiscripts/run_after_cache-inits.sh"
  first_hash="$(shasum "$HOME/.cache/zsh/fzf.zsh" | awk '{print $1}')"

  bash "$TEST_DOTFILES/.chezmoiscripts/run_after_cache-inits.sh"
  second_hash="$(shasum "$HOME/.cache/zsh/fzf.zsh" | awk '{print $1}')"

  [ "$first_hash" = "$second_hash" ]
  ! find "$HOME/.cache/zsh" -name '*.XXXXXX' -print -quit | grep -q .
  ! find "$HOME/.cache/zsh" -name 'fzf.zsh.*' -print -quit | grep -q .
}

@test "cache-inits: tool that emits only on stderr does not produce an empty cache" {
  # Some tools print errors only to stderr and exit 0 with no stdout
  # (e.g., a not-yet-trusted version). The cache must be skipped — an
  # empty file would leave the shell sourcing nothing useful and hide
  # the upstream breakage.
  mkdir -p "$HOME/.cache/zsh"
  rm -f "$HOME/.cache/zsh/zoxide.zsh"

  cat > "$MOCK_BIN/zoxide" << 'MOCK'
#!/bin/bash
echo "zoxide warning: trust required" >&2
MOCK
  chmod +x "$MOCK_BIN/zoxide"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_cache-inits.sh"

  [ "$status" -eq 0 ]
  [ ! -s "$HOME/.cache/zsh/zoxide.zsh" ]
  [[ "$output" != *"Cached zoxide"* ]]
}

@test "cache-inits: fnm receives passthrough arch on non-x86_64 hardware" {
  # The sed substitution only rewrites `x86_64` → `x64`. Anything else
  # (arm64, aarch64, the empty string from a broken `uname`) must be
  # forwarded unchanged so fnm can still resolve a sensible default
  # instead of being handed the raw substitution attempt.
  cat > "$MOCK_BIN/uname" << 'MOCK'
#!/bin/bash
echo "aarch64"
MOCK
  chmod +x "$MOCK_BIN/uname"

  cat > "$MOCK_BIN/fnm" << 'MOCK'
#!/bin/bash
printf '%s\n' "$@" > "$HOME/fnm-args"
echo "# fnm env"
MOCK
  chmod +x "$MOCK_BIN/fnm"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_cache-inits.sh"

  [ "$status" -eq 0 ]
  grep -Fxq 'aarch64' <(awk 'p {print; p=0} /^--arch$/ {p=1}' "$HOME/fnm-args")
}

@test "cache-inits: fails clearly when the cache directory cannot be created" {
  # Replace ~/.cache with a regular file so `mkdir -p` fails. The script
  # must surface an actionable error and exit non-zero rather than
  # continue silently into the cache_init calls (where the missing
  # directory would otherwise turn into a confusing mktemp failure).
  rm -rf "$HOME/.cache"
  printf 'occupied\n' > "$HOME/.cache"

  run bash "$TEST_DOTFILES/.chezmoiscripts/run_after_cache-inits.sh"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Could not create cache"* ]]
}

# ── Cross-cutting concerns ───────────────────────────────────────

@test "all chezmoiscripts: every script has a shebang" {
  for script in "$TEST_DOTFILES"/.chezmoiscripts/run_*; do
    head -1 "$script" | grep -q '#!/bin/bash' || {
      echo "Missing shebang in $(basename "$script")"
      return 1
    }
  done
}

@test "all chezmoiscripts: lifecycle scripts use strict mode" {
  # Check the 5 main lifecycle scripts (run_once, run_onchange, run_after_cache-inits)
  # Exclude run_after_agentbrew-sync.sh and run_after_devin-caffeinate.sh (utility scripts)
  for script in \
    "$TEST_DOTFILES/.chezmoiscripts/run_once_bootstrap.sh" \
    "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl" \
    "$TEST_DOTFILES/.chezmoiscripts/run_onchange_macos.sh.tmpl" \
    "$TEST_DOTFILES/.chezmoiscripts/run_onchange_launchagents.sh.tmpl" \
    "$TEST_DOTFILES/.chezmoiscripts/run_after_cache-inits.sh"; do
    grep -q 'set -euo pipefail' "$script" || {
      echo "Missing strict mode in $(basename "$script")"
      return 1
    }
  done
}

@test "all chezmoiscripts: no hardcoded HOME paths" {
  for script in "$TEST_DOTFILES"/.chezmoiscripts/run_*; do
    # Allow template expressions like {{ .chezmoi.homeDir }} but not literal /Users/
    if grep -qn '/Users/' "$script" 2>/dev/null; then
      echo "Hardcoded /Users/ path found in $(basename "$script")"
      return 1
    fi
  done
}

# ── run_after_install_local_llm.sh.tmpl ───────────────────────────
# local-llm stack — pipx + huggingface model-weights install,
# gated on chezmoi data use_local_ai AND the sentinel file.

LOCAL_LLM_TMPL="$BATS_TEST_DIRNAME/../.chezmoiscripts/run_after_install_local_llm.sh.tmpl"

@test "local-llm template: file exists and uses strict mode" {
  [ -f "$LOCAL_LLM_TMPL" ]
  grep -q 'set -euo pipefail' "$LOCAL_LLM_TMPL"
}

@test "local-llm template: gated on use_local_ai chezmoi flag" {
  # Uses `dig` so a missing key on partial chezmoi data doesn't crash render.
  grep -q '{{- if dig "use_local_ai"' "$LOCAL_LLM_TMPL"
  # The opt-out branch must exit cleanly without running pipx
  grep -q '{{- else' "$LOCAL_LLM_TMPL"
}

@test "local-llm template: pipx uses uv-managed python (dotfiles rule #10)" {
  # Never Homebrew or python.org python — must resolve via uv
  grep -q 'uv python find 3.13' "$LOCAL_LLM_TMPL"
  grep -q 'pipx install --python' "$LOCAL_LLM_TMPL"
  # Negative: must NOT pin python3 (would use whatever is on PATH)
  ! grep -qE 'pipx install --python python3(\.[0-9]+)? ' "$LOCAL_LLM_TMPL"
}

@test "local-llm template: installs huggingface_hub[cli] and aider-chat" {
  grep -q "huggingface_hub\[cli\]" "$LOCAL_LLM_TMPL"
  grep -q "aider-chat" "$LOCAL_LLM_TMPL"
}

@test "local-llm template: model download gated on sentinel file" {
  grep -q '.local-llm-bootstrap-confirmed' "$LOCAL_LLM_TMPL"
  # Sentinel absence must NOT cause the script to fail — exit 0
  local has_sentinel_check=false
  while IFS= read -r line; do
    if [[ "$line" == *'! -f "$_LL_SENTINEL"'* ]]; then
      has_sentinel_check=true
    fi
  done < "$LOCAL_LLM_TMPL"
  $has_sentinel_check
}

@test "local-llm template: hf download is the configured command" {
  grep -q 'download "$_LL_MODEL_REPO"' "$LOCAL_LLM_TMPL"
  grep -q 'huggingface-cli' "$LOCAL_LLM_TMPL"  # legacy fallback
}

@test "local-llm template: defaults to Qwen3-Coder-30B but env-overridable" {
  grep -q 'Qwen/Qwen3-Coder-30B-A3B-Instruct-MLX-4bit' "$LOCAL_LLM_TMPL"
  grep -q 'LOCAL_LLM_MODEL_REPO' "$LOCAL_LLM_TMPL"
}

_render_local_llm_template() {
  local enabled="$1"
  local out="$TEST_DIR/run_after_install_local_llm.rendered.sh"
  {
    printf '{{- $_ := set . "use_local_ai" %s -}}\n' "$enabled"
    cat "$LOCAL_LLM_TMPL"
  } | chezmoi execute-template --source "$TEST_DOTFILES" > "$out"
  chmod +x "$out"
  printf '%s\n' "$out"
}

_install_mock_uv_python() {
  local py="$HOME/.local/share/uv/python/cpython-3.13/bin/python3.13"
  mkdir -p "$(dirname "$py")"
  printf '#!/bin/bash\nexit 0\n' > "$py"
  chmod +x "$py"
  cat > "$MOCK_BIN/uv" <<MOCK
#!/bin/bash
printf '%s\n' "uv \$*" >> "\$HOME/local-llm-calls.log"
if [ "\${1:-}" = "python" ] && [ "\${2:-}" = "find" ]; then
  printf '%s\n' "$py"
  exit 0
fi
exit 0
MOCK
  chmod +x "$MOCK_BIN/uv"
}

@test "local-llm installer: without sentinel installs small pipx deps but skips model download" {
  TEST_DOTFILES="$BATS_TEST_DIRNAME/.."
  _install_mock_uv_python
  cat > "$MOCK_BIN/pipx" <<'MOCK'
#!/bin/bash
printf '%s\n' "pipx $*" >> "$HOME/local-llm-calls.log"
[ "${1:-}" = "list" ] && exit 0
exit 0
MOCK
  chmod +x "$MOCK_BIN/pipx"
  cat > "$MOCK_BIN/hf" <<'MOCK'
#!/bin/bash
printf '%s\n' "hf $*" >> "$HOME/local-llm-calls.log"
exit 0
MOCK
  chmod +x "$MOCK_BIN/hf"

  local rendered
  rendered="$(_render_local_llm_template true)"
  run bash "$rendered"

  [ "$status" -eq 0 ]
  grep -Fq "pipx install --python" "$HOME/local-llm-calls.log"
  grep -Fq "huggingface_hub[cli]" "$HOME/local-llm-calls.log"
  grep -Fq "aider-chat" "$HOME/local-llm-calls.log"
  ! grep -Fq "hf download" "$HOME/local-llm-calls.log"
  [[ "$output" == *"Sentinel absent"* ]]
}

@test "local-llm installer: sentinel downloads model when cache is missing" {
  TEST_DOTFILES="$BATS_TEST_DIRNAME/.."
  _install_mock_uv_python
  mkdir -p "$HOME/.config/dotfiles"
  touch "$HOME/.config/dotfiles/.local-llm-bootstrap-confirmed"
  cat > "$MOCK_BIN/pipx" <<'MOCK'
#!/bin/bash
printf '%s\n' "pipx $*" >> "$HOME/local-llm-calls.log"
if [ "${1:-}" = "list" ]; then
  printf '%s\n' "huggingface-hub 1.0.0"
  printf '%s\n' "aider-chat 1.0.0"
fi
exit 0
MOCK
  chmod +x "$MOCK_BIN/pipx"
  cat > "$MOCK_BIN/hf" <<'MOCK'
#!/bin/bash
printf '%s\n' "hf $*" >> "$HOME/local-llm-calls.log"
exit 0
MOCK
  chmod +x "$MOCK_BIN/hf"

  local rendered
  rendered="$(_render_local_llm_template true)"
  run bash "$rendered"

  [ "$status" -eq 0 ]
  grep -Fq "hf download Qwen/Qwen3-Coder-30B-A3B-Instruct-MLX-4bit" "$HOME/local-llm-calls.log"
}

@test "local-llm installer: cached model skips repeated hf download" {
  TEST_DOTFILES="$BATS_TEST_DIRNAME/.."
  _install_mock_uv_python
  mkdir -p "$HOME/.config/dotfiles"
  touch "$HOME/.config/dotfiles/.local-llm-bootstrap-confirmed"
  mkdir -p "$HOME/.cache/huggingface/hub/models--Qwen--Qwen3-Coder-30B-A3B-Instruct-MLX-4bit"
  cat > "$MOCK_BIN/pipx" <<'MOCK'
#!/bin/bash
printf '%s\n' "pipx $*" >> "$HOME/local-llm-calls.log"
if [ "${1:-}" = "list" ]; then
  printf '%s\n' "huggingface-hub 1.0.0"
  printf '%s\n' "aider-chat 1.0.0"
fi
exit 0
MOCK
  chmod +x "$MOCK_BIN/pipx"
  cat > "$MOCK_BIN/hf" <<'MOCK'
#!/bin/bash
printf '%s\n' "hf $*" >> "$HOME/local-llm-calls.log"
exit 0
MOCK
  chmod +x "$MOCK_BIN/hf"

  local rendered
  rendered="$(_render_local_llm_template true)"
  run bash "$rendered"

  [ "$status" -eq 0 ]
  ! grep -Fq "hf download" "$HOME/local-llm-calls.log"
  [[ "$output" == *"Model weights already cached"* ]]
}

# ── brew template — local-AI additions ────────────────────────────

@test "brew template: pipx is in the core Brewfile" {
  grep -q 'brew "pipx"' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
}

@test "brew template: mlx-lm install gated on use_local_ai + Apple Silicon" {
  # Must check use_local_ai (chezmoi-level) — uses dig for missing-key safety
  grep -q '{{ if dig "use_local_ai"' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
  # Must runtime-check arm64 (bash-level, since chezmoi has no arch func)
  grep -q 'uname -m.*arm64' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
  # Must skip cleanly under Rosetta
  grep -q 'sysctl.proc_translated' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
  # Must call brew install mlx-lm
  grep -q 'brew install mlx-lm' "$TEST_DOTFILES/.chezmoiscripts/run_onchange_brew.sh.tmpl"
}

@test "chezmoi data: use_local_ai prompt exists with safe default false" {
  grep -q 'use_local_ai' "$TEST_DOTFILES/.chezmoi.yaml.tmpl"
  # The prompt must default to false (~30 GB download requires opt-in)
  grep -E 'promptBoolOnce.*"use_local_ai".*false' "$TEST_DOTFILES/.chezmoi.yaml.tmpl"
}
