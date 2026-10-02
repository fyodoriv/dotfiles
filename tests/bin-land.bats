#!/usr/bin/env bats
load test_helper

SCRIPT="$BATS_TEST_DIRNAME/../bin/land"

# A checkout whose origin is github.com with pushurl DISABLED, like the
# tooling clones. insteadOf redirects the explicit github.com push URL to a
# local bare repo so nothing leaves the machine.
setup_land_repo() {
  LAND_TMP="$(mktemp -d)"
  git init -q --bare "$LAND_TMP/remote.git"
  git init -q -b main "$LAND_TMP/work"
  git -C "$LAND_TMP/work" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m "chore: base"
  git -C "$LAND_TMP/work" remote add origin https://github.com/owner/repo.git
  git -C "$LAND_TMP/work" config remote.origin.pushurl DISABLED
  git -C "$LAND_TMP/work" switch -q -c feat/thing
  git -C "$LAND_TMP/work" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m "feat: thing"
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0="url.$LAND_TMP/remote.git.insteadOf"
  export GIT_CONFIG_VALUE_0="https://github.com/owner/repo.git"

  mkdir -p "$LAND_TMP/bin"
  GH_LOG="$LAND_TMP/gh.log"
  cat > "$LAND_TMP/bin/gh" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$GH_LOG"
case "\$*" in
  "repo view"*) echo main ;;
  "pr view"*) exit 1 ;;
esac
exit 0
STUB
  chmod +x "$LAND_TMP/bin/gh"
  export PATH="$LAND_TMP/bin:$PATH"
  export LAND_ALLOW_NON_TTY=1
  # Agent shells set these; the pushes here go to a local bare repo.
  unset AGENT_PUBLIC_WRITE_GUARD DEVIN_MODEL DEVIN_SESSION_ID CLAUDE_CODE_SSE_PORT CLAUDECODE CURSOR_AGENT WINDSURF_AGENT CODEX_AGENT
}

teardown() {
  [ -n "${LAND_TMP:-}" ] && rm -rf "$LAND_TMP"
  return 0
}

@test "land refuses to run without a terminal" {
  run env -u LAND_ALLOW_NON_TTY bash "$SCRIPT" . < /dev/null
  [ "$status" -eq 3 ]
  [[ "$output" == *"human-only"* ]]
}

@test "land refuses inside an agent shell even with the terminal override" {
  run env LAND_ALLOW_NON_TTY=1 CURSOR_AGENT=1 bash "$SCRIPT" .
  [ "$status" -eq 3 ]
}

@test "land --lease accepts only one checkout" {
  run bash "$SCRIPT" --lease abc123 a b
  [ "$status" -eq 2 ]
  [[ "$output" == *"exactly one DIR"* ]]
}

@test "land pushes the branch to the explicit github.com URL despite pushurl DISABLED" {
  setup_land_repo
  run bash "$SCRIPT" "$LAND_TMP/work"
  [ "$status" -eq 0 ]
  [ "$(git -C "$LAND_TMP/remote.git" rev-parse feat/thing)" = "$(git -C "$LAND_TMP/work" rev-parse HEAD)" ]
  grep -q 'pr create -R owner/repo --head feat/thing --base main --fill' "$GH_LOG"
}

@test "land --dry-run pushes nothing and opens no PR" {
  setup_land_repo
  run bash "$SCRIPT" --dry-run "$LAND_TMP/work"
  [ "$status" -eq 0 ]
  run git -C "$LAND_TMP/remote.git" rev-parse --verify -q feat/thing
  [ "$status" -ne 0 ]
  ! grep -q 'pr create' "$GH_LOG"
}

@test "land refuses the default branch" {
  setup_land_repo
  git -C "$LAND_TMP/work" switch -q main
  run bash "$SCRIPT" "$LAND_TMP/work"
  [ "$status" -eq 1 ]
  [[ "$output" == *"default branch"* ]]
}

@test "land refuses uncommitted tracked changes" {
  setup_land_repo
  echo x > "$LAND_TMP/work/f"
  git -C "$LAND_TMP/work" add f
  run bash "$SCRIPT" "$LAND_TMP/work"
  [ "$status" -eq 1 ]
  [[ "$output" == *"uncommitted"* ]]
}

@test "land refuses a non-github origin" {
  setup_land_repo
  git -C "$LAND_TMP/work" remote set-url origin git@git.example.com:owner/repo.git
  run bash "$SCRIPT" "$LAND_TMP/work"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a github.com repo"* ]]
}

@test "land --lease rewrites only when the remote is still at the old tip" {
  setup_land_repo
  bash "$SCRIPT" "$LAND_TMP/work"
  old="$(git -C "$LAND_TMP/work" rev-parse HEAD)"
  git -C "$LAND_TMP/work" -c user.email=t@example.com -c user.name=t commit -q --amend --allow-empty -m "feat: thing v2"
  run bash "$SCRIPT" --lease 0000000000000000000000000000000000000001 "$LAND_TMP/work"
  [ "$status" -ne 0 ]
  run bash "$SCRIPT" --lease "$old" "$LAND_TMP/work"
  [ "$status" -eq 0 ]
  [ "$(git -C "$LAND_TMP/remote.git" rev-parse feat/thing)" = "$(git -C "$LAND_TMP/work" rev-parse HEAD)" ]
}
