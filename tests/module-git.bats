#!/usr/bin/env bats
# Functional tests for modules/git/doctor.sh

load test_helper

setup() {
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"

  mkdir -p "$TEST_HOME"
  mkdir -p "$TEST_DOTFILES/home"
  mkdir -p "$TEST_DOTFILES/bin"
  mkdir -p "$TEST_DOTFILES/git-hooks"

  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  # Point git config --global to isolated temp file
  export GIT_CONFIG_GLOBAL="$TEST_DIR/gitconfig"
  touch "$GIT_CONFIG_GLOBAL"
  # Prevent dynamic worktree scan from touching real repos
  export DOTFILES_REPOS_DIR="$TEST_DIR/repos"
  mkdir -p "$DOTFILES_REPOS_DIR"

  # Doctor framework state
  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"
  touch "$OVERRIDES_FILE"
  FIX_MODE=false
  LIST_MODE=false
  pass_count=0
  fail_count=0
  fix_count=0
  skip_count=0
  fail_messages=()

  pass()    { pass_count=$((pass_count + 1)); }
  fail()    { fail_count=$((fail_count + 1)); fail_messages+=("$1"); }
  fixed()   { fix_count=$((fix_count + 1)); }
  skipped() { skip_count=$((skip_count + 1)); }

  is_overridden() { grep -qx "$1" "$OVERRIDES_FILE" 2>/dev/null; }

  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="$4"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if eval "$test_cmd" >/dev/null 2>&1; then
      pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then
      if eval "$fix_cmd" >/dev/null 2>&1; then fixed "$desc"; else fail "$desc"; fi
    else
      fail "$desc"
    fi
  }

  check_symlink() {
    local id="$1" src="$2" dst="$3"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$desc"; return; fi
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
      pass "$dst"
    elif $FIX_MODE; then
      mkdir -p "$(dirname "$dst")"
      [ -f "$dst" ] && mv "$dst" "${dst}.backup" 2>/dev/null
      [ -L "$dst" ] && rm "$dst"
      ln -s "$src" "$dst"
      fixed "$dst"
    else
      fail "$dst"
    fi
  }

  check_managed() {
    local id="$1" src="$2" dst="$3"
    if $LIST_MODE; then return; fi
    if is_overridden "$id"; then skipped "$dst"; return; fi
    if [ -f "$dst" ]; then
      pass "$dst"
    elif $FIX_MODE; then
      mkdir -p "$(dirname "$dst")"
      cp "$src" "$dst" 2>/dev/null && fixed "$dst" || fail "$dst"
    else
      fail "$dst"
    fi
  }

  # Create source files that the module expects
  echo "[core]" > "$TEST_DOTFILES/home/gitconfig"
  echo "[core]" > "$TEST_DOTFILES/dot_gitconfig.tmpl"
  echo "*.DS_Store" > "$TEST_DOTFILES/home/gitignore_global"
  echo "subject line" > "$TEST_DOTFILES/home/gitcommit_template"
  echo "#!/bin/bash" > "$TEST_DOTFILES/home/git-editor"
  echo "#!/bin/bash" > "$TEST_DOTFILES/bin/git-safe"

  # Mock gh CLI to return expected values
  gh() {
    if [ "$1" = "config" ] && [ "$2" = "get" ]; then echo "ssh"; return 0; fi
    return 1
  }
  export -f gh 2>/dev/null || true
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "git: managed file and symlinks pass when correctly set up" {
  cp "$TEST_DOTFILES/dot_gitconfig.tmpl" "$TEST_HOME/.gitconfig"
  ln -s "$TEST_DOTFILES/home/gitignore_global" "$TEST_HOME/.gitignore_global"
  ln -s "$TEST_DOTFILES/home/gitcommit_template" "$TEST_HOME/.gitcommit_template"
  ln -s "$TEST_DOTFILES/home/git-editor" "$TEST_HOME/.git-editor"
  source "$BATS_TEST_DIRNAME/../modules/git/doctor.sh"
  [ "$pass_count" -ge 4 ]
}

@test "git: symlinks fail when missing" {
  source "$BATS_TEST_DIRNAME/../modules/git/doctor.sh"
  [ "$fail_count" -ge 4 ]
}

@test "git: fix mode creates missing symlinks and managed files" {
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/git/doctor.sh"
  [ "$fix_count" -ge 4 ]
  [ -f "$TEST_HOME/.gitconfig" ]
  [ -L "$TEST_HOME/.gitignore_global" ]
}

@test "git: local_config passes when file exists" {
  touch "$TEST_HOME/.gitconfig.local"
  source "$BATS_TEST_DIRNAME/../modules/git/doctor.sh"
  # local_config should pass (among others)
  local total=$((pass_count + fail_count + fix_count + skip_count))
  [ "$total" -gt 0 ]
  # Specifically: set up all symlinks + local config to isolate
  rm -rf "$TEST_DIR"
  TEST_DIR="$(mktemp -d)"
  TEST_HOME="$TEST_DIR/home"
  TEST_DOTFILES="$TEST_DIR/dotfiles"
  mkdir -p "$TEST_HOME" "$TEST_DOTFILES/home" "$TEST_DOTFILES/bin" "$TEST_DOTFILES/git-hooks"
  export HOME="$TEST_HOME"
  export DOTFILES_DIR="$TEST_DOTFILES"
  export GIT_CONFIG_GLOBAL="$TEST_DIR/gitconfig"
  touch "$GIT_CONFIG_GLOBAL"
  export DOTFILES_REPOS_DIR="$TEST_DIR/repos"
  mkdir -p "$DOTFILES_REPOS_DIR"
  OVERRIDES_FILE="$TEST_DOTFILES/.overrides"
  touch "$OVERRIDES_FILE"
  echo "[core]" > "$TEST_DOTFILES/home/gitconfig"
  echo "[core]" > "$TEST_DOTFILES/dot_gitconfig.tmpl"
  echo "*.DS_Store" > "$TEST_DOTFILES/home/gitignore_global"
  echo "subject" > "$TEST_DOTFILES/home/gitcommit_template"
  echo "#!/bin/bash" > "$TEST_DOTFILES/home/git-editor"
  echo "#!/bin/bash" > "$TEST_DOTFILES/bin/git-safe"
  touch "$TEST_HOME/.gitconfig.local"
  pass_count=0; fail_count=0
  source "$BATS_TEST_DIRNAME/../modules/git/doctor.sh"
  # local_config is 1 of the pass checks
  [ "$pass_count" -ge 1 ]
}

@test "git: git config checks pass when all configured" {
  # Isolate gh from the operator's config; stub auth/scope probes the doctor runs.
  export GH_CONFIG_DIR="$TEST_DIR/gh-config"
  mkdir -p "$GH_CONFIG_DIR"
  gh() {
    case "$1" in
      config)
        if [ "$2" = "get" ] && [ "$3" = "git_protocol" ]; then
          echo ssh
          return 0
        fi
        return 0
        ;;
      auth)
        if [ "$2" = "status" ]; then
          echo "Token scopes: repo, gist, read:org, workflow, admin:public_key, delete_repo"
          return 0
        fi
        ;;
    esac
    return 1
  }
  export -f gh 2>/dev/null || true

  git -C "$TEST_DOTFILES" init -q
  git config --global user.name "Test User"
  git config --global user.email "test@example.com"
  if [ -d "$BATS_TEST_DIRNAME/../git-hooks" ]; then
    cp -R "$BATS_TEST_DIRNAME/../git-hooks/." "$TEST_DOTFILES/git-hooks/"
    git -C "$TEST_DOTFILES" add git-hooks
    git -C "$TEST_DOTFILES" commit -q -m "seed git-hooks for integrity checks" --no-gpg-sign
  fi
  # The hook self-tests (run on every machine) need the readiness library.
  mkdir -p "$TEST_DOTFILES/lib"
  cp "$BATS_TEST_DIRNAME/../lib/oss-readiness.sh" "$TEST_DOTFILES/lib/oss-readiness.sh"

  git config --global pull.rebase true
  git config --global push.autoSetupRemote true
  git config --global core.pager "delta"
  git config --global rerere.enabled true
  git config --global diff.algorithm histogram
  git config --global fetch.prune true
  git config --global rebase.autoStash true
  git config --global core.fsmonitor false
  git config --global maintenance.auto true
  git config --global alias.wip "commit -m wip"
  git config --global core.hooksPath "$TEST_DOTFILES/git-hooks"
  git config --global user.name "Test User"
  git config --global user.email "test@example.com"
  chmod +x "$TEST_DOTFILES/bin/git-safe"
  # Set up managed file + symlinks to avoid file check failures
  cp "$TEST_DOTFILES/dot_gitconfig.tmpl" "$TEST_HOME/.gitconfig"
  ln -s "$TEST_DOTFILES/home/gitignore_global" "$TEST_HOME/.gitignore_global"
  ln -s "$TEST_DOTFILES/home/gitcommit_template" "$TEST_HOME/.gitcommit_template"
  ln -s "$TEST_DOTFILES/home/git-editor" "$TEST_HOME/.git-editor"
  touch "$TEST_HOME/.gitconfig.local"
  source "$BATS_TEST_DIRNAME/../modules/git/doctor.sh"
  # All checks except splitindex (needs --unset) should pass
  [ "$pass_count" -ge 14 ]
  [ "$fail_count" -eq 0 ]
}

@test "git: hook self-tests run without a personal remote" {
  # GitHub.com is canonical on every machine, so the privacy hooks must be
  # checked even when no `personal` remote exists. The fixture has no hooks.
  git -C "$TEST_DOTFILES" init -q
  source "$BATS_TEST_DIRNAME/../modules/git/doctor.sh"
  printf '%s\n' "${fail_messages[@]}" | grep -q "pre-commit hook self-test"
  printf '%s\n' "${fail_messages[@]}" | grep -q "pre-push hook self-test"
}

@test "git: shipped wip alias commits only staged changes" {
  run git config --file "$BATS_TEST_DIRNAME/../dot_gitconfig.tmpl" alias.wip
  [ "$status" -eq 0 ]
  [ "$output" = "commit -m wip" ]
}

@test "git: doctor flags unsafe add-all aliases" {
  git config --global alias.wip "!git add -A && git commit -m wip"
  git config --global alias.stage-all "!git add ."

  source "$BATS_TEST_DIRNAME/../modules/git/doctor.sh"

  [[ " ${fail_messages[*]} " == *"global git aliases avoid add-all staging"* ]]
  run git_unsafe_add_aliases
  [ "$status" -eq 0 ]
  [[ "$output" == *"alias.wip"* ]]
  [[ "$output" == *"alias.stage-all"* ]]
}

@test "git: git config checks fail when not configured" {
  # Empty git config — all config checks should fail
  source "$BATS_TEST_DIRNAME/../modules/git/doctor.sh"
  # 4 symlinks + local_config + 10 config checks + safe_guard + hooks_path = many failures
  [ "$fail_count" -ge 10 ]
}

@test "git: fix mode repairs git config settings" {
  FIX_MODE=true
  # Set up managed file + symlinks so only config checks need fixing
  cp "$TEST_DOTFILES/dot_gitconfig.tmpl" "$TEST_HOME/.gitconfig"
  ln -s "$TEST_DOTFILES/home/gitignore_global" "$TEST_HOME/.gitignore_global"
  ln -s "$TEST_DOTFILES/home/gitcommit_template" "$TEST_HOME/.gitcommit_template"
  ln -s "$TEST_DOTFILES/home/git-editor" "$TEST_HOME/.git-editor"
  touch "$TEST_HOME/.gitconfig.local"
  chmod +x "$TEST_DOTFILES/bin/git-safe"
  source "$BATS_TEST_DIRNAME/../modules/git/doctor.sh"
  [ "$fix_count" -ge 5 ]
  # Verify fix actually applied
  [ "$(git config --global pull.rebase)" = "true" ]
  [ "$(git config --global rerere.enabled)" = "true" ]
}

@test "git: overrides skip checks" {
  echo "managed.gitconfig" >> "$OVERRIDES_FILE"
  echo "symlink.gitignore" >> "$OVERRIDES_FILE"
  echo "git.pull_rebase" >> "$OVERRIDES_FILE"
  source "$BATS_TEST_DIRNAME/../modules/git/doctor.sh"
  [ "$skip_count" -ge 3 ]
}

@test "git: safe_guard passes when executable" {
  chmod +x "$TEST_DOTFILES/bin/git-safe"
  cp "$TEST_DOTFILES/dot_gitconfig.tmpl" "$TEST_HOME/.gitconfig"
  ln -s "$TEST_DOTFILES/home/gitignore_global" "$TEST_HOME/.gitignore_global"
  ln -s "$TEST_DOTFILES/home/gitcommit_template" "$TEST_HOME/.gitcommit_template"
  ln -s "$TEST_DOTFILES/home/git-editor" "$TEST_HOME/.git-editor"
  source "$BATS_TEST_DIRNAME/../modules/git/doctor.sh"
  # git.safe_guard should be among passes
  [ "$pass_count" -ge 5 ]
}

@test "git: stale local core.hooksPath override is detected (red)" {
  git init -q "$TEST_DOTFILES" 2>/dev/null
  git -C "$TEST_DOTFILES" config --local core.hooksPath /nonexistent/stale/hooks
  source "$BATS_TEST_DIRNAME/../modules/git/doctor.sh"
  [[ " ${fail_messages[*]} " == *"no stale local core.hooksPath override"* ]]
}

@test "git: --fix unsets a stale local core.hooksPath override" {
  git init -q "$TEST_DOTFILES" 2>/dev/null
  git -C "$TEST_DOTFILES" config --local core.hooksPath /nonexistent/stale/hooks
  FIX_MODE=true
  source "$BATS_TEST_DIRNAME/../modules/git/doctor.sh"
  [ -z "$(git -C "$TEST_DOTFILES" config --local --get core.hooksPath 2>/dev/null)" ]
}

@test "git: clean local config passes the hooksPath-override check" {
  git init -q "$TEST_DOTFILES" 2>/dev/null
  source "$BATS_TEST_DIRNAME/../modules/git/doctor.sh"
  [[ " ${fail_messages[*]} " != *"no stale local core.hooksPath override"* ]]
}
