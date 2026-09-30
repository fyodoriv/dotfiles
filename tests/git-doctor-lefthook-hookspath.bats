#!/usr/bin/env bats
# Sister-repo lefthook clobber-prevention check (modules/git/doctor.sh).
# A sister repo that bundles its own lefthook must set a LOCAL
# core.hooksPath, else its `pnpm install` lefthook clobbers dotfiles'
# globally-wired privacy hooks. This test exercises the exact loop body:
# only repos with lefthook.yml AND a local lefthook binary are checked;
# the fix sets a local core.hooksPath.

setup() {
  TEST_DIR="$(mktemp -d)"
  REPOS_DIR="$TEST_DIR/apps"
  DOTFILES_DIR="$REPOS_DIR/dotfiles"
  mkdir -p "$DOTFILES_DIR"

  FIX_MODE=false
  pass_count=0; fail_count=0; fix_count=0
  fail_messages=()
  pass()  { pass_count=$((pass_count + 1)); }
  fail()  { fail_count=$((fail_count + 1)); fail_messages+=("$1"); }
  fixed() { fix_count=$((fix_count + 1)); }

  # check() shape mirrored from bin/dotfiles-doctor.
  check() {
    local id="$1" desc="$2" test_cmd="$3" fix_cmd="$4"
    if eval "$test_cmd" >/dev/null 2>&1; then pass "$desc"
    elif $FIX_MODE && [ -n "$fix_cmd" ]; then
      if eval "$fix_cmd" >/dev/null 2>&1; then fixed "$desc"; else fail "$desc"; fi
    else fail "$desc"; fi
  }

  # Exact loop body from modules/git/doctor.sh.
  _run_lefthook_check() {
    for _lh_repo in "$REPOS_DIR"/*/ "$REPOS_DIR"/tooling/*/; do
      _lh_rp="${_lh_repo%/}"
      [ -d "$_lh_rp/.git" ] || continue
      [ "$_lh_rp" = "$DOTFILES_DIR" ] && continue
      { [ -f "$_lh_rp/lefthook.yml" ] || [ -f "$_lh_rp/lefthook.yaml" ]; } || continue
      [ -x "$_lh_rp/node_modules/.bin/lefthook" ] || continue
      _lh_name="$(basename "$_lh_rp")"
      _lh_local="$(git -C "$_lh_rp" config --local --get core.hooksPath 2>/dev/null || echo "")"
      check "git.lefthook_local_hookspath.$_lh_name" \
        "$_lh_name: lefthook uses a LOCAL core.hooksPath" \
        "[ -n \"$_lh_local\" ]" \
        "git -C \"$_lh_rp\" config --local core.hooksPath .git/hooks && ( cd \"$_lh_rp\" && \"$_lh_rp/node_modules/.bin/lefthook\" install >/dev/null 2>&1 )"
    done
    unset _lh_repo _lh_rp _lh_name _lh_local
  }

  # Build a qualifying sister repo: lefthook.yml + a local lefthook stub.
  _make_lefthook_repo() {
    local repo="$1"
    mkdir -p "$repo/node_modules/.bin"
    git init --quiet "$repo"
    git -C "$repo" config user.email t@e.test
    git -C "$repo" config user.name T
    printf 'pre-commit:\n  commands: {}\n' > "$repo/lefthook.yml"
    printf '#!/bin/sh\nexit 0\n' > "$repo/node_modules/.bin/lefthook"
    chmod +x "$repo/node_modules/.bin/lefthook"
  }
}

teardown() { rm -rf "$TEST_DIR"; }

@test "flags a lefthook repo that inherits the global hooksPath (no local override)" {
  _make_lefthook_repo "$REPOS_DIR/minsky"
  _run_lefthook_check
  [ "$fail_count" -eq 1 ]
  [[ "${fail_messages[0]}" == *"minsky"* ]]
}

@test "--fix sets a local core.hooksPath on the sister repo" {
  _make_lefthook_repo "$REPOS_DIR/minsky"
  FIX_MODE=true
  _run_lefthook_check
  [ "$fix_count" -eq 1 ]
  [ "$(git -C "$REPOS_DIR/minsky" config --local --get core.hooksPath)" = ".git/hooks" ]
}

@test "passes when the sister repo already has a local hooksPath" {
  _make_lefthook_repo "$REPOS_DIR/minsky"
  git -C "$REPOS_DIR/minsky" config --local core.hooksPath .git/hooks
  _run_lefthook_check
  [ "$fail_count" -eq 0 ]
  [ "$pass_count" -eq 1 ]
}

@test "skips a repo without a local lefthook binary (never left hook-less)" {
  mkdir -p "$REPOS_DIR/nohook"
  git init --quiet "$REPOS_DIR/nohook"
  printf 'pre-commit:\n  commands: {}\n' > "$REPOS_DIR/nohook/lefthook.yml"
  # no node_modules/.bin/lefthook
  _run_lefthook_check
  [ "$pass_count" -eq 0 ]
  [ "$fail_count" -eq 0 ]
}

@test "excludes the dotfiles repo itself (it owns the global hooksPath)" {
  _make_lefthook_repo "$DOTFILES_DIR"
  _run_lefthook_check
  [ "$pass_count" -eq 0 ]
  [ "$fail_count" -eq 0 ]
}
