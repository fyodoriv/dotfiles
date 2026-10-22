#!/usr/bin/env bats
# One update-tooling refresh runs `chezmoi apply` at most once (issue #244).
# Each test runs the skill's own step 3 "Dotfiles" block (dotfiles-sync, then
# `dotfiles apply --if-changed`, both through dotfiles-lock-checked) against a
# fixture applied checkout. A fake chezmoi logs every apply.

load test_helper

REPO_ROOT="$BATS_TEST_DIRNAME/.."
SKILL="$REPO_ROOT/skills/update-tooling/SKILL.md"
CANON="feat/chezmoi"

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME" "$TEST_DIR/fakebin"
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.com
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.com
  unset DOTFILES_DIR DOTFILES_LOCK XDG_STATE_HOME XDG_CONFIG_HOME DOTFILES_PLUGINS_LOCK
  APPLY_LOG="$TEST_DIR/chezmoi-apply.log"
  DRIFT_FILE="$TEST_DIR/drift"

  # The remote holds a minimal dotfiles source with the real scripts the
  # step runs. The doctor and the LaunchAgent reload are stubs.
  local seed="$TEST_DIR/seed"
  git init --quiet --initial-branch="$CANON" "$seed"
  mkdir -p "$seed/bin" "$seed/config"
  for f in dotfiles dotfiles-sync dotfiles-lock-checked; do
    cp "$REPO_ROOT/bin/$f" "$seed/bin/"
  done
  cp -R "$REPO_ROOT/lib" "$seed/lib"
  printf '#!/bin/bash\necho doctor >> "%s/calls.log"\n' "$TEST_DIR" > "$seed/bin/dotfiles-doctor"
  printf '#!/bin/bash\necho reload >> "%s/calls.log"\n' "$TEST_DIR" > "$seed/bin/dotfiles-reload-launchagents"
  chmod +x "$seed/bin/"*
  printf '# none\n' > "$seed/config/public-push-remotes.txt"
  echo "a = 1" > "$seed/dot_testrc"
  git -C "$seed" add -A
  git -C "$seed" commit --quiet --no-verify -m "chore: initial"
  git clone --quiet --bare "$seed" "$TEST_DIR/remote.git"
  git clone --quiet "$TEST_DIR/remote.git" "$TEST_DIR/dotfiles"

  # A host chezmoi apply would make the step wait up to 5 minutes.
  printf '#!/bin/bash\nexit 1\n' > "$TEST_DIR/fakebin/pgrep"
  chmod +x "$TEST_DIR/fakebin/pgrep"
  export PATH="$TEST_DIR/fakebin:$PATH"

  # The step as the skill writes it.
  awk '
    /^### Dotfiles$/ { in_section = 1; next }
    in_section && /^### / { exit }
    in_section && /^```bash$/ { in_block = 1; next }
    in_block && /^```$/ { exit }
    in_block { print }
  ' "$SKILL" > "$TEST_DIR/step3.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# A fake chezmoi whose source-path is $1. It logs each apply. `chezmoi
# status` prints the content of $DRIFT_FILE, and an apply converges it.
write_fake_chezmoi() {
  cat > "$TEST_DIR/fakebin/chezmoi" <<FAKE
#!/bin/bash
case "\$1" in
  source-path) printf '%s\n' "$1" ;;
  status) [ ! -s "$DRIFT_FILE" ] || cat "$DRIFT_FILE" ;;
  apply) echo "apply \${*:2}" >> "$APPLY_LOG"; rm -f "$DRIFT_FILE" ;;
esac
FAKE
  chmod +x "$TEST_DIR/fakebin/chezmoi"
}

# The applied checkout is a linked worktree on its own branch that tracks the
# canonical branch (the layout dotfiles-sync fast-forwards itself).
use_linked_applied_checkout() {
  APPLIED="$TEST_DIR/applied"
  git -C "$TEST_DIR/dotfiles" worktree add --quiet -b "applied/feat-chezmoi" "$APPLIED" "origin/$CANON"
  git -C "$APPLIED" branch --quiet --set-upstream-to="origin/$CANON"
  write_fake_chezmoi "$APPLIED"
}

# The applied checkout is the primary checkout on the canonical branch, which
# step 2 fast-forwards before step 3 runs.
use_primary_applied_checkout() {
  APPLIED="$TEST_DIR/dotfiles"
  write_fake_chezmoi "$APPLIED"
}

push_remote_commit() {
  local clone="$TEST_DIR/clone2"
  rm -rf "$clone"
  git clone --quiet "$TEST_DIR/remote.git" "$clone"
  echo "a = $RANDOM" > "$clone/dot_testrc"
  git -C "$clone" commit --quiet --no-verify -am "chore: remote update"
  git -C "$clone" push --quiet origin "$CANON"
}

# Run one refresh of step 3 and print how many chezmoi applies it ran.
refresh() {
  local before after
  before="$(applies)"
  run bash "$TEST_DIR/step3.sh"
  after="$(applies)"
  REFRESH_APPLIES=$((after - before))
}

applies() {
  if [ -f "$APPLY_LOG" ]; then wc -l < "$APPLY_LOG" | tr -d ' '; else echo 0; fi
}

assert_refresh_applies() {
  echo "chezmoi apply runs in this refresh: $REFRESH_APPLIES (want $1)"
  echo "$output"
  [ "$status" -eq 0 ]
  [ "$REFRESH_APPLIES" -eq "$1" ]
}

@test "the step 3 block wraps sync and the --if-changed apply in dotfiles-lock-checked" {
  grep -qF 'DOTFILES_APPLIED="$(chezmoi source-path)"' "$TEST_DIR/step3.sh"
  grep -qF '"$CHECKED" -- "$DOTFILES_APPLIED/bin/dotfiles-sync"' "$TEST_DIR/step3.sh"
  grep -qF '"$CHECKED" -- "$DOTFILES_APPLIED/bin/dotfiles" apply --if-changed' "$TEST_DIR/step3.sh"
}

@test "first refresh with no apply record runs chezmoi apply once" {
  use_linked_applied_checkout
  refresh
  assert_refresh_applies 1
  [[ "$output" == *"chezmoi re-applied"* ]]
  [[ "$output" == *"skipped chezmoi apply and doctor"* ]]
}

@test "refresh after a new commit runs chezmoi apply once (linked applied checkout)" {
  use_linked_applied_checkout
  refresh
  push_remote_commit
  refresh
  assert_refresh_applies 1
  [ "$(git -C "$APPLIED" rev-parse HEAD)" = "$(git -C "$TEST_DIR/remote.git" rev-parse "$CANON")" ]
  [[ "$output" == *"chezmoi re-applied"* ]]
  [[ "$output" == *"skipped chezmoi apply and doctor"* ]]
}

@test "refresh after step 2 fast-forwarded the primary checkout runs chezmoi apply once" {
  use_primary_applied_checkout
  refresh
  push_remote_commit
  git -C "$APPLIED" fetch --quiet origin
  git -C "$APPLIED" merge --quiet --ff-only "origin/$CANON"
  refresh
  assert_refresh_applies 1
  [[ "$output" == *"skipped chezmoi apply and doctor"* ]]
}

@test "refresh with nothing new runs no chezmoi apply" {
  use_linked_applied_checkout
  refresh
  refresh
  assert_refresh_applies 0
  [[ "$output" == *"no new commits or drift, skipped chezmoi apply"* ]]
  [[ "$output" == *"skipped chezmoi apply and doctor"* ]]
}

@test "refresh after a hand edit runs chezmoi apply once and names the drift" {
  use_primary_applied_checkout
  refresh
  echo "MM .testrc" > "$DRIFT_FILE"
  refresh
  assert_refresh_applies 1
  [[ "$output" == *"Drift since the last apply"*".testrc"* ]]
  [[ "$output" == *"skipped chezmoi apply and doctor"* ]]
}
