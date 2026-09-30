#!/usr/bin/env bats

load test_helper

GH_WRAPPER="$BATS_TEST_DIRNAME/../bin/gh"

setup() {
  TEST_DIR="$(mktemp -d)"
  GH_STUB="$TEST_DIR/real-gh"
  GH_ARGS="$TEST_DIR/gh-args.txt"
  GH_BODY="$TEST_DIR/gh-body.md"
  cat > "$GH_STUB" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" > "$GH_ARGS"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --body-file|--notes-file)
      shift
      cat "$1" > "$GH_BODY"
      ;;
  esac
  shift || break
done
printf 'https://github.example/pr/1\n'
exit 0
STUB
  chmod +x "$GH_STUB"
  export DOTFILES_REAL_GH="$GH_STUB"
  export GH_ARGS
  export GH_BODY
}

teardown() {
  rm -rf "$TEST_DIR"
}

agent_pr_approval() {
  local repo="$1" base="$2" title="$3" body="$4" body_sha
  body_sha="$(printf '%s' "$body" | shasum -a 256 | awk '{print $1}')"
  printf 'repo=%s base=%s title=%s body_sha256=%s' "$repo" "$base" "$title" "$body_sha"
}

@test "agent PR create allows stacked skill trio (Summary + Delivery plan + Test plan)" {
  local expected_body approval
  expected_body=$'## Why this is needed\nWizard phase B ships data intake.\n\n## Summary\nAdds phase B skill docs.\n\n## Delivery plan\n| Step | PR | Status |\n\n## Test plan\n- [x] bash scripts/run-tests.sh\n\n---\n_🤖 Written by an agent, not Fyodor. Ping me if this looks off._\n'
  approval="$(agent_pr_approval "your-org/example-cli" "master" "feat: phase b" "$expected_body")"

  run env AGENT_PUBLIC_WRITE_GUARD=1 AGENT_PUBLIC_WRITE_APPROVAL="$approval" "$GH_WRAPPER" pr create \
    --repo your-org/example-cli \
    --title "feat: phase b" \
    --base master \
    --body $'## Why this is needed\nWizard phase B ships data intake.\n\n## Summary\nAdds phase B skill docs.\n\n## Delivery plan\n| Step | PR | Status |\n\n## Test plan\n- [x] bash scripts/run-tests.sh'

  [ "$status" -eq 0 ]
  grep -q "Delivery plan" "$GH_BODY"
  grep -q "Test plan" "$GH_BODY"
}

@test "agent PR create blocks Summary-only without full or stacked validation" {
  run env AGENT_PUBLIC_WRITE_GUARD=1 "$GH_WRAPPER" pr create \
    --title "feat: phase b" \
    --base main \
    --body $'## Why this is needed\nShip phase B.\n\n## Summary\nAdds docs only.'

  [ "$status" -eq 1 ]
  [[ "$output" == *"Delivery plan"* ]] || [[ "$output" == *"Requirements checklist"* ]]
}
